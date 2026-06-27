/**
 * Minimal LINE Messaging API helpers — just enough to read inbound text events
 * and reply. Replying with the event's `replyToken` is free of charge on LINE
 * (only proactive push messages count against the monthly quota).
 */
const REPLY_URL = 'https://api.line.me/v2/bot/message/reply';

export interface LineTextMessageEvent {
  readonly type: 'message';
  readonly replyToken: string;
  readonly message: { readonly type: string; readonly text?: string };
}

export interface LineWebhookBody {
  readonly events?: readonly unknown[];
}

/** Narrow an arbitrary webhook event to a text message we can answer. */
export function asTextEvent(event: unknown): LineTextMessageEvent | undefined {
  if (typeof event !== 'object' || event === null) return undefined;
  const e = event as Record<string, unknown>;
  if (e['type'] !== 'message' || typeof e['replyToken'] !== 'string') {
    return undefined;
  }
  const message = e['message'];
  if (
    typeof message !== 'object' ||
    message === null ||
    (message as Record<string, unknown>)['type'] !== 'text' ||
    typeof (message as Record<string, unknown>)['text'] !== 'string'
  ) {
    return undefined;
  }
  return event as LineTextMessageEvent;
}

/** Reply to a message. LINE caps a single reply at 5 message bubbles. */
export async function replyText(
  accessToken: string,
  replyToken: string,
  text: string,
): Promise<void> {
  await fetch(REPLY_URL, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${accessToken}`,
    },
    body: JSON.stringify({
      replyToken,
      messages: [{ type: 'text', text: text.slice(0, 4900) }],
    }),
  });
}
