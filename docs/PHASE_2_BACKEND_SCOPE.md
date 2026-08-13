# Phase 2 Scope: Real Database & Backend

**Status:** Planning document only — nothing in this file has been built yet.
**Predecessor:** Phase 1 prototype (this repo's `lib/services/ClinicRepository`,
an in-memory stand-in for a backend, per spec section 19).
**Goal:** Replace the in-memory repository with a real, persistent,
multi-device backend, without rewriting the screens that already work.

This scope follows the spec's own sequencing (`section 26`): Phase 1
(prototype) is done; this document is Phase 2 (data model + backend),
feeding into Phase 3 (queue engine hardening) and Phase 4 (pilot).

---

## 1. Why the current app can't be used clinically yet

`ClinicRepository` (Phase 1) intentionally has no persistence and no
network layer — every screen talks to one Dart object living in the
app's memory. That means:

- Data is lost on refresh/restart.
- A secretary's tablet and a doctor's tablet each have their own,
  disconnected queue — there is no shared "now serving."
- Login accepts any seeded account with no password.
- Nothing enforces authorization except the same process that a
  determined client could bypass (there is no network boundary yet).

Phase 2 closes exactly these four gaps and nothing else — no new
features, per spec Rule 8 ("do not over-engineer").

---

## 2. Recommended stack

| Layer | Recommendation | Why |
|---|---|---|
| Database | **PostgreSQL** | Matches the spec's normalized entity model (9.1–9.7) directly; strong support for constraints, transactions, and row-level security. |
| Backend platform | **Supabase** (hosted Postgres + Auth + Realtime + Row-Level Security) | Free tier is enough for one small clinic; gives authenticated REST/Realtime APIs over Postgres without writing and hosting a custom server; RLS lets the *database itself* enforce the spec's "server-side authorization" requirement (14, 23.2) rather than trusting app code. |
| Realtime sync | **Supabase Realtime** (Postgres logical replication → websockets) | The spec's core value prop is a *shared, live* queue (10.4–10.6) — every device must see the same "now serving" without polling. |
| Web hosting | **GitHub Pages** (already wired up via `.github/workflows/ci-deploy.yml`) | Free, already deploying the Flutter web build on every push. |
| Mobile builds | Same repo, `flutter build apk` / `flutter build ios` | No separate backend hosting needed for mobile — same Supabase project. |

### Alternative considered: fully custom backend

A hand-rolled server (e.g. Dart `shelf` or Node/Express) plus a hosted
Postgres (Neon/Railway free tier) gives more control over business
logic placement, at the cost of building and maintaining auth,
authorization, migrations, and realtime sync by hand — all of which
Supabase provides out of the box. **Recommendation: start with
Supabase; revisit a custom backend only if the clinic's needs outgrow
its free tier or RLS model.** This is exactly the kind of policy
decision Rule 2 says not to make silently — flagging it here for
explicit clinic/developer sign-off before work begins.

**Supabase free-tier limits worth knowing up front:** 500 MB database,
50,000 monthly active auth users (irrelevant at clinic scale), and the
project **pauses after 7 days with no API activity** (auto-resumes on
next request, with a short cold-start delay). None of these are
practical blockers for a single clinic, but the pause behavior should
be understood before a pilot.

---

## 3. Database schema (PostgreSQL / Supabase)

Directly translates the existing Dart models
(`lib/models/*.dart`) and the spec's section 9 — no new fields invented.

```sql
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

-- Staff accounts. Supabase Auth owns credentials; this table holds the
-- clinic-specific profile + role that RLS policies key off of.
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
-- Queue numbers reset daily (ClinicPolicy.queueNumberResetsDaily) and must
-- be unique within a day, not globally.
create unique index queue_number_per_day
  on queue_entries (queue_number, (checked_in_at::date));

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

-- Append-only audit trail (spec 9.7, section 17). No UPDATE/DELETE grants
-- for any application role — see RLS policies below.
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
```

### Row-Level Security sketch

RLS is what turns "the backend must enforce authorization, not just
hide the button" (spec Scenario 9) into something the *database*
guarantees, not just the API code:

