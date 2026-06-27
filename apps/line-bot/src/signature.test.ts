import { describe, it, expect } from 'vitest';
import { verifyLineSignature } from './signature.js';

/** Produce a valid LINE signature for a body, the way LINE's servers do. */
async function sign(secret: string, body: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    'raw',
    new TextEncoder().encode(secret),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign'],
  );
  const mac = await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(body));
  let binary = '';
  for (const b of new Uint8Array(mac)) binary += String.fromCharCode(b);
  return btoa(binary);
}

describe('verifyLineSignature', () => {
  const secret = 'test-channel-secret';
  const body = JSON.stringify({ events: [{ type: 'message' }] });

  it('accepts a correctly signed body', async () => {
    const signature = await sign(secret, body);
    expect(await verifyLineSignature(secret, body, signature)).toBe(true);
  });

  it('rejects a tampered body', async () => {
    const signature = await sign(secret, body);
    expect(await verifyLineSignature(secret, body + ' ', signature)).toBe(false);
  });

  it('rejects a signature made with the wrong secret', async () => {
    const signature = await sign('attacker-secret', body);
    expect(await verifyLineSignature(secret, body, signature)).toBe(false);
  });

  it('rejects a missing signature header', async () => {
    expect(await verifyLineSignature(secret, body, null)).toBe(false);
  });
});
