import crypto from 'node:crypto';

const DEFAULT_MAX_SKEW_MS = 5 * 60 * 1000;

function getHeader(headers, key) {
  return headers[key] ?? headers[key.toLowerCase()] ?? headers[key.toUpperCase()];
}

function normalizeRawBody(req) {
  if (typeof req.rawBody === 'string') return req.rawBody;
  if (Buffer.isBuffer(req.rawBody)) return req.rawBody.toString('utf8');
  if (typeof req.body === 'string') return req.body;
  return JSON.stringify(req.body ?? {});
}

function getSecretForTier(tier) {
  const envKey = `NSTYLE_AGENT_TOKEN_${String(tier ?? '').toUpperCase()}`;
  return process.env[envKey] ?? process.env.NSTYLE_AGENT_TOKEN;
}

function safeEqualsHex(providedHex, expectedHex) {
  const provided = Buffer.from(providedHex, 'hex');
  const expected = Buffer.from(expectedHex, 'hex');
  if (provided.length !== expected.length) return false;
  return crypto.timingSafeEqual(provided, expected);
}

export function verifyTieredAuditRouteSignature(req) {
  const timestampRaw = getHeader(req.headers ?? {}, 'x-sentinel-timestamp');
  const signature = getHeader(req.headers ?? {}, 'x-sentinel-signature');
  const auditTier = getHeader(req.headers ?? {}, 'x-audit-tier');

  if (!timestampRaw || !signature || !auditTier) {
    return { ok: false, reason: 'missing_signature_headers' };
  }

  const timestampMs = Number(timestampRaw);
  if (!Number.isFinite(timestampMs)) {
    return { ok: false, reason: 'invalid_timestamp' };
  }

  const clockSkewMs = Math.abs(Date.now() - timestampMs);
  if (clockSkewMs > DEFAULT_MAX_SKEW_MS) {
    return { ok: false, reason: 'timestamp_out_of_window' };
  }

  const secret = getSecretForTier(auditTier);
  if (!secret) {
    return { ok: false, reason: 'missing_server_secret' };
  }

  const rawBody = normalizeRawBody(req);
  const canonical = [
    String(req.method ?? 'POST').toUpperCase(),
    String(req.originalUrl ?? req.url ?? '/'),
    String(timestampMs),
    String(auditTier),
    rawBody,
  ].join('\n');

  const expected = crypto.createHmac('sha256', secret).update(canonical).digest('hex');
  const valid = /^[a-fA-F0-9]+$/.test(signature) && safeEqualsHex(signature, expected);

  return {
    ok: valid,
    reason: valid ? undefined : 'signature_mismatch',
    auditTier,
    timestampMs,
    rawBody,
  };
}
