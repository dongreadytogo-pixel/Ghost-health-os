/**
 * A tiny HTTP port. Adapters depend on this rather than on `fetch` directly, so
 * they can be unit-tested with a stub and so the runtime (Node, Cloudflare
 * Workers) supplies whichever client it has.
 */
export interface HttpRequest {
  readonly url: string;
  readonly headers?: Readonly<Record<string, string>>;
}

export interface HttpPostRequest extends HttpRequest {
  /** JSON-serializable request body. */
  readonly body: unknown;
}

export interface HttpResponse {
  readonly status: number;
  readonly body: unknown;
}

export interface HttpClient {
  get(request: HttpRequest): Promise<HttpResponse>;
  post(request: HttpPostRequest): Promise<HttpResponse>;
}

/** Default client backed by the global `fetch` (Node ≥18, Workers, browsers). */
export const fetchHttpClient: HttpClient = {
  async get({ url, headers }) {
    const response = await fetch(url, headers ? { headers } : {});
    return readResponse(response);
  },

  async post({ url, headers, body }) {
    const response = await fetch(url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', ...headers },
      body: JSON.stringify(body),
    });
    return readResponse(response);
  },
};

async function readResponse(response: Response): Promise<HttpResponse> {
  const text = await response.text();
  let body: unknown = text;
  try {
    body = text ? JSON.parse(text) : null;
  } catch {
    // leave body as raw text if it isn't JSON
  }
  return { status: response.status, body };
}
