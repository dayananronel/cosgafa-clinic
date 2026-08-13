-- Phase 2 schema. Mirrors lib/models/*.dart and spec section 9 exactly —
-- see docs/PHASE_2_BACKEND_SCOPE.md §3 for the rationale behind every
-- table and constraint here. Apply in order (0001, 0002, ...) via the
-- Supabase SQL Editor or `supabase db push`.

create extension if not exists "pgcrypto";

create type user_role as enum ('ADMIN', 'SECRETARY', 'DOCTOR');
create type sex as enum ('MALE', 'FEMALE');
create type visit_status as enum ('OPEN', 'IN_CONSULTATION', 'COMPLETED', 'CANCELLED');
create type queue_status as enum (
  'CHECKED_IN', 'WAITING_FOR_INTAKE', 'IN_INTAKE', 'VITALS_COMPLETE',
  'NEEDS_DOCTOR_DECISION', 'WAITING_FOR_DOCTOR', 'CALLED',
  'IN_CONSULTATION', 'COMPLETED', 'SKIPPED', 'NO_SHOW', 'CANCELLED',
  'TEMPORARILY_AWAY'
);
create type queue_event_type as enum (
  'CHECK_IN', 'INTAKE_STARTED', 'PATIENT_REGISTERED', 'VISIT_CREATED',
  'VITALS_RECORDED', 'QUEUE_CREATED', 'PRIORITY_CHANGED',
  'DOCTOR_OVERRIDE', 'CALLED', 'SKIPPED', 'REQUEUED',
  'CONSULTATION_STARTED', 'COMPLETED', 'CANCELLED',
  'TEMPORARILY_AWAY', 'RETURNED', 'NEEDS_DOCTOR_DECISION'
);

-- Staff accounts. Supabase Auth (auth.users) owns credentials; this
-- table holds the clinic-specific profile + role RLS policies key off.
create table staff_profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  name text not null,
  role user_role not null,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table patients (
  id uuid primary key default gen_random_uuid(),
  patient_number text not null unique,
  first_name text not null,
  middle_name text not null default '',
  last_name text not null,
  birthdate date not null,
  sex sex not null,
  address text not null,
  guardian_name text not null,
  guardian_contact text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid references staff_profiles(id),
  updated_by uuid references staff_profiles(id)
);
create index patients_name_idx on patients (lower(last_name), lower(first_name));
create index patients_number_idx on patients (patient_number);

create table visits (
  id uuid primary key default gen_random_uuid(),
  patient_id uuid not null references patients(id),
  visit_date date not null default current_date,
  reason_for_visit text not null,
  status visit_status not null default 'OPEN',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid references staff_profiles(id),
  updated_by uuid references staff_profiles(id)
);
create index visits_patient_idx on visits (patient_id);
-- Enforces spec 13 "Duplicate visit": one OPEN visit per patient per day.
create unique index visits_one_open_per_patient_per_day
  on visits (patient_id, visit_date) where status = 'OPEN';

create table priority_categories (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  priority_level int not null,
  description text not null default '',
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table queue_entries (
  id uuid primary key default gen_random_uuid(),
  visit_id uuid not null unique references visits(id),
  queue_number int not null,
  checked_in_at timestamptz not null default now(),
  priority_category_id uuid not null references priority_categories(id),
  priority_level int not null,
  status queue_status not null default 'WAITING_FOR_INTAKE',
  called_at timestamptz,
  consultation_started_at timestamptz,
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index queue_entries_status_idx on queue_entries (status);
create index queue_entries_ordering_idx on queue_entries (priority_level, checked_in_at);

-- Postgres won't allow timestamptz::date directly in an index because the
-- built-in cast is timezone-session-dependent (STABLE, not IMMUTABLE).
-- This wrapper pins the conversion to UTC, which is deterministic, so it
-- can safely be declared IMMUTABLE for indexing purposes.
create or replace function clinic_day(ts timestamptz)
returns date
language sql
immutable
as $$
  select (ts at time zone 'utc')::date;
$$;

-- Queue numbers reset daily (ClinicPolicy.queueNumberResetsDaily) and must
-- be unique within a day, not globally.
create unique index queue_number_per_day
  on queue_entries (queue_number, clinic_day(checked_in_at));

-- Atomic per-day queue-number counter (spec 6 Step 2, 7.2). A plain
-- "select max(queue_number)+1" races under concurrent check-ins; this
-- table + upsert gives a single atomic increment instead.
create table daily_queue_counters (
  counter_date date primary key,
  next_number int not null default 1
);

create table vitals (
  id uuid primary key default gen_random_uuid(),
  visit_id uuid not null references visits(id),
  weight_kg numeric(5,2),
  temperature_c numeric(4,1),
  height_cm numeric(5,1),
  oxygen_saturation numeric(4,1),
  recorded_at timestamptz not null default now(),
  recorded_by uuid references staff_profiles(id)
);
create index vitals_visit_idx on vitals (visit_id);

-- Append-only audit trail (spec 9.7, section 17).
create table queue_events (
  id uuid primary key default gen_random_uuid(),
  queue_entry_id uuid references queue_entries(id),
  event_type queue_event_type not null,
  old_status queue_status,
  new_status queue_status,
  old_priority text,
  new_priority text,
  reason text,
  performed_by uuid references staff_profiles(id),
  created_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb
);
create index queue_events_entry_idx on queue_events (queue_entry_id);
create index queue_events_created_idx on queue_events (created_at desc);

-- ASSUMPTION (spec 7.5 / Step 8): example administrative categories
-- only, matching seed_data.dart. CONFIRMATION REQUIRED — the clinic must
-- confirm its actual category names and count.
insert into priority_categories (id, name, priority_level, description) values
  ('00000000-0000-0000-0000-000000000001', 'Doctor Priority', 1, 'Reserved for doctor-authorized overrides only.'),
  ('00000000-0000-0000-0000-000000000002', 'Special Assistance', 2, 'Children requiring special assistance.'),
  ('00000000-0000-0000-0000-000000000003', 'Follow-up / Newborn', 3, 'Follow-up visits and newborns.'),
  ('00000000-0000-0000-0000-000000000004', 'Normal', 4, 'Standard walk-in visit.');
