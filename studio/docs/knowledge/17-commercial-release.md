# 17 — Commercial Release (Phase 18 playbook)

## Packaging
Universal (arm64 + x86_64) app bundle; embedded frameworks signed
inside-out; helper tools (`ghostly`, `ghostly-mcp-server`) in
`Contents/Helpers/` with a "install command line tools" symlink action.

## Installer & distribution
Notarized DMG (drag-to-Applications) as primary; signed pkg where MDM
deployment matters. App Store build variant: sandbox-strict, Sparkle
removed.

## Updates
**Sparkle 2**: appcast.xml served over HTTPS, EdDSA-signed archives, delta
updates, staged rollout percentages, release notes per item.

## Crash reporting & telemetry
- Crash: MetricKit diagnostics uploaded **only with consent**.
- Telemetry: strictly opt-in, anonymous feature counters; never project
  content, never media paths (aligns with AI MEMORY privacy rules).

## Licensing & activation
- Ed25519-signed license keys carrying plan + seat count + expiry.
- Activation server issues a signed entitlement cached locally; 14-day
  offline grace; deactivation frees a seat. Trial = time-boxed entitlement.

## Versioning & channels
Semantic versioning; channels: `stable`, `beta` (separate appcasts).
`CHANGELOG.md` is the single changelog source; release notes generated
from it.

## Release checklist
1. All CI suites green on macOS + Linux; performance suite within budgets
2. Accessibility + localization pass (see 16/19)
3. Security review: entitlements minimal, keys in Keychain, plugins signed
4. Notarize + staple; Gatekeeper test on a clean machine
5. Demo project + sample plugins bundled; onboarding tutorial updated
6. Docs regenerated (user guide, SDK guide, API reference)
7. Tag release, publish appcast, staged rollout 10% → 100%
