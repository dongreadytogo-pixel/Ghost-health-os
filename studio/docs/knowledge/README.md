# Ghostly790k Knowledge Base

The single source of truth for the Ghostly790k AI Final Cut Studio project.
Every feature references these documents before implementation; when a
document is incomplete, improve it first (see
[20-development-rules.md](20-development-rules.md)).

| # | Document | Scope |
|---|----------|-------|
| 01 | [final-cut-core.md](01-final-cut-core.md) | FCP object model & UI concepts |
| 02 | [fcpxml-specification.md](02-fcpxml-specification.md) | FCPXML elements, time syntax, versions |
| 03 | [final-cut-workflow.md](03-final-cut-workflow.md) | Import → edit → export pipeline |
| 04 | [keyboard-shortcuts.md](04-keyboard-shortcuts.md) | FCP shortcuts by category |
| 05 | [effect-library.md](05-effect-library.md) | Built-in effects, transitions, tracking |
| 06 | [motion-template-system.md](06-motion-template-system.md) | Motion templates & published parameters |
| 07 | [color-grading.md](07-color-grading.md) | Color tools, LUTs, log, HDR, ACES |
| 08 | [audio-system.md](08-audio-system.md) | Roles, repair tools, loudness, podcast |
| 09 | [video-editing-theory.md](09-video-editing-theory.md) | Cuts, pacing, structure |
| 10 | [professional-editing-workflows.md](10-professional-editing-workflows.md) | Per-genre delivery conventions |
| 11 | [apple-frameworks.md](11-apple-frameworks.md) | AVFoundation, Vision, CoreML, Metal… |
| 12 | [macos-development.md](12-macos-development.md) | Sandbox, signing, notarization, updates |
| 13 | [ai-video-technologies.md](13-ai-video-technologies.md) | Whisper, ONNX, YOLO, SAM, CLIP, MCP |
| 14 | [plugin-sdk.md](14-plugin-sdk.md) | Plugin API, manifest, lifecycle, permissions |
| 15 | [marketplace-system.md](15-marketplace-system.md) | Packages, licensing, updates, cache |
| 16 | [testing-guidelines.md](16-testing-guidelines.md) | Test strategy for this repo |
| 17 | [commercial-release.md](17-commercial-release.md) | Packaging, updates, licensing, telemetry |
| 18 | [glossary.md](18-glossary.md) | Terms used across the project |
| 19 | [best-practices.md](19-best-practices.md) | Engineering & FCPXML best practices |
| 20 | [development-rules.md](20-development-rules.md) | Binding rules for all future work |
| ★ | [CONSTITUTION.md](CONSTITUTION.md) | AI Coding Constitution — mandatory engineering rules (overrides all) |

**Language policy:** Thai is a primary target alongside English — Thai-audio
clips and Thai captions must be first-class. Text handling must not assume
space-delimited words (see the Constitution's language-support clause).

Primary external sources: Apple's FCPXML Reference
(https://developer.apple.com/documentation/professional-video-applications/fcpxml-reference),
Final Cut Pro User Guide (https://support.apple.com/guide/final-cut-pro/),
and Apple framework documentation (https://developer.apple.com/documentation/).
