const DEFAULT_SLOT_MINUTES = Number(process.env.NSTYLE_SLOT_MINUTES ?? 30);
const DEFAULT_HORIZON_DAYS = Number(process.env.NSTYLE_LOOKAHEAD_DAYS ?? 30);
const DEFAULT_START_HOUR = Number(process.env.NSTYLE_OPEN_HOUR ?? 9);
const DEFAULT_START_MINUTE = Number(process.env.NSTYLE_OPEN_MINUTE ?? 30);
const DEFAULT_END_HOUR = Number(process.env.NSTYLE_CLOSE_HOUR ?? 18);
const DEFAULT_END_MINUTE = Number(process.env.NSTYLE_CLOSE_MINUTE ?? 0);

function addMinutes(date, minutes) {
  return new Date(date.getTime() + minutes * 60_000);
}

function startOfDay(date) {
  return new Date(date.getFullYear(), date.getMonth(), date.getDate());
}

function endOfDay(date) {
  return new Date(date.getFullYear(), date.getMonth(), date.getDate(), 23, 59, 59, 999);
}

function dayKey(date) {
  const y = date.getFullYear();
  const m = String(date.getMonth() + 1).padStart(2, '0');
  const d = String(date.getDate()).padStart(2, '0');
  return `${y}-${m}-${d}`;
}

function roundUpToBoundary(date, slotMinutes) {
  const slotMs = slotMinutes * 60_000;
  const rounded = Math.ceil(date.getTime() / slotMs) * slotMs;
  return new Date(rounded);
}

function overlaps(aStart, aEnd, bStart, bEnd) {
  return aStart < bEnd && aEnd > bStart;
}

function toWindowForDay(day, override) {
  if (override?.is_blocked) return null;
  const start = new Date(day);
  const end = new Date(day);

  if (override?.custom_start_time && override?.custom_end_time) {
    const [sh, sm] = String(override.custom_start_time).split(':').map(Number);
    const [eh, em] = String(override.custom_end_time).split(':').map(Number);
    start.setHours(sh, sm, 0, 0);
    end.setHours(eh, em, 0, 0);
    return { start, end };
  }

  start.setHours(DEFAULT_START_HOUR, DEFAULT_START_MINUTE, 0, 0);
  end.setHours(DEFAULT_END_HOUR, DEFAULT_END_MINUTE, 0, 0);
  return { start, end };
}

export class AvailabilityService {
  constructor(db) {
    this.db = db;
  }

  async getNextAvailable({
    requestedStart,
    durationMinutes,
    excludeAppointmentId,
    horizonDays = DEFAULT_HORIZON_DAYS,
  }) {
    const horizonEnd = addMinutes(requestedStart, horizonDays * 24 * 60);
    const [busyRows, overrideRows] = await Promise.all([
      this.loadBusyAppointments(requestedStart, horizonEnd, excludeAppointmentId),
      this.loadOverrides(startOfDay(requestedStart), endOfDay(horizonEnd)),
    ]);

    return this.scanForSlot({
      requestedStart,
      durationMinutes,
      busyRows,
      overrideRows,
      horizonDays,
    });
  }

  async loadBusyAppointments(start, end, excludeAppointmentId) {
    const params = [start, end];
    let sql = `
      select id, start_time, end_time
      from appointments
      where status in ('pending_approval', 'confirmed')
        and tstzrange(start_time, end_time, '[)') && tstzrange($1, $2, '[)')
    `;

    if (excludeAppointmentId) {
      params.push(excludeAppointmentId);
      sql += ` and id <> $3 `;
    }

    sql += ' order by start_time asc';
    const result = await this.db.query(sql, params);
    return result.rows.map((row) => ({
      id: row.id,
      start: new Date(row.start_time),
      end: new Date(row.end_time),
    }));
  }

  async loadOverrides(fromDay, toDay) {
    const result = await this.db.query(
      `
        select override_date, is_blocked, custom_start_time, custom_end_time
        from availability_overrides
        where override_date between $1::date and $2::date
        order by override_date asc
      `,
      [fromDay, toDay],
    );

    const map = new Map();
    for (const row of result.rows) {
      const date = new Date(row.override_date);
      map.set(dayKey(date), row);
    }
    return map;
  }

  scanForSlot({ requestedStart, durationMinutes, busyRows, overrideRows, horizonDays }) {
    const durationMs = durationMinutes * 60_000;
    const slotMinutes = DEFAULT_SLOT_MINUTES;
    const firstDay = startOfDay(requestedStart);

    for (let offsetDays = 0; offsetDays <= horizonDays; offsetDays += 1) {
      const day = addMinutes(firstDay, offsetDays * 24 * 60);
      const override = overrideRows.get(dayKey(day));
      const window = toWindowForDay(day, override);
      if (!window) continue;

      const dayStart = offsetDays === 0 ? new Date(Math.max(window.start.getTime(), requestedStart.getTime())) : window.start;
      let cursor = roundUpToBoundary(dayStart, slotMinutes);

      while (cursor.getTime() + durationMs <= window.end.getTime()) {
        const candidateEnd = new Date(cursor.getTime() + durationMs);
        if (this.isFree(cursor, candidateEnd, busyRows)) {
          return cursor;
        }
        cursor = addMinutes(cursor, slotMinutes);
      }
    }

    return null;
  }

  isFree(start, end, busyRows) {
    for (const busy of busyRows) {
      if (busy.end <= start) continue;
      if (busy.start >= end) continue;
      if (overlaps(start, end, busy.start, busy.end)) {
        return false;
      }
    }
    return true;
  }
}
