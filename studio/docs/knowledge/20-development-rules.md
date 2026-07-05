# 20 — Development Rules (binding)

These rules govern all future work on Ghostly790k AI Final Cut Studio.

1. **Knowledge Base first.** Before implementing any feature, read the
   relevant documents here. If the needed knowledge is missing or
   incomplete, improve the document *before* writing code.
2. **Single source of truth.** This Knowledge Base is authoritative for
   Final Cut Pro behavior, FCPXML semantics, platform conventions, and
   studio architecture decisions. Code comments may summarize; they must
   not contradict.
3. **No duplicated knowledge.** Link between documents instead of copying.
   One fact lives in one place.
4. **Synchronized documentation.** A change in behavior lands in the same
   commit as its documentation update (KB, CHANGELOG, README/ROADMAP as
   applicable).
5. **Cite sources.** Prefer official Apple documentation; cite it inline
   (URL) in KB documents. Implementation-derived facts cite the file/test
   that proves them.
6. **Task discipline.** Always work the highest-priority unfinished
   roadmap task; never rebuild completed work; resume from the latest
   checkpoint (ROADMAP.md + task list are the checkpoint record).
7. **Feature lifecycle.** Analyze → design → implement → test → debug →
   optimize → document → commit → continue. A feature is complete only
   with implementation, tests (success + failure paths), error handling,
   logging, docs, and CI green on both platforms.
8. **Quality bars.** No placeholder code, no TODO comments in shipped
   source, no fake implementations, no hardcoded secrets or magic values;
   typed errors; injected dependencies; deterministic engines.
9. **Verification.** CI (Linux + macOS) is the arbiter. Every CI failure
   is fixed forward with a regression test where applicable.
10. **Privacy defaults.** Local-first; nothing leaves the machine without
    explicit user action; keys in Keychain; opt-in telemetry only.
