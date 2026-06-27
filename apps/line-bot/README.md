# Ghost Health OS — LINE assistant

A Cloudflare Worker that answers Thai health questions on LINE using the
**free-tier Gemini API**. A personal bot runs at **zero token cost** (free Gemini
key + free LINE reply messages).

```
LINE message → verify signature → CoachAgent (free Gemini) → reply on LINE
```

Until a wearable is connected, the coach answers general, non-diagnostic health
questions. Once `ComputeDailyScores` is wired in, the same `CoachAgent` grounds
answers on the user's real daily scores — no change to this Worker.

## Secrets (never commit these)

Three values, set as Worker **secrets** (encrypted — not plain `vars`):

| Secret | Where to get it |
| --- | --- |
| `GEMINI_API_KEY` | aistudio.google.com → Get API key (free) |
| `LINE_CHANNEL_SECRET` | LINE Developers → your channel → Basic settings |
| `LINE_CHANNEL_ACCESS_TOKEN` | LINE Developers → your channel → Messaging API |

## Deploy (with Wrangler)

```bash
# from this folder: apps/line-bot
npx wrangler login                       # opens a browser, one time
npx wrangler secret put GEMINI_API_KEY
npx wrangler secret put LINE_CHANNEL_SECRET
npx wrangler secret put LINE_CHANNEL_ACCESS_TOKEN
npx wrangler deploy
```

`wrangler deploy` prints your Worker URL, e.g.
`https://ghost-line-bot.<you>.workers.dev`.

## Point LINE at the Worker

1. LINE Developers → your channel → **Messaging API** tab.
2. **Webhook URL** → paste your Worker URL, then **Verify** (expects 200).
3. Turn **Use webhook** ON.
4. Under **LINE Official Account features**, turn **Auto-reply messages** OFF
   (so only the bot replies) and **Greeting messages** as you like.
5. Add the bot as a friend (QR code on the same page) and send it a message.

Open the Worker URL in a browser — a GET returns
`Ghost LINE bot is running.`, confirming it's live before you wire the webhook.

## Local checks

```bash
pnpm --filter @ghost/line-bot typecheck
pnpm --filter @ghost/line-bot test     # signature-verification tests
```