```sql
alter table queue_entries enable row level security;
alter table queue_events enable row level security;
alter table patients enable row level security;

-- All authenticated staff can read.
create policy staff_read_queue on queue_entries for select
  using (auth.role() = 'authenticated');

-- Only staff whose profile role is DOCTOR may set priority_category_id
-- to the doctor-override category — mirrors
-- ClinicRepository.doctorOverride's in-app check, now enforced at the
-- data layer too.
create policy doctor_only_override on queue_entries for update
  using (
    priority_category_id <> (select id from priority_categories where priority_level = 1)
    or exists (
      select 1 from staff_profiles
      where id = auth.uid() and role = 'DOCTOR' and is_active
    )
  );

-- queue_events is append-only: no update/delete policy is created for
-- ANY role, which — combined with revoking UPDATE/DELETE grants — makes
-- the audit trail tamper-proof at the database level (spec Rule 4).
create policy staff_insert_events on queue_events for insert
  using (auth.role() = 'authenticated');
create policy staff_read_events on queue_events for select
  using (auth.role() = 'authenticated');
revoke update, delete on queue_events from authenticated;
```

The exact policy set needs a full pass once real roles are finalized;
this sketch exists to show the *pattern* (authorization lives in
Postgres, not just in Dart) that Phase 2 should follow throughout.

---

## 4. API surface

`ClinicRepository`'s public methods were deliberately named and shaped
like backend service calls (see its class doc comment). Phase 2's job
is mechanical: implement each one against Supabase instead of an
in-memory `Map`, behind the same interface, so **no screen code needs
to change**.

| `ClinicRepository` method today | Phase 2 backing |
|---|---|
| `registerPatient(...)` | `insert` into `patients` |
| `searchPatients(query)` | Postgres full-text / `ilike` query, or a Supabase Edge Function for fuzzier matching |
| `checkIn(...)` | A single Postgres function (`rpc`) that inserts `visits` + `queue_entries` + the opening `queue_events` rows in one transaction — see §5 |
| `startIntake` / `recordVitals` / `completeIntake` | `rpc` functions performing the same status-transition + audit-event pattern as today's private `_setStatus`/`_logEvent` helpers |
| `callPatient` / `callNext` / `startConsultation` / `completeConsultation` / `skip` / `requeue` | `rpc` functions — see §5 on concurrency |
| `doctorOverride` / `doctorKeepNormalPriority` | `rpc` functions, `security definer` only for the parts that must bypass RLS narrowly (e.g. checking role), never for the write itself |
| `todayQueueEntries` / `doctorQueueSorted` / `needsDecisionQueue` / etc. | Postgres views (`create view doctor_queue_sorted as select ... order by priority_level, checked_in_at`), subscribed to via Supabase Realtime for live updates |
| `eventsForQueueEntry` / `todayEvents` | Plain `select` against `queue_events` |

This becomes the concrete version of the spec's REST list (section 15)
— Supabase's auto-generated REST/RPC endpoints satisfy it without
hand-writing route handlers.

---

## 5. Concurrency & correctness (spec Rule 6, section 23.6)

Two real risks the in-memory prototype doesn't have to worry about,
and how Postgres solves them:

1. **Two devices calling the same "next patient" at once.** Wrap the
   call-next logic in a Postgres function using
   `select ... for update skip locked` on the target `queue_entries`
   row, inside a transaction, so two simultaneous "Call Next" taps
   can't both grab the same patient.
2. **Duplicate check-in from a repeated tap.** Already enforced by the
   `visits_one_open_per_patient_per_day` unique index above — a second
   insert attempt fails at the database, not just in application logic
   (defense in depth beyond the debounce the UI should also have).

Every status transition should be one Postgres function that updates
`queue_entries` **and** inserts the matching `queue_events` row in the
same transaction — never two separate round-trips — so a crash between
the two can't silently break the audit trail (spec Rule 4).

---

## 6. Auth

- **Supabase Auth**, email + password (simplest for clinic staff who
  aren't technical) with a `staff_profiles` row created for each
  account, holding `role` (`ADMIN`/`SECRETARY`/`DOCTOR`) per spec 9.6.
- Session tokens (JWT) issued by Supabase, refreshed automatically by
  the `supabase_flutter` package — replaces `AuthProvider`'s current
  "pick a seeded account" stand-in.
- Password reset via Supabase's built-in email flow (needs an SMTP
  provider configured — Supabase's free tier includes a limited
  built-in mailer sufficient for a pilot).
- No self-registration: staff accounts are created by an admin
  (matches spec's closed-roster staff model — there's no "sign up"
  flow anywhere in the spec).

---

## 7. Migration path — how this replaces `ClinicRepository` without a rewrite

1. Extract an abstract `ClinicApi` interface with exactly
   `ClinicRepository`'s current public method signatures.
2. Make `ClinicRepository` implement it (zero behavior change — this
   step is just a rename/extract, verified by the existing test suite
   passing unchanged).
