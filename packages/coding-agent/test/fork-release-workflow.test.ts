import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { describe, expect, it } from "vitest";
import { parse } from "yaml";

interface WorkflowStep {
	env?: Record<string, string>;
	id?: string;
	name?: string;
	run?: string;
	with?: Record<string, unknown>;
}

interface ForkReleaseWorkflow {
	concurrency: {
		"cancel-in-progress": boolean;
		group: string;
		queue: string;
	};
	jobs: {
		release: {
			if: string;
			steps: WorkflowStep[];
		};
	};
	permissions: Record<string, string>;
}

function loadWorkflow(): ForkReleaseWorkflow {
	const workflowPath = resolve(__dirname, "../../../.github/workflows/fork-release.yml");
	return parse(readFileSync(workflowPath, "utf8")) as ForkReleaseWorkflow;
}

describe("Amicus release workflow", () => {
	it("serializes every fork-main release without dropping queued runs", () => {
		const workflow = loadWorkflow();

		expect(workflow.concurrency).toEqual({
			"cancel-in-progress": false,
			group: "release-amicus",
			queue: "max",
		});
		expect(workflow.jobs.release.if).toBe("github.repository == '0xCarbon/amicus'");
		expect(workflow.permissions).toEqual({ contents: "write" });
	});

	it("checks out history so the release check has a test-policy baseline", () => {
		const checkout = loadWorkflow().jobs.release.steps.find((step) => step.name === "Checkout");
		expect(checkout?.with?.["fetch-depth"]).toBe(0);
	});

	it("selects latest precedence, publishes all artifacts, then removes any release that is not immutable", () => {
		const steps = loadWorkflow().jobs.release.steps;
		const githubTokenExpression = ["$", "{{ secrets.GITHUB_TOKEN }}"].join("");
		const latestOutputExpression = ["$", "{{ steps.latest.outputs.flag }}"].join("");
		const latestIndex = steps.findIndex((step) => step.name === "Select latest release");
		const publishIndex = steps.findIndex((step) => step.name === "Publish release");
		const immutableIndex = steps.findIndex((step) => step.name === "Require an immutable release");
		const latestStep = steps[latestIndex];
		const publishStep = steps[publishIndex];
		const immutableStep = steps[immutableIndex];

		expect(latestIndex).toBeGreaterThan(-1);
		expect(publishIndex).toBeGreaterThan(latestIndex);
		expect(immutableIndex).toBeGreaterThan(publishIndex);
		expect(steps.every((step) => !Object.values(step.env ?? {}).some((value) => value.includes("ADMIN_TOKEN")))).toBe(
			true,
		);
		expect(immutableStep?.env?.GH_TOKEN).toBe(githubTokenExpression);
		expect(immutableStep?.run).toContain("--jq .immutable");
		expect(immutableStep?.run).toContain('if [ "$immutable" != "true" ]');
		expect(immutableStep?.run).toContain("gh release delete");
		expect(immutableStep?.run).toContain("exit 1");
		expect(latestStep?.id).toBe("latest");
		expect(latestStep?.run).toContain("scripts/release-latest-decision.mjs");
		expect(publishStep?.run).toContain(latestOutputExpression);
		expect(publishStep?.run).toContain("packages/coding-agent/release/fork/artifacts/*");
		expect(publishStep?.run?.split("\n").some((line) => /^--latest(?:\s+\\)?$/.test(line.trim()))).toBe(false);
	});
});
