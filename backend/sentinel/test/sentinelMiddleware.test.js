import crypto from 'node:crypto';

import { beforeAll, beforeEach, describe, expect, it, jest } from '@jest/globals';

import { createSentinelHandlers } from '../src/middleware/sentinelMiddleware.js';
import { AppointmentService } from '../src/services/appointmentService.js';

function createMockRes() {
  return {
    status: jest.fn().mockReturnThis(),
    json: jest.fn().mockReturnThis(),
  };
}

function baseBookBody(overrides = {}) {
  return {
    action: 'book',
    auditTier: 'tier2',
    agentRequestId: 'req-123',
    client: {
      name: 'Jordan',
      phoneNumber: '+15551234567',
    },
    requestedTime: '2026-03-01T13:00:00.000Z',
    durationMinutes: 60,
    ...overrides,
  };
}

function signReq({ body, method = 'POST', url = '/sentinel/agent', tier = 'tier2', secret }) {
  const timestampMs = Date.now();
  const rawBody = JSON.stringify(body);
  const canonical = [method, url, String(timestampMs), tier, rawBody].join('\n');
  const signature = crypto.createHmac('sha256', secret).update(canonical).digest('hex');

  return {
    method,
    url,
    originalUrl: url,
    rawBody,
    headers: {
      'x-sentinel-timestamp': String(timestampMs),
      'x-sentinel-signature': signature,
      'x-audit-tier': tier,
    },
    body,
  };
}

describe('NStyle Sentinel middleware boundary (horror paths + integrity)', () => {
  beforeAll(() => {
    process.env.NSTYLE_AGENT_TOKEN_TIER2 = 'test-tier2-secret';
  });

  beforeEach(() => {
    jest.clearAllMocks();
  });

  it('rejects invalid tiered audit-route signatures', async () => {
    const mockAppointmentService = {
      handleAgentAction: jest.fn(),
      confirmPendingAppointment: jest.fn(),
    };
    const handlers = createSentinelHandlers({ appointmentService: mockAppointmentService });
    const body = baseBookBody();
    const req = signReq({
      body,
      secret: process.env.NSTYLE_AGENT_TOKEN_TIER2,
    });
    req.headers['x-sentinel-signature'] = 'deadbeef';
    const res = createMockRes();

    await handlers.sentinel(req, res);

    expect(mockAppointmentService.handleAgentAction).not.toHaveBeenCalled();
    expect(res.status).toHaveBeenCalledWith(403);
    expect(res.json).toHaveBeenCalledWith(
      expect.objectContaining({
        error: 'Unauthorized AI Agent request',
      }),
    );
  });

  it('rejects poisoned oversized payloads with safe client error', async () => {
    const mockAppointmentService = {
      handleAgentAction: jest.fn(),
      confirmPendingAppointment: jest.fn(),
    };
    const handlers = createSentinelHandlers({ appointmentService: mockAppointmentService });
    const body = baseBookBody({
      notes: 'x'.repeat(9_500),
    });
    const req = signReq({
      body,
      secret: process.env.NSTYLE_AGENT_TOKEN_TIER2,
    });
    const res = createMockRes();

    await handlers.sentinel(req, res);

    expect(mockAppointmentService.handleAgentAction).not.toHaveBeenCalled();
    expect(res.status).toHaveBeenCalledWith(413);
    expect(res.json).toHaveBeenCalledWith(
      expect.objectContaining({
        code: 'payload_too_large',
      }),
    );
  });

  it('returns a conflict proposal when service detects a race-condition slot collision', async () => {
    const mockAppointmentService = {
      handleAgentAction: jest.fn().mockResolvedValue({
        status: 'conflict',
        action: 'book',
        requestedTime: '2026-03-01T13:00:00.000Z',
        proposedTime: '2026-03-02T09:30:00.000Z',
      }),
      confirmPendingAppointment: jest.fn(),
    };
    const handlers = createSentinelHandlers({ appointmentService: mockAppointmentService });
    const req = signReq({
      body: baseBookBody(),
      secret: process.env.NSTYLE_AGENT_TOKEN_TIER2,
    });
    const res = createMockRes();

    await handlers.sentinel(req, res);

    expect(mockAppointmentService.handleAgentAction).toHaveBeenCalledTimes(1);
    expect(res.status).toHaveBeenCalledWith(200);
    expect(res.json).toHaveBeenCalledWith(
      expect.objectContaining({
        status: 'conflict',
        proposedTime: '2026-03-02T09:30:00.000Z',
      }),
    );
  });

  it('returns safe 500 response on upstream collapse without exposing stack traces', async () => {
    const mockAppointmentService = {
      handleAgentAction: jest
        .fn()
        .mockRejectedValue(new Error('FATAL: connection to database "supabase" failed')),
      confirmPendingAppointment: jest.fn(),
    };
    const handlers = createSentinelHandlers({ appointmentService: mockAppointmentService });
    const req = signReq({
      body: baseBookBody(),
      secret: process.env.NSTYLE_AGENT_TOKEN_TIER2,
    });
    const res = createMockRes();

    await handlers.sentinel(req, res);

    expect(res.status).toHaveBeenCalledWith(500);
    expect(res.json).toHaveBeenCalledWith({
      error: 'System fault. Active recovery initiated.',
      code: 'sentinel_fault',
    });
  });

  it('parses string boolean approval flags correctly for the Toney approval route', async () => {
    const mockAppointmentService = {
      handleAgentAction: jest.fn(),
      confirmPendingAppointment: jest.fn().mockResolvedValue({
        status: 'approval_resolved',
        appointmentId: 'appt-1',
        appointmentStatus: 'confirmed',
        version: 4,
        webhookDelivered: false,
      }),
    };
    const handlers = createSentinelHandlers({ appointmentService: mockAppointmentService });
    const res = createMockRes();

    await handlers.approve(
      {
        body: {
          appointmentId: 'appt-1',
          expectedVersion: 3,
          approved: 'false',
          reviewedBy: 'toney',
        },
      },
      res,
    );

    expect(mockAppointmentService.confirmPendingAppointment).toHaveBeenCalledWith(
      expect.objectContaining({
        appointmentId: 'appt-1',
        expectedVersion: 3,
        approved: false,
      }),
    );
    expect(res.status).toHaveBeenCalledWith(200);
  });
});

