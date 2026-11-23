import type { AgentMessage, ThinkingLevel } from "@earendil-works/pi-agent-core";
import { describe, expect, it } from "vitest";
import {
	type AutoThinkingProbabilities,
	buildAutoThinkingWindow,
	chooseAutoThinkingLevel,
	fetchAutoThinkingProbabilities,
} from "../src/core/auto-thinking.js";

const GLM: ThinkingLevel[] = ["low", "high", "max"];
const OPENAI: ThinkingLevel[] = ["off", "minimal", "low", "medium", "high", "xhigh"];

function text(role: "user" | "assistant", value: string): AgentMessage {
	return { role, content: [{ type: "text", text: value }], timestamp: 0 } as AgentMessage;
}

describe("auto thinking", () => {
	it.each([
		{ levels: GLM, p: [0.83, 0.17, 0], expected: "low" },
		{ levels: GLM, p: [0.57, 0.43, 0], expected: "high" },
		{ levels: GLM, p: [0.02, 0.24, 0.74], expected: "max" },
		{ levels: GLM, p: undefined, expected: "max" },
		{ levels: OPENAI, p: [0.9, 0.1, 0], expected: "low" },
		{ levels: OPENAI, p: [0.1, 0.85, 0.05], expected: "high" },
		{ levels: OPENAI, p: [0, 0.2, 0.8], expected: "xhigh" },
		{ levels: ["off", "low"], p: [1, 0, 0], expected: undefined },
	] as { levels: ThinkingLevel[]; p?: AutoThinkingProbabilities; expected?: ThinkingLevel }[])(
		"maps $p on $levels to $expected",
		({ levels, p, expected }) => {
			expect(chooseAutoThinkingLevel(levels, p)).toBe(expected);
		},
	);

	it("keeps the newest entries within the budgets, oldest first", () => {
		const messages = [
			text("user", "oldest"),
			text("assistant", "x".repeat(5000)),
			{
				role: "toolResult",
				toolCallId: "t",
				toolName: "bash",
				isError: true,
				content: [{ type: "text", text: "boom" }],
				timestamp: 0,
			} as AgentMessage,
		];
		const window = buildAutoThinkingWindow(messages, "fix it", {
			requestChars: 100,
			entryChars: 40,
			totalChars: 50,
			maxEntries: 8,
		});
		expect(window.request).toBe("fix it");
		expect(window.recent.map((entry) => entry.role)).toEqual(["assistant", "tool"]);
		expect(window.recent[1].text).toBe("bash (error): boom");
		expect(window.recent[0].text).toHaveLength(32);
		expect(window.recent[0].text).toContain(" [...] ");
		expect(buildAutoThinkingWindow(messages, "fix it")).toEqual(buildAutoThinkingWindow(messages, "fix it"));
	});

	it.each([
		{
			name: "valid score",
			response: () => Response.json({ answers: { difficulty: { probabilities: { 0: 0.1, 1: 0.2, 2: 0.7 } } } }),
			expected: [0.1, 0.2, 0.7],
		},
		{ name: "HTTP error", response: () => new Response("rate limited", { status: 429 }), expected: undefined },
		{ name: "malformed body", response: () => Response.json({ answers: {} }), expected: undefined },
		{ name: "network failure", response: () => Promise.reject(new Error("offline")), expected: undefined },
	])("returns $expected for a $name", async ({ response, expected }) => {
		let body: unknown;
		const fetchFn = (async (_url: string, init: RequestInit) => {
			body = JSON.parse(String(init.body));
			return response();
		}) as unknown as typeof fetch;
		const window = { request: "why does it deadlock?", recent: [] };
		await expect(fetchAutoThinkingProbabilities({ window, apiKey: "k", fetchFn })).resolves.toEqual(expected);
		expect(body).toMatchObject({ state: window, questions: { difficulty: { type: "score" } } });
	});

	it("gives up when the service does not answer before the timeout", async () => {
		const fetchFn = ((_url: string, init: RequestInit) =>
			new Promise((_resolve, reject) => {
				init.signal?.addEventListener("abort", () => reject(init.signal?.reason));
			})) as unknown as typeof fetch;
		const window = { request: "x", recent: [] };
		await expect(fetchAutoThinkingProbabilities({ window, apiKey: "k", fetchFn, timeoutMs: 1 })).resolves.toBe(
			undefined,
		);
	});
});
