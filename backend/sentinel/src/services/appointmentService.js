import pRetry from 'p-retry';

import { HttpError } from '../errors/httpError.js';

function addMinutes(date, minutes) {
  return new Date(date.getTime() + minutes * 60_000);
}

function overlapRangeQuery(excludeAppointmentId = false) {
  return `
    select id, start_time, end_time, status
    from appointments
    where status in ('pending_approval', 'confirmed')
      and tstzrange(start_time, end_time, '[)') && tstzrange($1, $2, '[)')
      ${excludeAppointmentId ? 'and id <> $3' : ''}
    order by start_time asc
    limit 1
  `;
}

function json(value) {
  return value == null ? null : JSON.stringify(value);
}

function pgDate(value) {
  return value instanceof Date ? value.toISOString() : value;
}

export class AppointmentService {
  constructor({ db, availabilityService, pushGateway, webhookClient }) {
    this.db = db;
    this.availabilityService = availabilityService;
    this.pushGateway = pushGateway;
    this.webhookClient = webhookClient;
  }

  async handleAgentAction(payload) {
    switch (payload.action) {
      case 'book':
        return this.handleBook(payload);
      case 'cancel':
        return this.handleCancel(payload);
      case 'modify':
        return this.handleModify(payload);
      default:
        throw new HttpError(400, 'Unsupported action', 'invalid_action');
    }
  }

  async handleBook(payload) {
    const start = payload.requestedStart;
    const end = addMinutes(start, payload.durationMinutes);

    const conflict = await this.findConflict({ start, end });
    if (conflict) {
      return this.buildConflictResponse(payload, start, payload.durationMinutes);
    }

    try {
      const result = await this.db.withTransaction(async (client) => {
        const clientId = await this.upsertClient(client, payload.client);
        const insertResult = await client.query(
          `
            insert into appointments (
              client_id, start_time, end_time, status, pending_action, pending_payload,
              requested_by_channel, agent_request_id, audit_tier, approval_requested_at,
              confirmation_webhook_url, notes
            )
            values ($1, $2, $3, 'pending_approval', 'book', $4::jsonb, 'ai_agent', $5, $6, now(), $7, $8)
            returning id, client_id, start_time, end_time, status, pending_action, version, created_at
          `,
          [
            clientId,
            pgDate(start),
            pgDate(end),
            json({
              requestedBy: 'ai_agent',
              durationMinutes: payload.durationMinutes,
              clientPhoneNumber: payload.client.phoneNumber,
            }),
            payload.agentRequestId ?? null,
            payload.auditTier,
            payload.confirmationWebhookUrl ?? null,
            payload.notes ?? null,
          ],
        );

        return insertResult.rows[0];
      });

      await this.pushGateway.sendPendingApproval({
        appointmentId: result.id,
        action: 'book',
        startTime: new Date(result.start_time),
        endTime: new Date(result.end_time),
      });

      return {
        status: 'pending_toney_approval',
        action: 'book',
        appointmentId: result.id,
        version: result.version,
        startTime: result.start_time,
        endTime: result.end_time,
      };
    } catch (error) {
      if (error?.code === '23P01') {
        return this.buildConflictResponse(payload, start, payload.durationMinutes);
      }
      throw error;
    }
  }

