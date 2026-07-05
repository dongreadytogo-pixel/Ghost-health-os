# AI Coding Constitution — v1.0

The mandatory engineering rules for Ghostly790k AI Final Cut Studio. These
rules **override convenience, shortcuts, and temporary solutions** and apply
to every file, module, feature, and commit. They complement and reinforce
[20-development-rules.md](20-development-rules.md).

## Mission
Build a production-grade **commercial macOS application** — never a demo,
prototype, or placeholder. Every change moves toward a releasable product.

### First-class language support
Thai is a primary target: the studio must handle **Thai-audio clips and Thai
captions** as well as English. Text handling must not assume space-delimited
words (Thai has no inter-word spaces); caption roles must carry the correct
language code; transcription and styling must round-trip Thai text intact.

## General principles (in priority order)
Correctness · Maintainability · Performance · Scalability · Readability ·
Testability · Security · Modularity · Consistency · Developer Experience ·
User Experience.

## Implementation rules
- No fake implementations, simulated functionality, or empty
  architecture-only types.
- No placeholder methods, dummy return values, or hidden unfinished code.
- Every public feature must actually work.

## No placeholders — forbidden in shipped source
`TODO`, `FIXME`, temporary hacks, dummy code, mock business logic,
unimplemented APIs, fake data, commented-out production code, example-only
implementations.

## Architecture
Clean Architecture; separation of concerns. Never mix UI with business logic
or persistence with domain logic. Never bypass abstractions. Prefer
dependency injection; avoid tight coupling. Every module independently
testable.

## Code quality
Self-documenting code, meaningful names, no duplicated logic, reusable
components, composition over inheritance, no global state, minimal side
effects.

## Error handling
Never ignore errors or fail silently. Surface meaningful diagnostics
(`StudioError`), recover safely where possible, log failures appropriately.

## Testing
Every feature needs unit, integration, failure, and edge-case tests plus
performance validation. No feature is complete until all tests pass on
Linux **and** macOS.

## Performance
Measure before optimizing. Avoid needless allocations and main-thread
blocking. Use concurrency responsibly. Prefer streaming over loading whole
files. Use Metal / hardware acceleration where appropriate.

## Documentation
Every module documents purpose, architecture, dependencies, public
interfaces, usage, limitations, and extension points — kept synchronized
with the implementation, in the same commit.

## Security
Protect user data; respect the macOS sandbox; never expose API keys
(Keychain only); validate all external input; secure defaults; never
transmit project data without explicit user permission.

## AI usage
AI assists implementation but never replaces engineering discipline. Verify
all generated code; prefer deterministic behavior over speculation.

## Dependencies
Add external dependencies only for clear long-term value; prefer native Apple
frameworks; document every dependency; remove unused ones.

## Plugin system
Plugins are sandboxed, declare permissions, expose version info, never modify
core modules directly, and communicate only through stable APIs.

## MCP server
Every exposed tool has a clear JSON schema, input validation, error handling,
documentation, versioning, and backward compatibility.

## User experience
Feels native macOS. Smooth animations, understandable errors, progress for
long-running tasks, responsive background work, mandatory accessibility,
localization-ready by design (Thai + English first).

## Refactoring
Continuously improve: refactor duplication, simplify complexity, strengthen
weakening architecture. Refactoring is part of implementation.

## Autonomous execution
Continuously: analyze the next unfinished task → verify dependencies →
implement → compile → test → fix failures → optimize → refactor → update
docs → record progress → commit → continue. Do not stop after one feature.

## Progress tracking
Maintain a living status report: completed / in-progress / remaining
features, known issues, technical debt, test coverage, performance metrics,
release readiness (see ROADMAP.md + CHANGELOG.md).

## Definition of done
Compiles; all tests pass; docs updated; performance acceptable; no
placeholder code; no known critical bugs; integrates correctly with the rest
of the app.

## Final rule
Always build software you would confidently ship to paying customers. Never
sacrifice long-term quality for short-term speed.
