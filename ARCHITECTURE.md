# Architecture

Ghost Health OS follows **Clean Architecture**. Dependencies point *inward*: outer
layers know about inner layers, never the reverse. The innermost layer — the
domain — knows nothing about databases, HTTP, vendors, or AI providers.

```
┌─────────────────────────────────────────────────────────────┐
│ Presentation        Next.js dashboard · LINE bot · CLI       │
│ ┌─────────────────────────────────────────────────────────┐ │
│ │ Application      use-cases, orchestration, AI agents      │ │
│ │ ┌─────────────────────────────────────────────────────┐ │ │
│ │ │ Domain        entities · value objects · metrics      │ │ │
│ │ │               (pure, no I/O, no framework)            │ │ │
│ │ └─────────────────────────────────────────────────────┘ │ │
│ │   Infrastructure  Supabase · Fitbit · Claude · LINE      │ │
│ └─────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

The **dependency rule** is enforced socially today and will be enforced
mechanically (lint boundaries / project references) as packages are added.

---

## Layers

### Domain — `packages/domain` (implemented)

Pure TypeScript. No `async` I/O, no `fetch`, no SDK imports. Deterministic and
exhaustively unit-testable. Contains:

- **Shared kernel** (`shared/`)
  - `Result<T, E>` — expected failures are values, not exceptions. The domain
    only `throw`s on true programmer errors.
  - `DomainError` — structured, machine-readable `code` + human `message`.
  - **Branded types** — `UserId`, `ProviderId`, `IsoDate`, … give nominal typing
    over structural `string`s at zero runtime cost.
  - **Guards** — composable, Result-returning validators (`ensureInRange`, …).

- **Value objects** (`value-objects/`)
  - `Score` — a normalized 0–100 value with a qualitative `band`
    (`critical`→`excellent`) and a list of weighted, self-explaining
    `contributions`. `Score.weighted()` re-normalizes automatically when factors
    are missing, so metrics **degrade gracefully** as data sources come and go.

- **Health contracts** (`health/`)
  - The *canonical, normalized* sample shapes (`SleepSample`, `RecoveryInputs`,
    `WorkoutSample`, `BloodSugarSample`). Every data source maps into these.
    Every metric and agent reads only these. This is the structural guarantee
    behind "never hardcode Fitbit-specific logic."

- **Ports** (`providers/`)
  - `HealthDataProvider` — the interface every data source implements.

- **Metrics** (`metrics/`) — the system's reasoning
  - `computeSleepScore` — duration (quadratic penalty below 7h), efficiency,
    deep %, REM %.
  - `computeRecoveryScore` — HRV and resting-HR deviation from a *personal*
    baseline, plus sleep and stress; re-weights across available signals.
  - `computeGhostScore` — weighted blend of category scores into the headline
    number, exposing the weakest category as a `focusArea` for coaching.

### Application — `packages/application` (roadmapped)

Use-cases that orchestrate the domain over time: sync pipelines, baseline
computation (trailing windows), trend/correlation analysis, the AI agent
runtime, report generation, notification timing. Depends on domain + ports;
receives concrete adapters via dependency injection.

### Infrastructure — `packages/infrastructure` (roadmapped)

Concrete adapters behind domain ports: a `FitbitProvider implements
HealthDataProvider`, a Supabase repository layer, a Claude-backed LLM client, a
LINE messaging client. Swapping any of these never touches the domain.

### Presentation — `apps/*` (roadmapped)

`apps/dashboard` (Next.js, Thai-first, mobile-first, dark mode),
`apps/line-bot` (Cloudflare Worker webhook), `apps/api`.

---

## Key design decisions

1. **Errors as values.** `Result`/`DomainError` keep failure paths type-checked
   and explicit. The application layer decides how to surface them; the domain
   never decides for it by throwing.

2. **Explainability is a first-class output, not an afterthought.** Every `Score`
   carries its `contributions`. The AI agents narrate *from structured rationale*
   rather than inventing justifications, which is both safer and more honest —
   directly serving the spec's "Explain every score."

3. **Personal baselines over population norms.** Recovery is scored relative to
   *your* trailing HRV/RHR, because absolute thresholds are misleading per-person.

4. **Graceful degradation.** Missing a data source lowers confidence, not
   correctness: weighted scores re-normalize over whatever signal exists.

5. **One seam per concern.** Data in → `HealthDataProvider`. Persistence →
   repository ports. AI → an LLM port. LINE → a messaging port. Each is the
   single place a vendor can change.

---

## Extension points (how the system grows without redesign)

| To add… | You write… | You never touch… |
| --- | --- | --- |
| A new wearable / CGM | an adapter implementing `HealthDataProvider` | the metrics or domain |
| A new metric | a pure function in `metrics/` returning a `Score` | persistence or UI |
| A new AI agent | an application-layer service reading domain outputs | the domain |
| A new delivery channel | a presentation adapter over a messaging port | the agents |

---

## Testing strategy

- **Domain:** exhaustive unit tests (pure functions make this cheap and fast).
  Edge cases — zero-sleep nights, missing baselines, empty category sets — are
  covered today.
- **Application (planned):** use-case tests with in-memory fake adapters.
- **Infrastructure (planned):** contract tests that every `HealthDataProvider`
  implementation must pass, guaranteeing adapters are interchangeable.
- **E2E (planned):** Playwright against the dashboard.
