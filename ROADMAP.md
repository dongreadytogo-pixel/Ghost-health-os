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

## M1 — Persistence & sync 🔜

Get real Fitbit data flowing into storage through the existing port.

- 🔜 `@ghost/application`: `SyncHealthData` use-case (provider → normalize → store)
- 🔜 Repository ports in domain; Supabase/PostgreSQL implementations in
  `@ghost/infrastructure`
- 🔜 `FitbitProvider implements HealthDataProvider` (OAuth2, rate-limit aware)
- 🔜 Database schema + migrations for the entities in the spec's data model
- 🔜 Provider **contract test suite** all adapters must pass
- 🔜 Idempotent upserts keyed on `SampleSource.externalId`

## M2 — Metrics & scoring pipeline 🗺️

Turn stored samples into daily scores and trends.

- 🗺️ Baseline engine (trailing-window HRV/RHR means) for personalized recovery
- 🗺️ Daily Ghost Score job composing all available categories
- 🗺️ Additional category scorers: nutrition, workout load, blood-sugar trend,
  hydration, heart, stress, consistency
- 🗺️ Training-load / readiness / overtraining-risk model
- 🗺️ Correlation engine (sleep↔recovery, protein↔recovery, meals↔blood sugar, …)

## M3 — AI agents & memory 🗺️

The "team of specialists."

- 🗺️ LLM port + Claude adapter (`@ghost/infrastructure`)
- 🗺️ Agent runtime: Health Analyst, Fitness/Recovery/Nutrition/Blood-Sugar/Sleep/
  Habit/Motivation Coaches, Prediction Engine, Conversation Engine, Report
  Generator, Memory Engine
- 🗺️ AI Memory store (durable user patterns: schedule, meal timing, goals)
- 🗺️ Agents narrate strictly from `Score.contributions` (no invented rationale)
- 🗺️ Prediction engine with explicit confidence + uncertainty

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
