import { chmodSync, existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "fs";
import { homedir, tmpdir } from "os";
import { delimiter, join } from "path";
import { afterEach, describe, expect, test } from "vitest";
import {
	adoptLegacyAgentDir,
	detectInstallMethod,
	ENV_LEGACY_SESSION_DIR,
	ENV_SESSION_DIR,
	getDaemonLogPath,
	getSelfUpdateCommand,
	getSelfUpdateUnavailableInstruction,
	getSessionsDir,
} from "../src/config.js";

const execPathDescriptor = Object.getOwnPropertyDescriptor(process, "execPath");
const originalEnv = {
	PATH: process.env.PATH,
	PI_PACKAGE_DIR: process.env.PI_PACKAGE_DIR,
	[ENV_SESSION_DIR]: process.env[ENV_SESSION_DIR],
	[ENV_LEGACY_SESSION_DIR]: process.env[ENV_LEGACY_SESSION_DIR],
};
let tempDir: string | undefined;

function setExecPath(value: string): void {
	Object.defineProperty(process, "execPath", { value, configurable: true });
}

afterEach(() => {
	if (execPathDescriptor) Object.defineProperty(process, "execPath", execPathDescriptor);
	for (const [key, value] of Object.entries(originalEnv)) {
		if (value === undefined) delete process.env[key];
		else process.env[key] = value;
	}
	if (tempDir) {
		chmodSync(tempDir, 0o700);
		rmSync(tempDir, { recursive: true, force: true });
		tempDir = undefined;
	}
});

// Fake package-manager CLI that answers one argv probe (`pnpm root -g`, `yarn global dir`, `bun pm bin -g`).
function writeFakeCli(binDir: string, name: string, probe: string[], output: string): void {
	mkdirSync(binDir, { recursive: true });
	const isWindows = process.platform === "win32";
	const file = join(binDir, isWindows ? `${name}.cmd` : name);
	const script = isWindows
		? `@echo off\r\n${probe.map((arg, index) => `if "%${index + 1}"=="${arg}" `).join("")}echo ${output}\r\n`
		: `#!/bin/sh\nif ${probe
				.map((arg, index) => `[ "$${index + 1}" = "${arg}" ]`)
				.join(" && ")}; then\n\tprintf '%s\\n' '${output.replaceAll("'", "'\\''")}'\n\texit 0\nfi\nexit 1\n`;
	writeFileSync(file, script);
	chmodSync(file, 0o755);
	process.env.PATH = `${binDir}${delimiter}${originalEnv.PATH ?? ""}`;
}

function usePackageDir(packageDir: string, execPath = join(packageDir, "dist", "cli.js")): void {
	mkdirSync(packageDir, { recursive: true });
	process.env.PI_PACKAGE_DIR = packageDir;
	setExecPath(execPath);
}

function createNpmPrefixInstall(template = "pi-prefix-"): { prefix: string; packageDir: string } {
	const prefix = mkdtempSync(join(tmpdir(), template));
	const packageDir = join(prefix, "lib", "node_modules", "@amicus", "coding-agent");
	tempDir = prefix;
	usePackageDir(packageDir);
	return { prefix, packageDir };
}

function createHomebrewInstall(): void {
	const prefix = mkdtempSync(join(tmpdir(), "pi-homebrew-"));
	tempDir = prefix;
	usePackageDir(join(prefix, "Cellar", "amicus", "0.7.0", "libexec", "lib", "node_modules", "amicus"));
}

function createPnpmGlobalInstall(): void {
	const temp = mkdtempSync(join(tmpdir(), "pi-pnpm-"));
	tempDir = temp;
	const root = join(temp, "pnpm", "global", "5", "node_modules");
	const packageDir = join(root, "@mariozechner", "pi-coding-agent");
	writeFakeCli(join(temp, "bin"), "pnpm", ["root", "-g"], root);
	usePackageDir(
		packageDir,
		join(
			root,
			".pnpm",
			"@mariozechner+pi-coding-agent@0.0.0",
			"node_modules",
			"@mariozechner",
			"pi-coding-agent",
			"dist",
			"cli.js",
		),
	);
}

function createYarnGlobalInstall(): void {
	const temp = mkdtempSync(join(tmpdir(), "pi-yarn-"));
	tempDir = temp;
	const globalDir = join(temp, "yarn", "global");
	writeFakeCli(join(temp, "bin"), "yarn", ["global", "dir"], globalDir);
	usePackageDir(
		join(globalDir, "node_modules", "@mariozechner", "pi-coding-agent"),
		join(globalDir, ".yarn", "@mariozechner", "pi-coding-agent", "dist", "cli.js"),
	);
}

function createBunGlobalInstall(): void {
	const temp = mkdtempSync(join(tmpdir(), "pi-bun-"));
	tempDir = temp;
	const prefix = join(temp, ".bun");
	const bunBin = join(prefix, "bin");
	writeFakeCli(bunBin, "bun", ["pm", "bin", "-g"], bunBin);
	usePackageDir(join(prefix, "install", "global", "node_modules", "@amicus", "coding-agent"));
}

describe("detectInstallMethod", () => {
	// Misdetecting the install method breaks self-update: it runs the wrong package manager.
	test.each<[string, () => void, string]>([
		[
			"Windows .pnpm install paths",
			() =>
				setExecPath(
					"C:\\Users\\Admin\\Documents\\pnpm-repository\\global\\5\\.pnpm\\@amicus+coding-agent@0.67.68\\node_modules\\@amicus\\coding-agent\\dist\\cli.js",
				),
			"pnpm",
		],
		[
			"Windows npm package dirs",
			() => {
				const packageDir = "C:\\Users\\Admin\\npm prefix\\node_modules\\@amicus\\coding-agent";
				process.env.PI_PACKAGE_DIR = packageDir;
				setExecPath(`${packageDir}\\dist\\cli.js`);
			},
			"npm",
		],
		["npm custom prefixes", () => createNpmPrefixInstall(), "npm"],
		["pnpm global installs", () => createPnpmGlobalInstall(), "pnpm"],
		["yarn global installs", () => createYarnGlobalInstall(), "yarn"],
		["bun global installs", () => createBunGlobalInstall(), "bun"],
		["Homebrew installs", () => createHomebrewInstall(), "homebrew"],
		["unknown wrapper installs", () => setExecPath("/usr/local/bin/node"), "unknown"],
	])("detects %s", (_label, setup, expected) => {
		setup();
		expect(detectInstallMethod()).toBe(expected);
	});

	test.each<[string, () => void]>([
		["Homebrew", () => createHomebrewInstall()],
		["unknown wrappers", () => setExecPath("/usr/local/bin/node")],
	])("refuses to self-update %s installs", (_label, setup) => {
		setup();
		expect(getSelfUpdateCommand("amicus")).toBeUndefined();
	});

	test("does not self-update when the npm install path is not writable", () => {
		const { packageDir } = createNpmPrefixInstall();
		chmodSync(packageDir, 0o500);

		expect(getSelfUpdateCommand("@amicus/coding-agent")).toBeUndefined();
		expect(getSelfUpdateUnavailableInstruction("@amicus/coding-agent")).toContain("the install path is not writable");
	});

	test.each<[string, (prefix: string) => string[] | undefined]>([
		["defaults to the detected prefix", () => undefined],
		["respects a configured npmCommand", (prefix) => ["npm", "--prefix", prefix]],
		["treats an empty npmCommand as unset", () => []],
	])("npm self-update %s", (_label, npmCommand) => {
		const { prefix } = createNpmPrefixInstall();

		expect(getSelfUpdateCommand("@amicus/coding-agent", npmCommand(prefix))).toEqual({
			command: "npm",
			args: ["--prefix", prefix, "install", "-g", "@amicus/coding-agent"],
			display: `npm --prefix ${prefix} install -g @amicus/coding-agent`,
		});
	});

	test("quotes npm self-update display paths", () => {
		const { prefix } = createNpmPrefixInstall("pi prefix ");

		expect(getSelfUpdateCommand("@amicus/coding-agent")?.display).toBe(
			`npm --prefix "${prefix}" install -g @amicus/coding-agent`,
		);
	});

	const tarballUrl = "https://downloads.example.test/amicus/amicus-0.73.0.tgz";

	test("installs a tarball spec without uninstalling the same logical package", () => {
		const { prefix } = createNpmPrefixInstall();

		expect(getSelfUpdateCommand("@amicus/coding-agent", undefined, tarballUrl)).toEqual({
			command: "npm",
			args: ["--prefix", prefix, "install", "-g", tarballUrl],
			display: `npm --prefix ${prefix} install -g ${tarballUrl}`,
		});
	});

	test("installs a renamed tarball package before uninstalling the old one", () => {
		const { prefix } = createNpmPrefixInstall();

		expect(getSelfUpdateCommand("@amicus/coding-agent", undefined, tarballUrl, "amicus")).toEqual({
			command: "npm",
			args: ["--prefix", prefix, "install", "-g", tarballUrl],
			display: `npm --prefix ${prefix} install -g ${tarballUrl} && npm --prefix ${prefix} uninstall -g @amicus/coding-agent`,
			steps: [
				{
					command: "npm",
					args: ["--prefix", prefix, "install", "-g", tarballUrl],
					display: `npm --prefix ${prefix} install -g ${tarballUrl}`,
				},
				{
					command: "npm",
					args: ["--prefix", prefix, "uninstall", "-g", "@amicus/coding-agent"],
					display: `npm --prefix ${prefix} uninstall -g @amicus/coding-agent`,
				},
			],
		});
	});

	// A rename must remove the old global package first, with each manager's own remove verb.
	test.each<[string, () => string[], string, string[], string[]]>([
		["npm", () => ["--prefix", createNpmPrefixInstall().prefix], "npm", ["uninstall", "-g"], ["install", "-g"]],
		[
			"pnpm",
			() => {
				createPnpmGlobalInstall();
				return [];
			},
			"pnpm",
			["remove", "-g"],
			["install", "-g"],
		],
		[
			"yarn",
			() => {
				createYarnGlobalInstall();
				return [];
			},
			"yarn",
			["global", "remove"],
			["global", "add"],
		],
		[
			"bun",
			() => {
				createBunGlobalInstall();
				return [];
			},
			"bun",
			["uninstall", "-g"],
			["install", "-g"],
		],
	])("renames a %s global install by removing the old package first", (_label, setup, command, remove, install) => {
		const argPrefix = setup();

		const result = getSelfUpdateCommand("@mariozechner/pi-coding-agent", undefined, "@new-scope/pi");

		expect(result?.command).toBe(command);
		expect(result?.steps?.map((step) => ({ command: step.command, args: step.args }))).toEqual([
			{ command, args: [...argPrefix, ...remove, "@mariozechner/pi-coding-agent"] },
			{ command, args: [...argPrefix, ...install, "@new-scope/pi"] },
		]);
	});
});

describe("session paths", () => {
	test("prefers the app-prefixed session dir env var over the legacy one and expands tilde", () => {
		expect(ENV_SESSION_DIR).toBe("AMICUS_SESSION_DIR");

		const sessionRoot = join(tmpdir(), `pi-session-root-${Date.now()}`);
		process.env[ENV_SESSION_DIR] = sessionRoot;
		process.env[ENV_LEGACY_SESSION_DIR] = join(tmpdir(), "legacy-root");
		expect(getSessionsDir("/agent")).toBe(sessionRoot);

		delete process.env[ENV_SESSION_DIR];
		expect(getSessionsDir("/agent")).toBe(join(tmpdir(), "legacy-root"));

		process.env[ENV_SESSION_DIR] = "~/amicus-sessions";
		expect(getSessionsDir("/agent")).toBe(join(homedir(), "amicus-sessions"));
	});
});

describe("getDaemonLogPath", () => {
	test("normalizes POSIX socket path spellings to one log file", () => {
		const platformDescriptor = Object.getOwnPropertyDescriptor(process, "platform");
		Object.defineProperty(process, "platform", { value: "linux", configurable: true });
		try {
			expect(getDaemonLogPath("/a//b.sock")).toBe(getDaemonLogPath("/a/b.sock"));
		} finally {
			if (platformDescriptor) Object.defineProperty(process, "platform", platformDescriptor);
		}
	});
});

describe("legacy agent directory", () => {
	test.each([
		{ name: "moves the pre-rename directory into place", targetExists: false, expected: "legacy" },
		{ name: "never overwrites an existing directory", targetExists: true, expected: "current" },
	])("$name", ({ targetExists, expected }) => {
		const home = mkdtempSync(join(tmpdir(), "amicus-legacy-home-"));
		try {
			const legacy = join(home, ".prime", "agent");
			const target = join(home, ".amicus");
			mkdirSync(legacy, { recursive: true });
			writeFileSync(join(legacy, "auth.json"), "legacy");
			if (targetExists) {
				mkdirSync(target);
				writeFileSync(join(target, "auth.json"), "current");
			}
			adoptLegacyAgentDir(target, home);
			expect(readFileSync(join(target, "auth.json"), "utf8")).toBe(expected);
			expect(existsSync(legacy)).toBe(targetExists);
		} finally {
			rmSync(home, { recursive: true, force: true });
		}
	});
});