  async handleCancel(payload) {
    const updated = await this.db.withTransaction(async (client) => {
      const existing = await this.getAppointmentForUpdate(client, payload.appointmentId);
      if (existing.status === 'cancelled') {
        return { outcome: 'already_cancelled', row: existing };
      }

      const nextVersion = Number(existing.version) + 1;
      const pendingPayload = {
        ...(existing.pending_payload ?? {}),
        type: 'cancel',
        requestedReason: payload.reason ?? payload.notes ?? null,
        previousStatus: existing.status,
      };

      const result = await client.query(
        `
          update appointments
          set status = 'pending_approval',
              pending_action = 'cancel',
              pending_payload = $2::jsonb,
              approval_requested_at = now(),
              notes = coalesce($3, notes),
              agent_request_id = coalesce($4, agent_request_id),
              audit_tier = $5,
              confirmation_webhook_url = coalesce($6, confirmation_webhook_url),
              version = $7
          where id = $1
          returning id, start_time, end_time, status, pending_action, version
        `,
        [
          payload.appointmentId,
          json(pendingPayload),
          payload.notes ?? null,
          payload.agentRequestId ?? null,
          payload.auditTier,
          payload.confirmationWebhookUrl ?? null,
          nextVersion,
        ],
      );

      return { outcome: 'pending', row: result.rows[0] };
    });

    if (updated.outcome === 'already_cancelled') {
      return {
        status: 'already_cancelled',
        appointmentId: updated.row.id,
      };
    }

    await this.pushGateway.sendPendingApproval({
      appointmentId: updated.row.id,
      action: 'cancel',
      startTime: new Date(updated.row.start_time),
      endTime: new Date(updated.row.end_time),
    });

    return {
      status: 'pending_toney_approval',
      action: 'cancel',
      appointmentId: updated.row.id,
      version: updated.row.version,
    };
  }

  async handleModify(payload) {
    const start = payload.requestedStart;
    const end = addMinutes(start, payload.durationMinutes);

    const conflict = await this.findConflict({
      start,
      end,
      excludeAppointmentId: payload.appointmentId,
    });
    if (conflict) {
      return this.buildConflictResponse(payload, start, payload.durationMinutes, payload.appointmentId);
    }

    try {
      const updated = await this.db.withTransaction(async (client) => {
        const existing = await this.getAppointmentForUpdate(client, payload.appointmentId);
        if (existing.status === 'cancelled') {
          throw new HttpError(409, 'Cannot modify a cancelled appointment', 'invalid_state');
        }

        const nextVersion = Number(existing.version) + 1;
        const pendingPayload = {
          ...(existing.pending_payload ?? {}),
          type: 'modify',
          previousStartTime: existing.start_time,
          previousEndTime: existing.end_time,
          previousStatus: existing.status,
          requestedDurationMinutes: payload.durationMinutes,
        };

        const result = await client.query(
          `
            update appointments
            set start_time = $2,
                end_time = $3,
                status = 'pending_approval',
                pending_action = 'modify',
                pending_payload = $4::jsonb,
                approval_requested_at = now(),
                agent_request_id = coalesce($5, agent_request_id),
                audit_tier = $6,
                confirmation_webhook_url = coalesce($7, confirmation_webhook_url),
                notes = coalesce($8, notes),
                version = $9
            where id = $1
            returning id, start_time, end_time, status, pending_action, version
          `,
          [
            payload.appointmentId,
            pgDate(start),
            pgDate(end),
            json(pendingPayload),
            payload.agentRequestId ?? null,
            payload.auditTier,
            payload.confirmationWebhookUrl ?? null,
            payload.notes ?? null,
            nextVersion,
          ],
        );

        return result.rows[0];
      });

      await this.pushGateway.sendPendingApproval({
        appointmentId: updated.id,
        action: 'modify',
        startTime: new Date(updated.start_time),
        endTime: new Date(updated.end_time),
      });

      return {
        status: 'pending_toney_approval',
        action: 'modify',
        appointmentId: updated.id,
        version: updated.version,
        startTime: updated.start_time,
        endTime: updated.end_time,
      };
    } catch (error) {
      if (error?.code === '23P01') {
        return this.buildConflictResponse(payload, start, payload.durationMinutes, payload.appointmentId);
      }
      throw error;
    }
  }

