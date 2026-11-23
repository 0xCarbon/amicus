import { fauxAssistantMessage, type ModelThinkingLevel, type SimpleStreamOptions } from "@earendil-works/pi-ai";
import { afterEach, describe, expect, it, vi } from "vitest";
import { AUTO_THINKING_API_KEY_ENV } from "../../src/core/auto-thinking.js";
import { createHarness } from "./harness.js";

const GLM_LIKE = { off: null, minimal: null, medium: null, xhigh: null, max: "max" } as const;
const savedKey = process.env[AUTO_THINKING_API_KEY_ENV];

afterEach(() => {
	vi.unstubAllGlobals();
	if (savedKey === undefined) delete process.env[AUTO_THINKING_API_KEY_ENV];
	else process.env[AUTO_THINKING_API_KEY_ENV] = savedKey;
});

function jevAnswers(answers: ([number, number, number] | "fail")[]): { state: unknown }[] {
	const bodies: { state: unknown }[] = [];
	vi.stubGlobal(
		"fetch",
		vi.fn(async (_url: string, init: RequestInit) => {
			bodies.push(JSON.parse(String(init.body)));
			const next = answers.shift();
			if (!next || next === "fail") return new Response("overloaded", { status: 529 });
			return Response.json({ answers: { difficulty: { probabilities: { 0: next[0], 1: next[1], 2: next[2] } } } });
		}),
	);
	return bodies;
}

describe("auto thinking", () => {
	it("picks each prompt's level from the difficulty score until a level is chosen explicitly", async () => {
		process.env[AUTO_THINKING_API_KEY_ENV] = "test-key";
		const bodies = jevAnswers([[0.9, 0.1, 0], [0.1, 0.85, 0.05], "fail"]);
		const harness = await createHarness({ models: [{ id: "glm-like", reasoning: true }] });
		try {
			harness.session.agent.state.model.thinkingLevelMap = { ...GLM_LIKE };
			const observed: (ModelThinkingLevel | undefined)[] = [];
			const reply = (_context: unknown, options: unknown) => {
				observed.push((options as SimpleStreamOptions)?.reasoning);
				return fauxAssistantMessage("done");
			};
			harness.setResponses([reply, reply, reply, reply]);

			expect(harness.session.setAutoThinking(true)).toBe(true);
			for (const text of ["rename foo", "add a flag", "the daemon deadlocks"]) await harness.session.prompt(text);
			harness.session.selectThinkingLevel("low");
			await harness.session.prompt("thanks");

			expect(observed).toEqual(["low", "high", "max", "low"]);
			expect(bodies).toHaveLength(3);
			expect(bodies[1].state).toMatchObject({
				request: "add a flag",
				recent: [
					{ role: "user", text: "rename foo" },
					{ role: "assistant", text: "done" },
				],
			});
			expect(harness.session.autoThinking).toBe(false);
			const persisted = harness.sessionManager
				.getEntries()
				.filter((entry) => entry.type === "custom" && entry.customType === "auto_thinking_state");
			expect(persisted.map((entry) => (entry as { data?: unknown }).data)).toEqual([
				{ enabled: true },
				{ enabled: false },
			]);
		} finally {
			harness.cleanup();
		}
	});

	it("refuses auto without a TypeSafe key", async () => {
		delete process.env[AUTO_THINKING_API_KEY_ENV];
		const harness = await createHarness({ models: [{ id: "glm-like", reasoning: true }] });
		try {
			expect(harness.session.isAutoThinkingAvailable()).toBe(false);
			expect(harness.session.setAutoThinking(true)).toBe(false);
		} finally {
			harness.cleanup();
		}
	});
});