3. Add `SupabaseClinicApi implements ClinicApi`, backed by the schema
   and RPCs above.
4. Swap which implementation `main.dart` constructs behind a single
   flag (e.g. `--dart-define=BACKEND=supabase`), so the in-memory
   version stays available for demos/tests and CI screenshots.
5. Screens, providers, and widgets do not change at all — they already
   depend only on the interface's method signatures via `Provider`.

This is the spec's own Rule 10 ("build in vertical slices") applied to
the backend swap itself: each method can move from in-memory to
Supabase independently and stay shippable throughout.

---

## 8. Security & Philippine data-privacy considerations (spec section 14)

The spec explicitly flags this as needing dedicated assessment before
production; Phase 2 must include, not defer:

- **Data Privacy Act of 2012 (RA 10173).** Patient records are
  "sensitive personal information" once they include health data.
  Before a real pilot: confirm whether the clinic needs to register
  with the National Privacy Commission (registration is required once
  processing exceeds NPC's threshold headcount/records, which a small
  clinic may or may not cross — needs an explicit check, not an
  assumption), and draft a privacy notice covering what's collected,
  why, retention period, and how a guardian can request access or
  deletion.
- **Minimum necessary collection** — already reflected in the schema
  above; resist adding fields "because other EMRs have them" (spec
  Rule 8).
- **Encryption in transit** — Supabase enforces TLS by default.
- **Encryption at rest** — provided by Supabase's underlying managed
  Postgres.
- **Backups** — Supabase free tier does **not** include point-in-time
  recovery or automated backups; Phase 2 should add a scheduled
  `pg_dump` (e.g. a GitHub Actions cron job) to external storage before
  any real patient data is entered. This is a hard requirement from
  spec section 20 ("Backup/recovery strategy" is Must Have), not
  optional polish.
- **Audit logs** — `queue_events` (already append-only per §3) plus
  Postgres's own connection logs satisfy spec section 17.
- **Least privilege** — RLS policies scoped per role (§3); no
  "postgres superuser" credential ever ships in the Flutter app.

---

## 9. Testing strategy for Phase 2

- Keep every existing `ClinicRepository` unit test (`test/clinic_repository_test.dart`)
  as-is — they encode the spec's acceptance scenarios (section 24) and
  should also pass, unmodified, against `SupabaseClinicApi` once it
  exists, run against a local Supabase instance (`supabase start`,
  Docker-based) in CI. Same test suite, two implementations — this is
  the whole point of the `ClinicApi` interface in §7.
- Add integration tests specifically for the concurrency cases in §5
  (simultaneous call-next, duplicate check-in) that the in-memory
  version can't meaningfully test.
- Add an RLS test pass: attempt a secretary-authenticated client
  performing a doctor-only override and assert it is rejected by
  Postgres, not just by the Flutter UI (directly verifies spec
  Scenario 9).

---

## 10. Rough sequencing

| Step | Deliverable |
|---|---|
| 2.1 | Supabase project + schema above provisioned; RLS policies drafted and reviewed with the clinic |
| 2.2 | `ClinicApi` interface extracted; existing tests still pass against `ClinicRepository` unchanged |
| 2.3 | `SupabaseClinicApi` implemented method-by-method, vertical slice by vertical slice (check-in → intake → queue → doctor actions), per spec Rule 10 |
| 2.4 | Realtime subscriptions wired so the public display and both dashboards update live without polling |
| 2.5 | Auth screens replace the seeded-account picker; RLS policies enforced end-to-end |
| 2.6 | Backup automation (scheduled `pg_dump`) in place *before* any real patient data is entered |
| 2.7 | Pilot per spec section 19 Phase 4 — deploy to the actual clinic, compare before/after metrics |

Each step should ship independently and stay demoable, matching how
Phase 1 was built.

---

## 11. Assumptions in this document requiring confirmation

Per Rule 2/Rule 9, flagging every place this document makes a call the
spec left to the clinic:

- **Supabase over a custom backend** — a real tradeoff, not a
  foregone conclusion; revisit if the clinic already has
  infrastructure preferences or compliance requirements Supabase can't
  meet.
- **Email/password auth** rather than magic-link or SSO — simplest
  for non-technical staff, but not the only option.
- **NPC registration threshold** — needs an actual legal/compliance
  check for this specific clinic's size and processing volume, not an
  assumption made here.
- **Backup cadence** — a daily `pg_dump` is proposed as a reasonable
  default, not a clinic-confirmed policy.
