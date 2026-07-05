# 14 — Plugin SDK (design specification)

Status: specification for Phase 13; interfaces here are the contract the
implementation must satisfy. Registry seam already exists
(`MCPServer.register`, `PacingProfile`, `CaptionStyle`, `RenderPreset` are
all data-driven).

## What a plugin can contribute
- MCP tools (new agent-callable operations)
- Pacing profiles / caption styles / render presets
- Effects & Motion template packs (installed to Motion Templates folder)
- Detection providers (`AudioSampleProviding`, `FrameHistogramProviding`)
- LLM providers (`LLMProvider`)

## Manifest (`plugin.json`)
```json
{
  "id": "com.example.retro-pack",
  "name": "Retro Pack",
  "version": "1.2.0",
  "minStudioVersion": "1.0.0",
  "author": "Example Co",
  "entryPoint": "RetroPack.bundle",
  "permissions": ["filesystem.read", "network"],
  "contributes": ["captionStyles", "renderPresets", "mcpTools"]
}
```
- **Versioning** — semantic versioning; the SDK's public API is versioned
  independently; `minStudioVersion` gates installs; breaking SDK changes
  bump SDK major and are announced one minor release ahead.

## Lifecycle
`discovered → validated (signature + manifest) → loaded → activated
(register contributions) → deactivated → unloaded`
Hot reload = deactivate → replace bundle → activate; only contribution
registries are mutated, so no engine restart is needed.

## Isolation & permissions
Plugins run out-of-process (ExtensionKit/XPC) with a declared-permission
model: filesystem scopes, network, FCP automation. The host proxies all
engine calls; a crashing plugin cannot take down the studio. Unsigned
plugins refuse to load in release builds.

## Dependency injection
Plugins receive a `StudioServices` facade (logger, preference store,
registries) — never global singletons — mirroring how tests inject stubs
today.

## Developer experience (planned)
`ghostly plugin new/build/validate/pack` CLI; a debugger harness that hosts
one plugin with verbose logging; template projects per contribution type;
documentation generated from the manifest schema.
