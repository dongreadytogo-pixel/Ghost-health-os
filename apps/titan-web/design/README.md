# Project Titan — UI Design System (Claude Design ready)

Standalone preview cards for the game's visual language — colours, rarity scale,
panels, bars, buttons and chips. Each file is a self-contained HTML preview with
a first-line `<!-- @dsCard group="..." -->` marker, which is exactly the format
[Claude Design](https://claude.ai/design) indexes into its Design System pane.

| File | Group | Contents |
|---|---|---|
| `00-foundations.html` | Foundations | brand palette, rarity scale, type |
| `01-panels-bars.html` | Components | panel, header pills, HP/EXP/enemy bars |
| `02-buttons.html` | Components | control buttons (default / pressed) |
| `03-chips.html` | Components | companion chips (rarity + bond), gear chips (+level) |

## Working with Claude Design

This web environment can't log into your Claude Design account directly
(`DesignSync` needs an interactive terminal). Two ways to connect them:

1. **Send to Claude Code Web** — from your Claude Design project, use
   *"Send to Claude Code Web"* to seed the project into this workspace; then the
   `/design-sync` skill can sync these components one at a time.
2. **Pull these in** — point Claude Design at this `design/` folder (these cards
   already carry `@dsCard` markers), or copy a card's styles into a Design
   project.

The single source of truth for live styles is the game itself
(`apps/titan-web/index.html` `:root` variables); these cards mirror those tokens
so design and gameplay stay visually identical. When you restyle in Claude
Design, fold the changes back into those CSS variables.
