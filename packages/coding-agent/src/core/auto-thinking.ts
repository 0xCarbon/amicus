import type { AgentMessage, ThinkingLevel } from "@earendil-works/pi-agent-core";

/** Difficulty probabilities Jev assigns to trivial, moderate and hard requests. */
export type AutoThinkingProbabilities = readonly [trivial: number, moderate: number, hard: number];

export interface AutoThinkingWindowEntry {
	role: "user" | "assistant" | "tool";
	text: string;
}

export interface AutoThinkingWindow {
	request: string;
	recent: AutoThinkingWindowEntry[];
}

export interface AutoThinkingWindowLimits {
	requestChars: number;
	entryChars: number;
	totalChars: number;
	maxEntries: number;
}

export const AUTO_THINKING_WINDOW_LIMITS: AutoThinkingWindowLimits = {
	requestChars: 4000,
	entryChars: 600,
	totalChars: 4000,
	maxEntries: 8,
};

/** Step below the top level only when Jev is at least this confident the request is easier. */
export const AUTO_THINKING_TRIVIAL_THRESHOLD = 0.7;
export const AUTO_THINKING_MODERATE_THRESHOLD = 0.7;
export const AUTO_THINKING_TIMEOUT_MS = 1000;
export const AUTO_THINKING_API_KEY_ENV = "TYPESAFE_API_KEY";
const JEV_URL = "https://api.typesafe.ai/v1/systemone";
// Thresholds are tuned against a pinned version; aliases move on release.
const JEV_MODEL = "jev-1.14.0";
const DIFFICULTY_RUBRIC = [
	"trivial: a lookup, a mechanical edit, or a short factual answer",
	"moderate: multi-step but routine work with a clear approach",
	"hard: design, debugging an unknown cause, concurrency, security, or correctness-critical reasoning",
];

const CLIP_MARKER = " [...] ";

function clip(text: string, limit: number): string {
	const normalized = text.replace(/\s+/g, " ").trim();
	if (normalized.length <= limit) return normalized;
	const kept = limit - CLIP_MARKER.length;
	if (kept < 2) return normalized.slice(0, Math.max(0, limit));
	const head = Math.ceil(kept * 0.6);
	return `${normalized.slice(0, head)}${CLIP_MARKER}${normalized.slice(normalized.length - (kept - head))}`;
}

function textOf(content: unknown): string {
	if (typeof content === "string") return content;
	if (!Array.isArray(content)) return "";
	const parts: string[] = [];
	for (const block of content as { type?: string; text?: unknown; name?: unknown }[]) {
		if (block.type === "text" && typeof block.text === "string") parts.push(block.text);
		else if (block.type === "toolCall" && typeof block.name === "string") parts.push(`[calls ${block.name}]`);
		else if (block.type === "image") parts.push("[image]");
	}
	return parts.join(" ");
}

function windowEntry(message: AgentMessage): AutoThinkingWindowEntry | undefined {
	if (!("role" in message)) return undefined;
	if (message.role === "user") return { role: "user", text: textOf(message.content) };
	if (message.role === "assistant") return { role: "assistant", text: textOf(message.content) };
	if (message.role === "toolResult") {
		const prefix = `${message.toolName}${message.isError ? " (error)" : ""}: `;
		return { role: "tool", text: prefix + textOf(message.content) };
	}
	return undefined;
}

/**
 * Deterministic context for the difficulty question: the request in full (clipped head and tail)
 * plus the newest transcript entries that fit the per-entry and total character budgets.
 */
export function buildAutoThinkingWindow(
	messages: readonly AgentMessage[],
	request: string,
	limits: AutoThinkingWindowLimits = AUTO_THINKING_WINDOW_LIMITS,
): AutoThinkingWindow {
	const recent: AutoThinkingWindowEntry[] = [];
	let budget = limits.totalChars;
	for (let index = messages.length - 1; index >= 0 && recent.length < limits.maxEntries; index--) {
		const entry = windowEntry(messages[index]);
		if (!entry) continue;
		const text = clip(entry.text, Math.min(limits.entryChars, budget));
		if (!text) continue;
		budget -= text.length;
		recent.unshift({ role: entry.role, text });
		if (budget <= 0) break;
	}
	return { request: clip(request, limits.requestChars), recent };
}

/** Levels auto may choose: every supported level except off. Auto needs at least two. */
export function autoThinkingCandidates(available: readonly ThinkingLevel[]): ThinkingLevel[] {
	const candidates = available.filter((level) => level !== "off");
	return candidates.length >= 2 ? candidates : [];
}

export function chooseAutoThinkingLevel(
	available: readonly ThinkingLevel[],
	probabilities: AutoThinkingProbabilities | undefined,
): ThinkingLevel | undefined {
	const candidates = autoThinkingCandidates(available);
	const top = candidates.at(-1);
	if (!top || !probabilities) return top;
	const lower = candidates.slice(0, -1);
	const trivialLevel = lower.includes("low") ? "low" : lower[0];
	const moderateLevel = lower.includes("high") ? "high" : lower[Math.floor((lower.length * 2) / 3)];
	const [trivial, moderate] = probabilities;
	if (trivial >= AUTO_THINKING_TRIVIAL_THRESHOLD) return trivialLevel;
	if (trivial + moderate >= AUTO_THINKING_MODERATE_THRESHOLD) return moderateLevel;
	return top;
}

function parseProbabilities(payload: unknown): AutoThinkingProbabilities | undefined {
	const answer = (payload as { answers?: { difficulty?: { probabilities?: Record<string, unknown> } } })?.answers
		?.difficulty?.probabilities;
	if (!answer) return undefined;
	const values = ["0", "1", "2"].map((key) => answer[key]);
	if (!values.every((value): value is number => typeof value === "number" && Number.isFinite(value))) {
		return undefined;
	}
	return [values[0], values[1], values[2]];
}

export interface AutoThinkingRequest {
	window: AutoThinkingWindow;
	apiKey: string;
	fetchFn?: typeof fetch;
	timeoutMs?: number;
	signal?: AbortSignal;
}

/** Asks Jev to rate the request's difficulty. Returns undefined on any failure so callers fall back. */
export async function fetchAutoThinkingProbabilities(
	request: AutoThinkingRequest,
): Promise<AutoThinkingProbabilities | undefined> {
	const timeout = AbortSignal.timeout(request.timeoutMs ?? AUTO_THINKING_TIMEOUT_MS);
	const signal = request.signal ? AbortSignal.any([request.signal, timeout]) : timeout;
	try {
		const response = await (request.fetchFn ?? fetch)(JEV_URL, {
			method: "POST",
			headers: { Authorization: `Bearer ${request.apiKey}`, "Content-Type": "application/json" },
			body: JSON.stringify({
				model: JEV_MODEL,
				state: request.window,
				questions: {
					difficulty: {
						type: "score",
						instructions:
							"How much deliberate reasoning does a coding agent need to complete `request` correctly, given the `recent` conversation?",
						criteria: DIFFICULTY_RUBRIC,
					},
				},
			}),
			signal,
		});
		if (!response.ok) return undefined;
		return parseProbabilities(await response.json());
	} catch {
		return undefined;
	}
}
