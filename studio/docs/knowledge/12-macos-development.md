# 12 — macOS Development

Source: https://developer.apple.com/documentation/ (Security, Xcode,
Notarization guides).

## App Sandbox
Mandatory for App Store; recommended everywhere. Entitlements gate file
access, network, Apple Events. User-selected files are reachable via
open/save panels; retain access across launches with **security-scoped
bookmarks** (`URL.bookmarkData(options: .withSecurityScope)` →
`startAccessingSecurityScopedResource`). The studio stores bookmarks for
media folders and FCP libraries.

## Hardened Runtime & code signing
- Sign every binary/framework with a Developer ID Application certificate;
  enable Hardened Runtime (required for notarization).
- Plugins (dylib/bundle) must be signed; library validation restricts
  loading unsigned code — plugin loading uses XPC/ExtensionKit instead of
  raw dlopen (see 14).

## Notarization
`xcrun notarytool submit <dmg/zip> --keychain-profile … --wait` then
`xcrun stapler staple`. Gatekeeper checks on first launch. CI job planned
for release pipeline (Phase 18).

## Distribution
- **DMG or pkg installer**, signed + notarized.
- **Sparkle** framework for auto-updates (appcast XML + EdDSA signatures)
  outside the App Store; App Store handles updates itself.

## System integration
- **Spotlight** — `CSSearchableItem` for projects/assets so users can find
  studio content system-wide.
- **QuickLook** — preview extension for `.fcpxml`/project files.
- **File Provider** — only if exposing a virtual asset drive (not planned).
- **TCC privacy prompts** — microphone (record VO), Apple Events
  (control FCP), files; each needs a usage-description Info.plist key.

## Data locations
App Support: `~/Library/Application Support/Ghostly/` (sandbox container
path when sandboxed); preferences in `~/.ghostly` today (CLI/MCP context) —
converges on App Support for the shipping app. Keychain for API keys —
never plist/JSON (see 19).

## Crash reporting & logs
`os.Logger` with subsystem/category mirrors our `GhostlyCore.Logger`
backends; MetricKit (`MXCrashDiagnostic`) for opt-in crash reports.
