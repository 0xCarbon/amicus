/**
 * Namespaced `_meta` payloads for amicus capabilities that ACP has no
 * native concept for (Python cell semantics, RLM subagents, autonomous gates,
 * goals, heartbeats, continual harness state).
 *
 * ACP reserves `_meta` on capability objects, notifications, tool calls, and
 * content blocks precisely so agents can carry non-standard data. Vanilla ACP
 * clients ignore these keys; a amicus-aware client (or the verifiers
 * harness) reads them. Never add non-standard fields to an ACP object root.
 */

/** Reverse-domain namespace for every amicus `_meta` payload. */
export const AMICUS_META_NAMESPACE = "ai.primeintellect.amicus";

export interface AmicusSubagentMeta {
	id: string;
	sessionName?: string;
	status: string;
	model?: string;
	depth?: number;
	tokenCount?: number;
	error?: string;
}

export interface AmicusAutonomousMeta {
	enabled: boolean;
	continuationsUsed: number;
	turnsUsed: number;
	tokensUsed: number;
	gateAttempt?: number;
	gateFailure?: string;
}

export interface AmicusIpythonAttachmentMeta {
	mimeType?: string;
	path?: string;
	bytes?: number;
}

export interface AmicusIpythonMeta {
	/** Media the cell loaded into context, as reported by the ipython tool. */
	attachments?: AmicusIpythonAttachmentMeta[];
	/** Number of diffs the cell displayed. */
	diffCount?: number;
}

export interface AmicusGoalMeta {
	status: string;
	objective?: string;
	tokenBudget?: number;
	tokensUsed?: number;
}

export interface AmicusRefinementMeta {
	status: "complete" | "failed";
	summary?: string;
	changes?: string[];
	error?: string;
}

export interface AmicusQuiescenceMeta {
	/** Subagents that have not reached a terminal state at the observation point. */
	outstandingSubagents: number;
	/** Autonomous continuation slots still available at the observation point. */
	remainingAutonomousContinuations: number;
}

export interface AmicusAgentMessageMeta {
	toolCallId: string;
	target?: string;
	deliveryStatus?: string;
}

export interface AmicusCwdMeta {
	/** The cwd the client asked for. */
	requested: string;
	/** The cwd amicus is actually running in, fixed at startup. */
	actual: string;
}

/**
 * Producer-side ordering and causality for ACP updates.
 *
 * `promptTurnId` is allocated when ACP accepts a prompt, never inferred from
 * whichever prompt happens to be running when an update is delivered. `0`
 * means a session-scoped event with no prompt origin (for example a heartbeat
 * change before the first prompt). `eventSequence` is connection-wide and
 * strictly increases for every update Amicus publishes.
 */
export type AmicusEventPhase = "event" | "responseBoundary" | "terminalQuiescence";

/** The outcome carried by a correlated response boundary and terminal envelope. */
export type AmicusResponseOutcome = "result" | "error";

export interface AmicusSessionMeta {
	/** Monotonically increasing ACP prompt turn which caused this update. */
	promptTurnId?: number;
	/** Strictly increasing producer sequence, across all ACP updates. */
	eventSequence?: number;
	/** Whether this is ordinary work, the prompt response boundary, or final quiescence. */
	phase?: AmicusEventPhase;
	/**
	 * The boundary/terminal outcome. This deliberately has only `result` and
	 * `error`: ACP's transport stop reasons (including `end_turn`) are never a
	 * causal completion signal.
	 */
	outcome?: AmicusResponseOutcome;
	/** Whether an accepted response boundary promises a later terminal-quiescence envelope. */
	terminalQuiescenceExpected?: boolean;
	/** Present when a client-requested cwd differs from the agent's real cwd. */
	cwd?: AmicusCwdMeta;
	/** Set when the session's heartbeat or cron schedule changed. */
	heartbeatsChanged?: boolean;
	goal?: AmicusGoalMeta;
	refinement?: AmicusRefinementMeta;
	agentMessage?: AmicusAgentMessageMeta;
	sessionId?: string;
	rlmDepth?: number;
	rlmMaxDepth?: number;
	compaction?: { tokensBefore?: number; summary?: string };
	subagents?: AmicusSubagentMeta[];
	autonomous?: AmicusAutonomousMeta;
	/** Observed subagent and autonomous-continuation counts at completion. */
	quiescence?: AmicusQuiescenceMeta;
	ipython?: AmicusIpythonMeta;
}

/** Wrap a amicus payload in its reverse-domain `_meta` envelope. */
export function amicusMeta(payload: AmicusSessionMeta): Record<string, unknown> {
	return { [AMICUS_META_NAMESPACE]: payload };
}
