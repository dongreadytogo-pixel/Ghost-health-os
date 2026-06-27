# Roadmap

The master spec is a destination, not a single sprint. This roadmap sequences it
into milestones that each leave the system **shippable and tested**, building
strictly outward from the domain core so no milestone forces a redesign of an
earlier one.

Legend: ✅ done · 🔜 next · 🗺️ planned

---

## M0 — Foundation ✅

The provider-agnostic, fully-tested core.

- ✅ pnpm monorepo, strict TypeScript, Vitest
- ✅ `Result`/`DomainError`, branded types, validation guards
- ✅ `Score` value object (banded, explainable, auto-reweighting)
- ✅ Normalized health-sample contracts
- ✅ `HealthDataProvider` port
- ✅ Sleep, Recovery, and **Ghost Score** calculators
- ✅ 23 passing unit tests

## M1 — Persistence & sync ✅

Get real Fitbit data flowing into storage through the existing port.

- ✅ `@ghost/application`: `SyncHealthData` use-case (provider → normalize → store)
- ✅ `HealthSampleRepository` port in domain + idempotent `sampleKey` identity
- ✅ `InMemoryHealthSampleRepository` reference implementation
- ✅ Repository **contract test suite** all stores must pass
- ✅ `FitbitProvider implements HealthDataProvider` (bearer auth, 401/429/transport
  mapped to typed `DomainError`s), with a pure, tested payload mapper
- ✅ `HttpClient` port so adapters are unit-testable without network
- ✅ PostgreSQL/Supabase schema with unique `sample_key` (idempotent upsert) and
  row-level security for user isolation
- 🔜 Wire the Supabase repository implementation against the schema + run the
  contract suite over it (deferred until a Supabase project/env is available)
- 🔜 Fitbit OAuth2 token exchange + refresh flow

## M2 — Metrics & scoring pipeline ✅

Turn stored samples into daily scores and trends.

- ✅ Baseline engine (trailing-window HRV/RHR means) for personalized recovery
- ✅ `ComputeDailyScores` use-case composing all available categories into the
  Ghost Score with a focus area
- ✅ Additional category scorers: nutrition, hydration, blood-sugar trend
  (non-diagnostic), heart, stress, consistency
- ✅ Training-load (ACWR) / readiness / overtraining-risk model
- ✅ Correlation engine (Pearson + plain-language insights: sleep↔recovery,
  protein↔recovery, meals↔blood sugar, …)

## M3 — AI agents & memory 🔜 (foundations ✅)

The "team of specialists."

- ✅ LLM port (`@ghost/application`) + Claude adapter (`@ghost/infrastructure`,
  official Anthropic SDK, injectable transport, refusal → typed error)
- ✅ Deterministic Thai daily-summary report generator (grounded, no
  hallucination — every line traces to a computed score)
- ✅ `CoachAgent` (Conversation Engine): answers natural Thai questions grounded
  on the day's computed scores, with a strict non-diagnostic system prompt
- 🔜 Remaining specialist agents (Fitness/Recovery/Nutrition/Sleep/Habit/
  Motivation Coaches, Prediction Engine, Report Generator variants)
- 🔜 AI Memory store (durable user patterns: schedule, meal timing, goals)
- 🔜 Prediction engine with explicit confidence + uncertainty
- 🔜 Live Claude wiring (needs an `ANTHROPIC_API_KEY` at runtime)

## M4 — Delivery: LINE assistant 🗺️

- 🗺️ `apps/line-bot` (Cloudflare Worker webhook)
- 🗺️ Natural Thai Q&A ("วันนี้ควรเล่นอะไร", "Recovery เท่าไร", …)
- 🗺️ Generated reports: morning / workout / evening / daily / weekly / monthly
- 🗺️ Adaptive notification timing (AI-chosen, never fixed schedules)

## M5 — Dashboard 🗺️

- 🗺️ `apps/dashboard` (Next.js, Thai-first, mobile-first, dark mode, responsive)
- 🗺️ Pages: Home, Today, Workout, Nutrition, Recovery, Sleep, Blood Sugar, Heart,
  Weight, Graphs, Calendar, Achievements, Reports, AI Insights, Settings
- 🗺️ Drillable score explanations powered by `Score.contributions`

## M6 — Engagement & reporting 🗺️

- 🗺️ Gamification: levels, XP, achievements, streaks, challenges
- 🗺️ Report export: PDF / Excel / CSV with charts and recommendations

## M7 — Hardening & scale 🗺️

- 🗺️ Security: OAuth, JWT, encryption at rest, RBAC, secrets management, rate
  limiting, audit logs, automated backups
- 🗺️ Observability: Sentry, PostHog
- 🗺️ CI/CD: GitHub Actions (typecheck, test, build, deploy to Cloudflare)
- 🗺️ Performance: edge caching, query optimization, lazy loading
- 🗺️ Enforce architecture boundaries mechanically (lint/project references)

## Future 🗺️

Apple Watch · Apple Intelligence · Siri · Widgets · Live Activities · Android ·
Wear OS · Desktop · Family / Doctor / Coach dashboards · Voice AI · Public API ·
Plugin marketplace · Multi-language.

---

## Sequencing principles

1. **Inside-out.** Never build a UI for a metric that doesn't exist, or a metric
   for data that can't be synced.
2. **Every milestone ships green.** No milestone is "done" until typecheck and
   tests pass.
3. **Adapters behind ports.** Each new vendor is an adapter + contract-test pass,
   never a change to the core.
4. **Explainability stays first-class** at every layer it flows through.
