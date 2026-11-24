import { createCipheriv, createDecipheriv, createHash, createHmac, randomBytes, timingSafeEqual } from "node:crypto";

/**
 * Stateless token sealing for the remote connector. Serverless functions keep
 * no memory between requests, so every OAuth artefact (client ids, codes,
 * access and refresh tokens) carries its own state, encrypted and
 * authenticated with AES-256-GCM under a key derived from UNIFY_MCP_SECRET.
 * The token's purpose is bound in as associated data, so a code can never be
 * replayed as an access token and so on.
 */
export type SealKind = "client" | "code" | "at" | "rt";

const b64url = (b: Buffer) => b.toString("base64url");

export class Sealer {
  private readonly key: Buffer;
  private readonly macKey: Buffer;

  constructor(secret: string) {
    if (!secret || secret.length < 32) {
      throw new Error("UNIFY_MCP_SECRET must be set to a random string of at least 32 characters.");
    }
    this.key = createHash("sha256").update(`unify-mcp:enc:${secret}`).digest();
    this.macKey = createHash("sha256").update(`unify-mcp:mac:${secret}`).digest();
  }

  seal(kind: SealKind, payload: object): string {
    const iv = randomBytes(12);
    const cipher = createCipheriv("aes-256-gcm", this.key, iv);
    cipher.setAAD(Buffer.from(kind));
    const body = Buffer.concat([cipher.update(JSON.stringify(payload), "utf8"), cipher.final()]);
    return b64url(Buffer.concat([iv, body, cipher.getAuthTag()]));
  }

  /** Returns the payload, or undefined when the token is forged, corrupt or of another kind. */
  open<T>(kind: SealKind, token: string | undefined | null): T | undefined {
    if (!token || typeof token !== "string" || token.length > 16_384) return undefined;
    try {
      const raw = Buffer.from(token, "base64url");
      if (raw.length < 12 + 16 + 2) return undefined;
      const iv = raw.subarray(0, 12);
      const tag = raw.subarray(raw.length - 16);
      const body = raw.subarray(12, raw.length - 16);
      const decipher = createDecipheriv("aes-256-gcm", this.key, iv);
      decipher.setAAD(Buffer.from(kind));
      decipher.setAuthTag(tag);
      const text = Buffer.concat([decipher.update(body), decipher.final()]).toString("utf8");
      return JSON.parse(text) as T;
    } catch {
      return undefined;
    }
  }

  /** Deterministic secret for confidential clients, derived from their client id. */
  clientSecret(clientId: string): string {
    return b64url(createHmac("sha256", this.macKey).update(`secret:${clientId}`).digest());
  }

  safeEqual(a: string, b: string): boolean {
    const x = Buffer.from(a);
    const y = Buffer.from(b);
    return x.length === y.length && timingSafeEqual(x, y);
  }
}

export function pkceS256(verifier: string): string {
  return createHash("sha256").update(verifier).digest("base64url");
}

/** Reads `exp` from a JWT without verifying it (Unify verifies its own tokens). */
export function jwtExpiry(jwt: string): number | undefined {
  try {
    const payload = JSON.parse(Buffer.from(jwt.split(".")[1], "base64url").toString("utf8"));
    return typeof payload.exp === "number" ? payload.exp : undefined;
  } catch {
    return undefined;
  }
}
