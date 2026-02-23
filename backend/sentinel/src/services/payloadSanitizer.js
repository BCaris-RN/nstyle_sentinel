import { HttpError } from '../errors/httpError.js';

const MAX_BODY_BYTES = 8 * 1024;
const ALLOWED_ACTIONS = new Set(['book', 'cancel', 'modify']);

function boundedString(value, field, { max = 200, min = 0 } = {}) {
  if (typeof value !== 'string') {
    throw new HttpError(400, `${field} must be a string`, 'invalid_payload');
  }
  const trimmed = value.trim();
  if (trimmed.length < min || trimmed.length > max) {
    throw new HttpError(400, `${field} length is invalid`, 'invalid_payload');
  }
  return trimmed;
}

function optionalString(value, field, opts = {}) {
  if (value == null) return undefined;
  return boundedString(value, field, opts);
}

function parseIsoDate(value, field) {
  const text = boundedString(value, field, { max: 64, min: 8 });
  const date = new Date(text);
  if (Number.isNaN(date.getTime())) {
    throw new HttpError(400, `${field} must be a valid ISO datetime`, 'invalid_payload');
  }
  return date;
}

function parseDurationMinutes(value) {
  const parsed = Number(value ?? 60);
  if (!Number.isInteger(parsed) || parsed < 15 || parsed > 240 || parsed % 15 !== 0) {
    throw new HttpError(
      400,
      'durationMinutes must be an integer between 15 and 240 in 15-minute increments',
      'invalid_payload',
    );
  }
  return parsed;
}

function parseClient(client) {
  if (!client || typeof client !== 'object') {
    throw new HttpError(400, 'client is required', 'invalid_payload');
  }

  const phone = boundedString(client.phoneNumber ?? client.phone_number ?? '', 'client.phoneNumber', {
    min: 7,
    max: 20,
  });
  if (!/^[+0-9()\-.\s]+$/.test(phone)) {
    throw new HttpError(400, 'client.phoneNumber format is invalid', 'invalid_payload');
  }

  return {
    name: boundedString(client.name ?? '', 'client.name', { min: 1, max: 120 }),
    phoneNumber: phone,
    email: optionalString(client.email, 'client.email', { max: 200 }),
  };
}

function normalizeBodySize(body) {
  const raw = JSON.stringify(body ?? {});
  if (raw.length > MAX_BODY_BYTES) {
    throw new HttpError(413, 'payload too large', 'payload_too_large');
  }
}

export function sanitizeAgentPayload(body) {
  if (!body || typeof body !== 'object' || Array.isArray(body)) {
    throw new HttpError(400, 'request body must be a JSON object', 'invalid_payload');
  }

  normalizeBodySize(body);

  const action = boundedString(body.action ?? '', 'action', { min: 3, max: 10 }).toLowerCase();
  if (!ALLOWED_ACTIONS.has(action)) {
    throw new HttpError(400, 'action must be one of book, cancel, modify', 'invalid_payload');
  }

  const base = {
    action,
    agentRequestId: optionalString(body.agentRequestId, 'agentRequestId', { max: 120 }),
    auditTier: boundedString(body.auditTier ?? 'tier2', 'auditTier', { min: 4, max: 20 }),
    confirmationWebhookUrl: optionalString(body.confirmationWebhookUrl, 'confirmationWebhookUrl', {
      max: 500,
    }),
    notes: optionalString(body.notes, 'notes', { max: 500 }),
  };

  if (action === 'book') {
    const requestedStart = parseIsoDate(body.requestedTime ?? body.requestedStart, 'requestedTime');
    const durationMinutes = parseDurationMinutes(body.durationMinutes);
    return {
      ...base,
      client: parseClient(body.client),
      requestedStart,
      durationMinutes,
    };
  }

  if (action === 'cancel') {
    return {
      ...base,
      appointmentId: boundedString(body.appointmentId ?? '', 'appointmentId', { min: 8, max: 60 }),
      reason: optionalString(body.reason, 'reason', { max: 300 }),
    };
  }

  return {
    ...base,
    appointmentId: boundedString(body.appointmentId ?? '', 'appointmentId', { min: 8, max: 60 }),
    requestedStart: parseIsoDate(body.requestedTime ?? body.requestedStart, 'requestedTime'),
    durationMinutes: parseDurationMinutes(body.durationMinutes),
  };
}
