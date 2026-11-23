# Contributing to Amicus

Thanks for your interest in contributing to Amicus! We welcome bug reports, feature requests, questions, and other feedback in [GitHub Issues](https://github.com/0xCarbon/amicus/issues).

With the influx of agent-generated contributions, we do not review unsolicited pull requests. While we are open to contributions by agents, you are responsible for your code and must understand how it interacts with the entire project.

## Issues

Search existing Issues before opening a new one. Include enough detail for someone else to understand and reproduce the problem, but do not share API keys, tokens, private prompts, or other sensitive information. Issues labeled `backlog` are accepted work; an existing Issue does not automatically mean that an external pull request is wanted, so wait for a maintainer to invite implementation before starting substantial work.

For security vulnerabilities, follow [SECURITY.md](SECURITY.md) instead of posting publicly.

## Pull Requests and Trusted Contributors

Amicus runs on user machines and can execute code with the user's permissions. We therefore limit pull requests to maintainers and trusted contributors who have been explicitly vouched for. Maintainers may vouch for someone after they have consistently demonstrated a useful understanding of the project through issue investigation, testing, documentation, or other collaboration. There is no separate application process and no guarantee that participation will result in approval.

Pull requests from unvouched contributors are automatically closed. If you are interested in contributing code, start with an Issue and work with the maintainers on the problem first.

## Preparing an Approved Pull Request

If a maintainer has invited a pull request:

1. Keep the change focused on the accepted Issue.
2. Follow the repository's development rules and existing conventions.
3. Add or update tests for behavioral changes.
4. Run the relevant checks locally and describe the validation in the pull request.
5. Avoid unrelated refactors or dependency changes.

Development setup and commands are documented in the [development guide](packages/coding-agent/docs/development.md).

## Pre-release behavioral evaluation

Maintainers may apply the exact `pre-release` label to a release-candidate pull request.
This approves the current head for a fixed Short SWE comparison with its exact base.
Remove and reapply the label after every new head revision or base advancement. Removing
the label revokes any prior result. Do not add it for ordinary CI. A labeled PR must pass
the current `Behavioral Eval / pre-release approval` and `Behavioral Eval / pre-release`
statuses before merge. Repository rules must require both contexts with strict up-to-date-branch
enforcement; the workflow refuses evaluation success otherwise. See
[`scripts/evals/short_swe/README.md`](scripts/evals/short_swe/README.md).

## Changelog entries

Do not edit `packages/*/CHANGELOG.md` directly. Instead, add one fragment
file per PR per touched package: `packages/<pkg>/.changes/<slug>.md`, where `<slug>` is a kebab-case name
derived from your branch or ticket (e.g. `eng-1234-fix-resize.md`). The file contains exactly the bullet
line(s) that describe the change, e.g. `- Fixed the frobnicator dropping input on resize.`. The release
script aggregates fragments into the release section and deletes them. PRs that change `packages/<pkg>/src`
without a fragment fail CI; apply the `no-changelog` label to opt out.

Maintainers may close a pull request that changes scope, cannot be validated safely, or no longer fits the project roadmap.
