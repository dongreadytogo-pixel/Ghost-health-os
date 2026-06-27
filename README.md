# Ghost Health OS

> AI-powered personal health operating system — a provider-agnostic, clean-architecture core that continuously learns from your health, fitness, nutrition, sleep, and recovery data and coaches you like a team of specialists.

This is **not** a Fitbit companion, a dashboard, or a chatbot. It is a platform
whose architecture is designed so that data sources, AI agents, delivery
channels, and UI are all replaceable parts plugged into a stable, well-tested core.

> [!IMPORTANT]
> **Non-medical disclaimer.** Ghost Health OS is not intended to diagnose, treat,
> cure, or prevent any disease. All insights are educational and informational
> only. The blood-sugar module tracks **trends only** and never diagnoses.
> Consult qualified healthcare professionals for medical advice.

---

## Current status

This repository is at its **foundation milestone**. What exists today is real,
typed, and tested — not scaffolding stubs:

| Area | Status |
| --- | --- |
| Monorepo + tooling (pnpm, TypeScript strict, Vitest) | ✅ Done |
| `@ghost/domain` — pure provider-agnostic core | ✅ Done |
| Result/error model, branded types, validation guards | ✅ Done |
| Normalized health-sample contracts (sleep, recovery, workout, blood sugar) | ✅ Done |
| `HealthDataProvider` port (the "no hardcoded Fitbit" seam) | ✅ Done |
| Metrics engine: Sleep, Recovery, **Ghost Score** (explainable) | ✅ Done |
| 23 unit tests, all green | ✅ Done |
| Application layer, infrastructure adapters, API, dashboard, LINE bot | 🗺️ Roadmapped — see [`ROADMAP.md`](./ROADMAP.md) |

The guiding principle: **build a small, deep, correct core first**, then grow
outward layer by layer without ever redesigning the center.

---

## Why start at the core?

The master spec describes an enormous surface — dozens of data sources, ten AI
agents, a Thai-language dashboard, a LINE assistant, gamification, reports. The
fastest way to a *broken* product is to scaffold all of it shallowly. The fastest
way to a *durable* one is to nail the part everything else depends on:

- **The Ghost Score and its sub-scores are pure functions** with no I/O. They are
  the system's reasoning, and they are fully unit-testable in isolation.
- **Every score explains itself** (`Score.contributions`), satisfying the spec's
  "Explain every score" mandate and giving the AI agents structured rationale to
  speak from.
- **Data sources sit behind one port** (`HealthDataProvider`). Adding Apple
  Health or a CGM later means writing an adapter, not touching the core.

See [`ARCHITECTURE.md`](./ARCHITECTURE.md) for the full layering.

---

## Repository layout

```
ghost-health-os/
├── packages/
│   └── domain/                 # @ghost/domain — pure core (no I/O, no framework)
│       └── src/
│           ├── shared/         # Result, branded types, validation guards
│           ├── value-objects/  # Score (0–100, banded, explainable)
│           ├── health/         # normalized health-sample contracts
│           ├── providers/      # HealthDataProvider port
│           └── metrics/        # sleep / recovery / Ghost Score calculators
├── ARCHITECTURE.md             # layering, dependency rules, extension points
├── ROADMAP.md                  # the full spec mapped to incremental milestones
└── CONTRIBUTING.md             # conventions, how to add a provider / metric
```

Future packages (`@ghost/application`, `@ghost/infrastructure`) and apps
(`apps/api`, `apps/dashboard`, `apps/line-bot`) are described in the roadmap and
slot into this same workspace.

---

## Getting started

Requires Node ≥ 20 and pnpm.

```bash
pnpm install        # install workspace dependencies
pnpm test           # run all unit tests (currently @ghost/domain)
pnpm typecheck      # strict TypeScript check across the workspace
pnpm build          # compile packages
```

### A taste of the core

```ts
import {
  computeSleepScore,
  computeRecoveryScore,
  computeGhostScore,
  Score,
} from '@ghost/domain';

const sleep = computeSleepScore(sleepSample);           // 0–100, with reasons
const recovery = computeRecoveryScore(recoveryInputs, baseline);

const ghost = computeGhostScore([
  { category: 'sleep', score: sleep },
  { category: 'recovery', score: recovery },
]);

console.log(ghost.score.value);        // e.g. 78
console.log(ghost.focusArea);          // e.g. 'recovery' — what to fix first
console.log(ghost.score.contributions); // drillable, explainable breakdown
```

---

## Tech stack (target)

Frontend: Next.js · React · TypeScript · TailwindCSS ·
Backend: Cloudflare Workers · Supabase (PostgreSQL, Auth, Storage) ·
AI: Claude API · Delivery: LINE ·
Ops: GitHub Actions · Sentry · PostHog.

The domain core is deliberately framework-free so none of these choices leak
into the system's reasoning.

---

## License

MIT — see [`LICENSE`](./LICENSE). Users own their data.
