# Play Lucky Town on your phone (iPhone / Android)

You don't need a PC. The game exports to the **web** and is published to
**GitHub Pages**, so you open a link in your phone's browser and play. On-screen
touch controls replace the keyboard.

---

## One-time setup (do this once, works from the GitHub mobile site)

1. Open the repo on github.com → **Settings** → **Pages**.
2. Under **Build and deployment → Source**, choose **GitHub Actions**.
3. That's it. Every push that touches `lucky-town/` runs the
   **“Lucky Town Web Build”** workflow, which builds the game and deploys it.

> You can also trigger it manually: repo → **Actions** → *Lucky Town Web Build*
> → **Run workflow**.

After the first green run, your play URL appears in two places:
- **Settings → Pages** (“Your site is live at …”), and
- the workflow run’s **summary** (the `github-pages` environment URL).

It looks like `https://<your-username>.github.io/<repo>/`.

---

## How to play (touch controls)

Open the URL in **Safari** (iPhone) or **Chrome** (Android). On the first load
the page may reload once — that's the cross-origin-isolation shim enabling the
game's threads. Then:

| Control | What it does |
| --- | --- |
| **Left thumb stick** | Walk around the city (drag anywhere on the lower-left) |
| **Interact (E)** | Play a slot machine when you're standing next to one |
| **Board** | Quests, rankings, odd jobs, buy land / build / upgrade |
| **Auction** | Bid on or list pets and land |
| **Stats** | Lifetime statistics and achievements |
| **Menu** | Pause — save / load across slots, resume, quit |

Each panel has an on-screen **Close** button (panels also pause the world while
open). Add the page to your Home Screen for a full-screen, app-like feel
(Safari → Share → *Add to Home Screen*).

---

## Notes & limitations

- **Saves** live in your browser's storage (per device/browser). Clearing site
  data erases them. Cloud saves are a future item.
- **Performance**: this is a real-time 3D sim running in a mobile browser with
  placeholder art. It runs, but expect modest frame rates until the art pass and
  mobile LOD work land (see `ROADMAP.md`).
- **Audio** may require one tap to start (browser autoplay policy) — and there's
  no audio yet anyway.
- If the page shows a blank screen, give it a moment on first load (it reloads
  once for the isolation shim), or hard-refresh.

---

## Why a browser and not the App Store?

Shipping a native iOS build needs a Mac + Xcode + an Apple Developer account.
The web build needs none of that and works on any phone immediately — ideal for
playtesting from your iPhone today. A native iOS/Android build is still on the
roadmap for later (Godot exports to both).
