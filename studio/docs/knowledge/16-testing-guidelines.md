# 16 — Testing Guidelines

How this repository is tested today and the bar for every new feature.

## Current state
~314 XCTest functions across 14 suites; every module ships with its suite;
CI runs Linux (`swift:6.0` container) + macOS on every push touching
`studio/**`, plus release-build smoke tests of the CLI (including the
end-to-end Thai `edit` and generated-WAV audio paths) and a live MCP
handshake.

## Test taxonomy
- **Unit** — pure logic: time math, parsers, detectors, planners, builders.
  The bulk of the suite; no I/O, no network.
- **Integration** — module seams: MCP `tools/call` end-to-end
  (auto_edit → validate_fcpxml round-trip), storage save/snapshot/restore,
  FCPXML write→read round-trips.
- **Smoke (CI)** — the built executables actually run (`ghostly intent`,
  `presets`, `export`, `demo-thai`, the end-to-end `edit` command from a Thai
  SRT fixture — output re-linted with `ghostly validate` —,
  `demo-audio`/`analyze-audio` on generated WAV bytes, and MCP
  initialize/tools list over stdio).
- **Performance** — best-of-N wall-time baselines (Phase 17): RationalTime
  accumulation (100k mixed-timescale additions), NTSC frame snapping,
  silence/beat detection over 60 s fixtures, WAV decode, and FCPXML
  write/validate on a 1,000-clip timeline, each against a deliberately
  generous budget. XCTest `measure {}` is avoided: corelibs XCTest fails
  runs whose deviation exceeds 10%, which noisy CI runners routinely do.
  Blocks assert correctness too, so wrong output fails as well.
- **Stress** — 10k-clip timelines, hour-long detection arrays (planned).
- **UI / accessibility** — XCUITest on the macOS app; every control needs a
  label (planned with app buildout, M2).
- **Regression** — every CI-caught bug gets a pinned test. Examples already
  in-tree: source-time caption conversion, autosave millisecond precision,
  favorite tie-break scoring, titles-key backward decode.

## Rules for new code
1. No feature merges without tests exercising success *and* failure paths.
2. Tests must pass on Linux and macOS (platform-gated code compiles away).
3. Inject dependencies (transports, renderers, providers) — tests never hit
   network, ffmpeg, or real media.
4. Determinism is tested where promised (same input ⇒ identical output).
5. Fixture time values use exact rationals; float comparisons use accuracy
   bounds.
6. A flaky test is a bug: fix the product or the test, never retry-loop it.

## Anti-flake specifics learned in this repo
- Date persistence needs sub-second precision (`millisecondsSince1970`).
- Repeated CLI/FFmpeg flags: assert against *all* occurrences.
- Swift argument labels are positional — helpers with many defaulted
  parameters should keep call sites in declaration order.
