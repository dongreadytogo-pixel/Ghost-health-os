/**
 * Verify the `x-line-signature` header on an incoming webhook.
 *
 * LINE signs every request body with HMAC-SHA256 using your Channel secret and
 * sends the Base64 result in the header. Verifying it proves the request really
 * came from LINE (not a spoofer), so we never act on — or spend Gemini quota on
 * — forged requests. Uses Web Crypto, which exists in both Cloudflare Workers
 * and Node ≥18.
 */
export async function verifyLineSignature(
  channelSecret: string,
  rawBody: string,
  signature: string | null,
): Promise<boolean> {
  if (!signature) return false;

  const key = await crypto.subtle.importKey(
    'raw',
    new TextEncoder().encode(channelSecret),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign'],
  );
  const mac = await crypto.subtle.sign(
    'HMAC',
    key,
    new TextEncoder().encode(rawBody),
  );
  const expected = arrayBufferToBase64(mac);

  return timingSafeEqual(expected, signature);
}

function arrayBufferToBase64(buffer: ArrayBuffer): string {
  const bytes = new Uint8Array(buffer);
  let binary = '';
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary);
}

/** Length-aware, constant-time string comparison. */
function timingSafeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let mismatch = 0;
  for (let i = 0; i < a.length; i++) {
    mismatch |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }
  return mismatch === 0;
}