  async confirmPendingAppointment({ appointmentId, expectedVersion, approved, reviewedBy = 'toney' }) {
    let webhookWork;

    const updated = await this.db.withTransaction(async (client) => {
      const existing = await this.getAppointmentForUpdate(client, appointmentId);
      if (existing.status !== 'pending_approval' || !existing.pending_action) {
        throw new HttpError(409, 'Appointment is not awaiting approval', 'invalid_state');
      }

      const nextState = this.resolveApprovalTransition(existing, approved);
      const updateResult = await client.query(
        `
          update appointments
          set status = $3,
              pending_action = null,
              pending_payload = null,
              approved_at = case when $4 then now() else approved_at end,
              cancelled_at = case when $3 = 'cancelled' then now() else cancelled_at end,
              confirmed_by = $5,
              version = version + 1
          where id = $1
            and version = $2
          returning id, client_id, start_time, end_time, status, version, confirmation_webhook_url
        `,
        [appointmentId, expectedVersion, nextState.status, approved, reviewedBy],
      );

      if (updateResult.rowCount !== 1) {
        throw new HttpError(409, 'Approval version conflict', 'optimistic_lock_conflict');
      }

      const row = updateResult.rows[0];
      webhookWork = {
        url: row.confirmation_webhook_url,
        payload: {
          appointmentId: row.id,
          status: row.status,
          approved,
          reviewedBy,
          startTime: row.start_time,
          endTime: row.end_time,
          version: row.version,
        },
      };
      return row;
    });

    let webhookDelivered = false;
    if (webhookWork?.url) {
      try {
        await pRetry(
          async () => {
            await this.webhookClient.postConfirmation({
              url: webhookWork.url,
              payload: webhookWork.payload,
              headers: {
                'x-sentinel-source': 'nstyle-sentinel',
              },
            });
          },
          { retries: 2 },
        );
        webhookDelivered = true;
      } catch (error) {
        // eslint-disable-next-line no-console
        console.error('[Sentinel] Confirmation webhook failed:', error.message);
      }
    }

    return {
      status: 'approval_resolved',
      appointmentId: updated.id,
      appointmentStatus: updated.status,
      version: updated.version,
      webhookDelivered,
    };
  }

  async findConflict({ start, end, excludeAppointmentId }) {
    return pRetry(
      async () => {
        const params = excludeAppointmentId ? [pgDate(start), pgDate(end), excludeAppointmentId] : [pgDate(start), pgDate(end)];
        const result = await this.db.query(overlapRangeQuery(Boolean(excludeAppointmentId)), params);
        return result.rows[0] ?? null;
      },
      { retries: 2 },
    );
  }

  async buildConflictResponse(payload, requestedStart, durationMinutes, excludeAppointmentId) {
    const nextAvailable = await this.availabilityService.getNextAvailable({
      requestedStart,
      durationMinutes,
      excludeAppointmentId,
    });

    return {
      status: 'conflict',
      action: payload.action,
      requestedTime: requestedStart.toISOString(),
      proposedTime: nextAvailable?.toISOString?.() ?? null,
    };
  }

  async upsertClient(client, person) {
    const result = await client.query(
      `
        insert into clients (phone_number, name, email)
        values ($1, $2, $3)
        on conflict (phone_number)
        do update set
          name = excluded.name,
          email = coalesce(excluded.email, clients.email),
          updated_at = now()
        returning id
      `,
      [person.phoneNumber, person.name, person.email ?? null],
    );
    return result.rows[0].id;
  }

  async getAppointmentForUpdate(client, appointmentId) {
    const result = await client.query(
      `
        select id, start_time, end_time, status, version, pending_action, pending_payload,
               confirmation_webhook_url
        from appointments
        where id = $1
        for update
      `,
      [appointmentId],
    );

    if (result.rowCount !== 1) {
      throw new HttpError(404, 'Appointment not found', 'not_found');
    }
    return result.rows[0];
  }

  resolveApprovalTransition(existing, approved) {
    if (approved) {
      return {
        status: existing.pending_action === 'cancel' ? 'cancelled' : 'confirmed',
      };
    }

    if (existing.pending_action === 'book') {
      return { status: 'rejected' };
    }
    return { status: 'confirmed' };
  }
}
