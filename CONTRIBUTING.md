# Contributing to Vorssaint

Vorssaint aims to stay small, native and readable. Contributions are accepted
under GPL-3.0-or-later unless stated otherwise.

## Getting started

You need macOS 14 or newer, Apple Silicon and the Xcode Command Line Tools.
The project builds with `build.sh`, without an Xcode project or external package
dependencies. `Package.swift` supports editor indexing; it does not assemble or
sign the app bundle.

```sh
git clone https://github.com/vorssaint/vorssaint-utils.git
cd vorssaint-utils
./build.sh --dev
./build/VorssaintDeveloper --selftest
./build.sh --test
```

To install and launch the separate Developer app, use `./build.sh --dev --install`.
It has its own preferences and permissions and does not replace the official app.
For daily use or animation performance checks, add `--optimized` to compile the
Developer variant with release optimization while retaining its identity and probes.
A plain `./build.sh` builds the optimized variant used by CI; its health check is
`./build/Vorssaint --selftest`.

### Stable signing

Developer and install builds automatically try to create a stable local signing
identity when none is available. You can also run `./Tools/setup-signing.sh`.
Keep that identity across rebuilds: ad-hoc signatures change with the binary and
can invalidate macOS permission grants. Check the build output for signing
failures. For stale grants, see [troubleshooting](docs/TROUBLESHOOTING.md#resetting-permissions).

Official releases use Developer ID signing and notarization through the protected
release workflow. Local signing does not produce an official release.

## Scope and implementation

Before a substantial feature, search existing issues and PRs and discuss the
direction in an issue. Explain the user need, required permissions, dependencies
and ongoing maintenance. Prefer existing macOS capabilities and repository code
over a new subsystem. Keep each PR focused on one independently useful change.

- App lifecycle lives in `Sources/Vorssaint/App`, shared catalogs and preferences
  in `Core`, behavior in `Services`, views in `UI`, and diagnostics in `Support`.
  Keep reusable decisions outside views where they can be tested.
- Check other callers and the upgrade path when fixing shared behavior.
- New features belong in the feature catalog, with availability and permission
  checks on every entry point. Optional background work should stop when disabled.
- User preferences must participate in settings backup. Machine-specific state
  and private content need an explicit exclusion.
- Update every locale in `AppLanguage.allCases`, including feature-specific
  string catalogs. A new language also needs its locale registration, localized
  permission prompts where applicable, and coverage tests.
- New source files retain the project's SPDX license and copyright headers.

Sensor changes should include a dump from `./build/Vorssaint --sensors` and the
Mac model. Selection logic lives in `TemperatureSensorSelector` and `SystemMonitor`.

## Validation

Documentation-only changes need a diff and link check. For code changes, run the
relevant tests; `./build.sh --list-tests` lists suites and
`./build.sh --test-suite=NAME` selects one. Behavior tests should fail without the
fix and preserve legitimate use, rather than pinning private implementation text.

The test executable compiles a selected set of sources, so passing tests does not
prove the app builds. Build the app and run its selftest for runtime, UI or bundled
resource changes. CI also checks the optimized build, selftest, tests and packaging.
Builds should finish without warnings.

For behavior involving windows, permissions or hardware, describe what you actually
verified and on which Mac and macOS version. Include display, Spaces or language
details when relevant, and state what remains untested. Compilation and static
inspection alone do not demonstrate an interaction on a real Mac.

## Pull requests

Explain the behavior before and after, the scope and validation. Use
`type(scope): lowercase imperative phrase` for the title and reuse an existing
scope where possible. Open unfinished work as a draft and name what is missing.
The [template](.github/PULL_REQUEST_TEMPLATE.md) is a prompt, not a form.

Leave version bumps and `CHANGELOG.md` to the maintainer. Describe the user-visible
effect in the PR so it can become a release note with your credit.

When an issue exists, include one reference per line:

```text
Refs #123
Refs #456
```

Avoid `Closes` or `Fixes`: those close the issue at merge, before users receive
the fix. The fix-status workflow tracks the reference, notifies the reporter when
a stable release carries the fix, and can close the issue after two weeks without
a response. If the PR addresses only part of an issue, say exactly which part.

For agent-assisted work, see [contributing with an agent](docs/AI-CONTRIBUTIONS.md).
Bug reports and feature requests use the [issue forms](https://github.com/vorssaint/vorssaint-utils/issues/new/choose).
Report vulnerabilities through [private security reporting](SECURITY.md).

## Releases (maintainers)

Integrating into `main`, pushing a branch and opening a PR do not publish a release.
Publication requires an explicit release decision, including beta or stable.

Before sending a version tag, validate the final commit on `main`, confirm its
verified signature, and match `Resources/Info.plist` and the release notes to the
chosen version. Use a signed tag such as `vX.Y.Z-beta.N` or `vX.Y.Z`.
Sending the tag starts [the release workflow](.github/workflows/release.yml).

The protected `release-signing` environment holds the signing and notarization
credentials. The workflow builds, signs and notarizes the app and DMG, then
publishes an immutable release. Confirm publication succeeded; a pushed tag alone
is not a published version. Beta releases remain prereleases and do not replace
the latest stable release or its Homebrew cask. Do not move published tags or
replace published artifacts.

## Downloadable CI builds

The CI workflow builds every pushed branch, version tag and pull request. It can
also be started with **Actions → CI → Run workflow** once present on the default
branch. The macOS 26 job builds the release app, runs selftests and unit tests,
packages a DMG, verifies its signature and compares the mounted app with the
fresh build. Only a successful job uploads a downloadable artifact.

Open the successful run in GitHub Actions and download `Vorssaint-dmg-<commit>`.
Extract the archive and send the DMG inside. `BUILD-INFO.txt` identifies the exact
source and run; `SHA256SUMS` verifies the file with `shasum -a 256 -c SHA256SUMS`.
DMGs use the full source commit in their filename to distinguish builds that
share an app version. Artifacts remain available for 30 days.

CI builds target Apple Silicon (arm64), require macOS 14+, and are ad-hoc signed
without Apple notarization. The protected official release workflow is separate
and remains restricted to the upstream repository and its signing credentials.
Fork builds do not require Apple secrets and do not publish official releases.

## AI usage accounting

Antigravity history is read from conversation SQLite generation and step metadata
in App, IDE, CLI and T3 profiles. Request aliases deduplicate repeated metadata,
retries remain separate, and cache reads, cache writes, output and reasoning are
kept distinct. Reasoning is already included in output and is not billed twice.
Display transcripts remain a fallback when conversation databases are unavailable.
Unknown model identities retain token counts without inventing prices.

Codex history includes plain JSONL and compressed `.jsonl.zst` archives. The build
downloads Zstandard 1.5.7 at a pinned commit and statically links its decoder for
macOS 14+, so the installed app needs no external decompression command. Its BSD
license ships in the bundle. Both readers use bounded buffers and support cancellation.

Prices are estimated API-equivalent values, not subscription charges. Gemini rates
were added to the shipped price list on 2026-11-15 using Google's published pricing.
By explicit request, experimental `gemini-3.8-flash-n` uses the same estimate as
`gemini-3.8-flash-high`: $0.75 input, $0.075 cache read, and $3.75 output per million
tokens, with cache creation at input price. This is an estimate override, not a
published separate price for `-n`. Recheck the promotional Gemini rates at the
dates recorded in `Resources/agent-prices.json`.

Shortcuts live activities observe only Apple's workflow start/finish unified-log
metadata. The observer is opt-out in Dynamic Island settings, stops with the
feature, bounds its subprocess lifetime and history reads, and checks runner
identity and process birth time before presenting a session. Shortcut names,
actions, inputs and results are not retained. A retained runner alone never
creates an activity. This integration depends on macOS's WorkflowExecution log
format; macOS owns its native running indicator and provides no supported
suppression API. To smoke-test it, run a Wait-only shortcut and verify that it
preempts music/agents centrally, then restores the previous activity on finish.

Vorssaint is a persistent menu-bar utility. App Intents idle cleanup from Siri
or LaunchServices must not quit it. The termination policy preserves explicit
local quits, Activity Monitor quits and session-ending quit reasons. Its tests
also cover the command bar's asynchronous input-source restoration on quit.
