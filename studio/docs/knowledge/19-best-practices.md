# 19 — Best Practices

## FCPXML generation
1. Rational time everywhere; snap edits to `frameDuration`; never floats.
2. Spine tiles `[0, duration)`; explicit gaps; children in parent source
   time (`T − offset + start`).
3. Deduplicate resources; document-unique ids; every `ref` resolves.
4. Deterministic output (stable attribute order) → diffable, cacheable,
   testable.
5. Validate before hand-off (`FCPXMLValidator`); tool errors over silent
   fixes.

## Swift architecture (as practiced in `studio/`)
- Clean layering: Core → Domain → engines → interfaces; inner layers never
  import outward.
- Value types for models; actors own mutable state; `Sendable` everywhere;
  no singletons — inject dependencies (transports, renderers, providers).
- One error currency (`StudioError`) mapped at module boundaries with
  stable machine codes.
- Protocol seams at platform edges (`#if canImport(...)` only in adapters,
  never in domain logic).
- Registries over switch statements for extensibility (tools, styles,
  presets, profiles).

## Performance
- Pure detection algorithms on plain arrays → vectorize later (vDSP) without
  API change; stream media instead of loading whole files; O(n) passes over
  timelines; lazy thumbnail/proxy generation; cache by content hash.
- Measure before optimizing; performance tests pin budgets (Phase 17).

## Editing/UX conventions
- Every mutating operation is an undoable `EditCommand`; UI never mutates
  `Timeline` directly.
- Long work off the main actor with progress reporting into the task queue;
  cancellation supported.
- Accessibility labels on all controls; localization-ready strings (no
  concatenated sentences); dark/light both first-class.

## Privacy & security
- Learning data local-only; never transmit project content without explicit
  action; API keys in Keychain; plugins signed + sandboxed; audit-log
  destructive operations.

## Maintainability
- Comments state non-obvious constraints, not narration.
- Docs update in the same commit as behavior changes (see 20).
- Regression test per fixed bug; deterministic tests only.
- Small, single-purpose commits with imperative messages.