describe('AppointmentService conflict + retry behavior', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  it('triggers look-ahead availability query when a slot is already taken', async () => {
    const db = {
      query: jest.fn().mockResolvedValue({
        rows: [
          {
            id: 'existing-appt',
            start_time: '2026-03-01T13:00:00.000Z',
            end_time: '2026-03-01T14:00:00.000Z',
            status: 'confirmed',
          },
        ],
      }),
      withTransaction: jest.fn(),
    };
    const availabilityService = {
      getNextAvailable: jest.fn().mockResolvedValue(new Date('2026-03-02T09:30:00.000Z')),
    };
    const service = new AppointmentService({
      db,
      availabilityService,
      pushGateway: { sendPendingApproval: jest.fn() },
      webhookClient: { postConfirmation: jest.fn() },
    });

    const result = await service.handleBook({
      action: 'book',
      auditTier: 'tier2',
      client: { name: 'Jordan', phoneNumber: '+15551234567' },
      requestedStart: new Date('2026-03-01T13:00:00.000Z'),
      durationMinutes: 60,
    });

    expect(db.query).toHaveBeenCalledTimes(1);
    expect(availabilityService.getNextAvailable).toHaveBeenCalledTimes(1);
    expect(result).toMatchObject({
      status: 'conflict',
      action: 'book',
      requestedTime: '2026-03-01T13:00:00.000Z',
      proposedTime: '2026-03-02T09:30:00.000Z',
    });
  });

  it('retries transient database failures before surfacing the error', async () => {
    const db = {
      query: jest.fn().mockRejectedValue(new Error('timeout')),
      withTransaction: jest.fn(),
    };
    const service = new AppointmentService({
      db,
      availabilityService: { getNextAvailable: jest.fn() },
      pushGateway: { sendPendingApproval: jest.fn() },
      webhookClient: { postConfirmation: jest.fn() },
    });

    await expect(
      service.handleBook({
        action: 'book',
        auditTier: 'tier2',
        client: { name: 'Jordan', phoneNumber: '+15551234567' },
        requestedStart: new Date('2026-03-01T13:00:00.000Z'),
        durationMinutes: 60,
      }),
    ).rejects.toThrow('timeout');

    // p-retry with retries: 2 -> 3 total attempts.
    expect(db.query).toHaveBeenCalledTimes(3);
  });
});
