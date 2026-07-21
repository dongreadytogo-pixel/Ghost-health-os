# 15 — Marketplace System (design specification)

Status: specification for Phase 14.

## Package types
Plugins (see 14), subtitle packs (`CaptionStyle` sets), LUT packs (`.cube`),
transition/effect presets, Motion packs (template bundles), AI workflow
recipes (saved `EditIntent` chains + profiles).

## Package format
Signed zip: `manifest.json` (id, type, version, min versions, checksums,
license), payload folder, preview assets. Checksums verified before install;
signature verified against publisher keys.

## Install flow
download → verify signature + checksums → stage → activate (register into
the matching registry / copy Motion templates) → record in local catalog.
Rollback = keep previous staged version until activation succeeds.

## Updates
Catalog endpoint lists latest versions; semver-aware updater surfaces
changelogs; auto-update opt-in per package.

## Ratings & reviews
Server-side; the client displays aggregate rating + review snippets;
submissions require an account. Never blocks offline use.

## Licensing
- Free, paid, subscription entitlements.
- License tokens bound to account (not machine) with offline grace period;
  validation endpoint + locally cached signed entitlement.

## Offline cache
Everything installed keeps working offline; the catalog caches with ETags;
downloads resume.

## Security posture
Same rules as plugins: signed content only in release builds; marketplace
payloads never execute at install time (activation goes through the
sandboxed plugin path); template/LUT packs are data-only.
