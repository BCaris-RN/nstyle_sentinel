-- NStyle Sentinel core PostgreSQL schema (Supabase/Postgres compatible)
-- Focus: dual-handshake bookings, conflict prevention, optimistic locking,
-- and keyset-friendly calendar reads.

create extension if not exists pgcrypto;
create extension if not exists btree_gist;

do $$
begin
  if not exists (
    select 1 from pg_type where typname = 'appointment_status'
  ) then
    create type appointment_status as enum (
      'pending_approval',
      'confirmed',
      'cancelled',
      'rejected',
      'expired'
    );
  end if;
end
$$;

create or replace function set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

create table if not exists clients (
  id uuid primary key default gen_random_uuid(),
  phone_number varchar(20) not null unique,
  name varchar(120) not null,
  email text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

drop trigger if exists trg_clients_updated_at on clients;
create trigger trg_clients_updated_at
before update on clients
for each row
execute function set_updated_at();

create table if not exists availability_overrides (
  id uuid primary key default gen_random_uuid(),
  override_date date not null,
  is_blocked boolean not null default false,
  custom_start_time time,
  custom_end_time time,
  note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint availability_override_time_window_chk
    check (
      (is_blocked = true and custom_start_time is null and custom_end_time is null)
      or
      (is_blocked = false and custom_start_time is not null and custom_end_time is not null and custom_end_time > custom_start_time)
    )
);

create index if not exists idx_availability_overrides_date
  on availability_overrides (override_date, id);

drop trigger if exists trg_availability_overrides_updated_at on availability_overrides;
create trigger trg_availability_overrides_updated_at
before update on availability_overrides
for each row
execute function set_updated_at();

create table if not exists appointments (
  id uuid primary key default gen_random_uuid(),
  client_id uuid not null references clients(id) on delete restrict,
  start_time timestamptz not null,
  end_time timestamptz not null,
  status appointment_status not null default 'pending_approval',
  pending_action text,
  pending_payload jsonb,
  requested_by_channel text not null default 'ai_agent',
  agent_request_id text unique,
  audit_tier text not null default 'tier2',
  approval_requested_at timestamptz,
  approved_at timestamptz,
  cancelled_at timestamptz,
  confirmed_by text,
  confirmation_webhook_url text,
  external_reference text,
  notes text,
  version integer not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  slot_range tstzrange generated always as (tstzrange(start_time, end_time, '[)')) stored,
  constraint appointments_time_window_chk check (end_time > start_time),
  constraint appointments_version_positive_chk check (version > 0),
  constraint appointments_pending_action_chk check (
    pending_action is null or pending_action in ('book', 'modify', 'cancel')
  )
);

-- Prevent overlapping active slots (pending + confirmed) at the database layer.
do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'appointments_no_overlap_active_slots'
  ) then
    alter table appointments
      add constraint appointments_no_overlap_active_slots
      exclude using gist (slot_range with &&)
      where (status in ('pending_approval', 'confirmed'));
  end if;
end
$$;

create index if not exists idx_appointments_keyset
  on appointments (start_time, id);

create index if not exists idx_appointments_status_start
  on appointments (status, start_time, id);

create index if not exists idx_appointments_client_start
  on appointments (client_id, start_time desc, id desc);

drop trigger if exists trg_appointments_updated_at on appointments;
create trigger trg_appointments_updated_at
before update on appointments
for each row
execute function set_updated_at();

comment on table appointments is
  'AI agent requests become pending_approval and require Toney manual approval before final state.';

comment on column appointments.version is
  'Optimistic locking column. Update with WHERE id = ? AND version = ? and SET version = version + 1.';

-- Example optimistic lock confirmation query:
-- update appointments
-- set status = 'confirmed',
--     approved_at = now(),
--     confirmed_by = 'toney',
--     version = version + 1
-- where id = $1
--   and version = $2
--   and status = 'pending_approval';

-- Example keyset pagination query (12-month calendar hydration):
-- select *
-- from appointments
-- where start_time >= $1
--   and ($2::timestamptz is null or (start_time, id) > ($2, $3::uuid))
-- order by start_time, id
-- limit $4;
