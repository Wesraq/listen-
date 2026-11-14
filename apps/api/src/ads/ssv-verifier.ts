import { createPublicKey, createVerify, timingSafeEqual } from 'crypto';

const VERIFIER_KEYS_URL = 'https://www.gstatic.com/admob/reward/verifier-keys.json';
const KEYS_TTL_MS = 60 * 60 * 1000;

type VerifierKey = { keyId: number; pem: string; base64?: string };

let cachedKeys: VerifierKey[] | null = null;
let cachedAt = 0;

async function loadVerifierKeys(): Promise<VerifierKey[]> {
  const now = Date.now();
  if (cachedKeys && now - cachedAt < KEYS_TTL_MS) return cachedKeys;
  const res = await fetch(VERIFIER_KEYS_URL);
  if (!res.ok) {
    throw new Error(`Failed to fetch AdMob verifier keys (${res.status})`);
  }
  const json = (await res.json()) as { keys?: VerifierKey[] };
  if (!json.keys?.length) throw new Error('AdMob verifier keys empty');
  cachedKeys = json.keys;
  cachedAt = now;
  return cachedKeys;
}

/**
 * AdMob SSV signs the raw query string up to (but excluding) `&signature=`.
 * signature and key_id are always the last two parameters.
 * @see https://developers.google.com/admob/android/ssv
 */
export async function verifyAdMobSsvQuery(rawQuery: string): Promise<{
  ok: boolean;
  reason?: string;
}> {
  const query = rawQuery.startsWith('?') ? rawQuery.slice(1) : rawQuery;
  const sigMarker = '&signature=';
  const sigIndex = query.indexOf(sigMarker);
  if (sigIndex < 0) {
    return { ok: false, reason: 'Missing signature parameter' };
  }
  const contentToVerify = query.slice(0, sigIndex);
  const params = new URLSearchParams(query);
  const signature = params.get('signature');
  const keyId = params.get('key_id');
  if (!signature || !keyId) {
    return { ok: false, reason: 'Missing signature or key_id' };
  }

  let keys: VerifierKey[];
  try {
    keys = await loadVerifierKeys();
  } catch (error) {
    return {
      ok: false,
      reason: error instanceof Error ? error.message : 'Verifier key fetch failed',
    };
  }

  const key = keys.find((k) => String(k.keyId) === keyId);
  if (!key?.pem) {
    return { ok: false, reason: `Unknown AdMob key_id ${keyId}` };
  }

  try {
    const publicKey = createPublicKey(key.pem);
    const verifier = createVerify('SHA256');
    verifier.update(contentToVerify);
    verifier.end();
    // AdMob signatures are URL-safe base64; Node accepts standard base64 after normalize.
    const normalized = signature.replace(/-/g, '+').replace(/_/g, '/');
    const ok = verifier.verify(publicKey, normalized, 'base64');
    return ok ? { ok: true } : { ok: false, reason: 'Invalid AdMob SSV signature' };
  } catch (error) {
    return {
      ok: false,
      reason: error instanceof Error ? error.message : 'SSV signature verify error',
    };
  }
}

/** Replay window: reject SSV callbacks older than this (ms). */
export const SSV_MAX_AGE_MS = 10 * 60 * 1000;

export function parseSsvTimestamp(raw?: string): number | null {
  if (!raw) return null;
  const n = Number(raw);
  if (!Number.isFinite(n) || n <= 0) return null;
  // AdMob sends unix ms (or sometimes seconds).
  return n < 1e12 ? n * 1000 : n;
}

export function assertFreshSsvTimestamp(raw?: string): { ok: boolean; reason?: string } {
  const ts = parseSsvTimestamp(raw);
  if (ts == null) return { ok: false, reason: 'Missing or invalid SSV timestamp' };
  const age = Date.now() - ts;
  if (age < -60_000) return { ok: false, reason: 'SSV timestamp in the future' };
  if (age > SSV_MAX_AGE_MS) return { ok: false, reason: 'SSV timestamp expired' };
  return { ok: true };
}

/** Constant-time-ish compare for transaction id presence checks. */
export function safeIncludes(set: Set<string>, value: string): boolean {
  if (!value) return false;
  if (set.has(value)) return true;
  // Touch equal path length to avoid trivial timing on empty.
  const probe = Buffer.from(value);
  const dummy = Buffer.alloc(probe.length, 0);
  try {
    timingSafeEqual(probe, dummy);
  } catch {
    /* length mismatch */
  }
  return false;
}
