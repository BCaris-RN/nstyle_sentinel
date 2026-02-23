import { query, withTransaction } from '../infrastructure/db.js';
import { pushGateway } from '../infrastructure/pushGateway.js';
import { webhookClient } from '../infrastructure/webhookClient.js';
import { HttpError, isHttpError } from '../errors/httpError.js';
import { verifyTieredAuditRouteSignature } from '../security/agentSignature.js';
import { AvailabilityService } from '../services/availabilityService.js';
import { AppointmentService } from '../services/appointmentService.js';
import { sanitizeAgentPayload } from '../services/payloadSanitizer.js';

const db = { query, withTransaction };
const availabilityService = new AvailabilityService(db);
const appointmentService = new AppointmentService({
  db,
  availabilityService,
  pushGateway,
  webhookClient,
});

function parseApprovedFlag(value) {
  if (typeof value === 'boolean') return value;
  if (typeof value === 'string') {
    const normalized = value.trim().toLowerCase();
    if (normalized == 'true') return true;
    if (normalized == 'false') return false;
  }
  throw new HttpError(400, 'approved must be a boolean', 'invalid_payload');
}

function sendError(res, error) {
  if (isHttpError(error)) {
    return res.status(error.statusCode).json({
      error: error.message,
      code: error.code,
    });
  }

  // eslint-disable-next-line no-console
  console.error('[Sentinel Fault]', error.message);
  return res.status(500).json({
    error: 'System fault. Active recovery initiated.',
    code: 'sentinel_fault',
  });
}

export async function sentinelMiddleware(req, res) {
  try {
    const verification = verifyTieredAuditRouteSignature(req);
    if (!verification.ok) {
      throw new HttpError(403, 'Unauthorized AI Agent request', verification.reason ?? 'invalid_signature');
    }

    const payload = sanitizeAgentPayload(req.body);
    if (payload.auditTier !== verification.auditTier) {
      throw new HttpError(403, 'Audit tier mismatch', 'audit_tier_mismatch');
    }

    const result = await appointmentService.handleAgentAction(payload);
    const httpStatus = result.status === 'pending_toney_approval' ? 202 : 200;
    return res.status(httpStatus).json(result);
  } catch (error) {
    return sendError(res, error);
  }
}

export async function toneyApprovalMiddleware(req, res) {
  try {
    const appointmentId = String(req.body?.appointmentId ?? '').trim();
    const expectedVersion = Number(req.body?.expectedVersion);
    const approved = parseApprovedFlag(req.body?.approved);
    const reviewedBy = String(req.body?.reviewedBy ?? 'toney').slice(0, 120);

    if (!appointmentId) {
      throw new HttpError(400, 'appointmentId is required', 'invalid_payload');
    }
    if (!Number.isInteger(expectedVersion) || expectedVersion < 1) {
      throw new HttpError(400, 'expectedVersion must be a positive integer', 'invalid_payload');
    }

    const result = await appointmentService.confirmPendingAppointment({
      appointmentId,
      expectedVersion,
      approved,
      reviewedBy,
    });

    return res.status(200).json(result);
  } catch (error) {
    return sendError(res, error);
  }
}

export function createSentinelHandlers(overrides = {}) {
  const availability = overrides.availabilityService ?? availabilityService;
  const appointments =
    overrides.appointmentService ??
    new AppointmentService({
      db: overrides.db ?? db,
      availabilityService: availability,
      pushGateway: overrides.pushGateway ?? pushGateway,
      webhookClient: overrides.webhookClient ?? webhookClient,
    });

  return {
    async sentinel(req, res) {
      try {
        const verification = verifyTieredAuditRouteSignature(req);
        if (!verification.ok) {
          throw new HttpError(403, 'Unauthorized AI Agent request', verification.reason ?? 'invalid_signature');
        }
        const payload = sanitizeAgentPayload(req.body);
        if (payload.auditTier !== verification.auditTier) {
          throw new HttpError(403, 'Audit tier mismatch', 'audit_tier_mismatch');
        }
        const result = await appointments.handleAgentAction(payload);
        return res.status(result.status === 'pending_toney_approval' ? 202 : 200).json(result);
      } catch (error) {
        return sendError(res, error);
      }
    },
    async approve(req, res) {
      try {
        const result = await appointments.confirmPendingAppointment({
          appointmentId: String(req.body?.appointmentId ?? '').trim(),
          expectedVersion: Number(req.body?.expectedVersion),
          approved: parseApprovedFlag(req.body?.approved),
          reviewedBy: String(req.body?.reviewedBy ?? 'toney').slice(0, 120),
        });
        return res.status(200).json(result);
      } catch (error) {
        return sendError(res, error);
      }
    },
  };
}
