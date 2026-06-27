# Contributing

## Principles

This project optimizes for **longevity**: it is built as if it will serve
millions of users for years. Before adding code, prefer improving design,
removing duplication, and strengthening tests. Read [`ARCHITECTURE.md`](./ARCHITECTURE.md)
first — the dependency rule is non-negotiable.

## Conventions

- **TypeScript strict everywhere.** No `any`, no non-null `!` to silence the
  compiler. `noUncheckedIndexedAccess` and `exactOptionalPropertyTypes` are on.
- **Domain is pure.** Nothing in `packages/domain` may import a framework, SDK,
  or perform I/O. If you need `await`, you're in the wrong layer.
- **Errors are values.** Return `Result`/`DomainError` for expected failures;
  reserve `throw` for programmer errors.
- **Scores explain themselves.** Any new metric returns a `Score` with populated
  `contributions`. Non-diagnostic language only — especially for blood sugar.
- **Test what you add.** New domain logic ships with unit tests in the same
  milestone.

## Local workflow

```bash
pnpm install
pnpm test          # all packages
pnpm typecheck     # strict check
pnpm build
```

Run a single package's tests in watch mode:

```bash
pnpm --filter @ghost/domain test:watch
```

## Adding a new data source

1. Implement `HealthDataProvider` in `@ghost/infrastructure`.
2. Map the vendor payload into the canonical `health/samples` shapes — **do not**
   leak vendor fields upward.
3. Make the provider pass the shared provider contract test suite (M1).
4. Surface transport/auth failures as a `DomainError` result; never throw across
   the port.

## Adding a new metric

1. Write a pure function in `packages/domain/src/metrics/` returning a `Score`.
2. Populate `contributions` with weighted, human-readable, non-diagnostic
   explanations.
3. Cover edge cases (missing data, zero/degenerate inputs) with tests.
4. Export it from `src/index.ts`.

## Commit messages

Clear, imperative, scoped. Example: `domain: add hydration score calculator`.
