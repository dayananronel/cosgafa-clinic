# Dr. Michelle Cosgafa Paediatrics Clinic — Reception & Queue Management

A Flutter implementation of the MVP described in
`pediatric_clinic_reception_queue_management_spec.md`: a reception and
queue workflow for a small pediatric clinic where one secretary handles
intake and vitals, and the doctor holds sole authority over clinical
priority decisions.

The app runs against either of two interchangeable backends behind the
same `ClinicApi` interface, selected at build/run time — no screen code
differs between them:

- **Demo backend** (default) — the **Phase 1 prototype** called for in
  the spec (section 19, "Build clickable/mock UI before backend
  implementation"): full business logic, in-memory only, seeded fake
  data, no real login. This is what the [live preview](#live-preview)
  runs.
- **Supabase backend** (Phase 2) — a real Postgres database, Row-Level
  Security, Realtime sync across devices, and real staff email/password
  login. See **[`supabase/README.md`](supabase/README.md)** to set one
  up (~10 minutes, free tier) and
  **[`docs/PHASE_2_BACKEND_SCOPE.md`](docs/PHASE_2_BACKEND_SCOPE.md)**
  for the design.

## Live preview

Every push to this branch builds and deploys automatically via GitHub
Actions (`.github/workflows/ci-deploy.yml`) to GitHub Pages:

**https://dayananronel.github.io/cosgafa-clinic/**

The workflow runs `flutter analyze` + `flutter test` first, so a
broken build never reaches the preview URL. This is a demo build with
seeded fake data and simulated login — see Assumptions below.

## Getting started

```bash
flutter pub get
flutter run -d chrome      # or any connected device — demo backend
flutter test                # unit + widget tests
```

Sign in as one of the three seeded demo accounts (Secretary, Doctor,
Admin) on the login screen — no password is required in this mode (see
Assumptions below). To run against a real Supabase backend instead:

```bash
flutter run \
  --dart-define=BACKEND=supabase \
  --dart-define=SUPABASE_URL=https://xxxx.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=eyJ...
```

See `supabase/README.md` for the one-time project setup this needs.

## What's implemented

- **Secretary Dashboard** — today's date, live status counts, check-in
  action (spec 10.1).
- **Check-In flow** — existing patient search with confirmation screen,
  new patient registration with duplicate-name/birthdate warnings, and
  reason-for-visit capture, ending in a queue-number confirmation (spec
  10.2, Steps 3–6).
- **Intake screen** — reason, vitals (weight/temperature/height/SpO₂),
  and administrative queue category on one page, with an explicit "ask
  the doctor" flag instead of guessing priority (spec 10.3, Steps 7–9).
- **Waiting Queue** — tabbed staff view of every queue state with
  queue number, identity, category, arrival time, and status (spec 10.4).
- **Doctor Dashboard** — current patient with vitals/reason, a
  needs-decision list, and the next-patient queue with call / start /
  complete / skip / requeue actions (spec 10.5).
- **Doctor priority override** — a dedicated confirmation dialog that
  requires a reason (with a required explanation for "Other") and states
  plainly that it changes the queue order; never a single silent button
  (spec section 11).
- **Public Queue Display** — now-serving and next queue numbers only,
  with no patient-identifying information (spec 10.6, section 12).
- **Audit log** — every queue-affecting action is written as an
  immutable `QueueEvent` with actor, timestamp, and reason where
  applicable, and is viewable from any screen (spec section 17).
- **Queue algorithm** — doctor override > clinic-defined priority
  category > arrival timestamp, exactly as specified (spec section 16).

## Architecture

```
lib/
  models/      Patient, Visit, QueueEntry, Vitals, PriorityCategory,
               QueueEvent, AppUser — kept as separate entities per the
               spec's explicit separation rules (patient vs. visit vs.
               queue vs. vitals).
  services/
    clinic_api.dart          Abstract ClinicApi contract (the write
                              operations) + ClinicDataCache mixin (every
                              read/derived getter — queue ordering,
                              status filters, joins — implemented once,
                              shared by both backends below, so they can
                              never disagree about what "next patient"
                              means).
    clinic_repository.dart   ClinicApi impl #1: in-memory, Phase 1 demo.
    supabase_clinic_api.dart ClinicApi impl #2: real Postgres/Supabase,
                              Phase 2 — reads from Realtime-synced cache,
                              writes via RPC calls to
                              supabase/migrations/0003_functions.sql.
  providers/   AuthSession (shared interface) with two implementations:
               AuthProvider (demo, pick a seeded account) and
               SupabaseAuthProvider (real email/password).
  screens/     One folder per actor (secretary/, doctor/, public/, auth/)
               — depend only on ClinicApi/AuthSession, never on which
               concrete backend is active.
  widgets/     Shared UI (status badges, app bar, avatars, stat cards).
supabase/
  migrations/  SQL: schema, Row-Level Security, RPC functions.
  README.md    Setup instructions for a real Supabase project.
```

Every `ClinicApi` write method returns a `Future` — even the in-memory
demo backend's, which resolves immediately — so screens `await` one
consistent contract regardless of which backend is wired up, rather
than the interface pretending a real network call is synchronous.

## Branding

The app icon and in-app logo (`lib/widgets/clinic_logo.dart`,
`assets/branding/`) are a vector-drawn recreation of the clinic's mark
— a coral circle with a pale heart-and-cross — generated at
`android/app/src/main/res/mipmap-*/ic_launcher.png` and
`web/icons/Icon-*.png` for every platform icon size, including
maskable variants for Android's adaptive icon safe zone.

## Responsive design

Every screen is built to work from a phone (~360px wide) up through
tablet and desktop widths, verified by rendering each screen at a
390×844 viewport:

- `ClinicAppBar` drops the signed-in user's name/role label below
  600px width so the title, audit-log, and public-display actions
  never overflow.
- List rows that combine a queue position, avatar, identity, and a
  trailing action button (waiting queue, doctor's next-patient list)
  switch from a single row to a stacked layout below ~380px, so long
  patient names get ellipsis instead of being crushed by the action
  button.
- The Public Queue Display's "now serving" number scales with
  available width (`FittedBox` + width-proportional font sizing)
  instead of a fixed 120px size, so it fits a phone as well as a
  waiting-room TV.
- Dashboards use a responsive grid (1/2/3 columns based on width) and
  every form/detail screen is wrapped in a scrollable, width-constrained
  container.

## Assumptions requiring clinic confirmation

The spec repeatedly warns against inventing clinical or operational
policy (Rule 2, Rule 9). Where a decision was left to the clinic, this
prototype makes an explicit, documented assumption rather than a silent
one. Search the codebase for `ASSUMPTION` / `CONFIRMATION REQUIRED` to
find every instance; the main ones are:

- **The demo backend's authentication is simulated.** Sign-in picks a
  seeded account with no password, and data lives only in memory for
  the app session — nothing persists across restarts. The Supabase
  backend (opt-in via `--dart-define=BACKEND=supabase`) has real
  email/password auth and a persistent database instead; see
  `docs/PHASE_2_BACKEND_SCOPE.md` §6 and §8 for what still needs
  clinic/legal confirmation (NPC registration threshold, backup
  cadence) before either is used with real patient data.
- **Priority categories** (Doctor Priority / Special Assistance /
  Follow-up-Newborn / Normal) are the spec's own examples, not a
  clinic-confirmed policy (spec 7.5, Step 8).
- **Queue numbers reset daily**, and **requeued patients keep their
  original priority and arrival time** rather than going to the back of
  the line — both are configurable via `ClinicPolicy` (`lib/services/clinic_policy.dart`)
  and both need clinic sign-off (spec section 13).
- **Vitals fields** are limited to weight, temperature, height, and
  oxygen saturation, matching the spec's own example set (spec 9.4) —
  the clinic must confirm which measurements it actually takes.

None of this authorization/priority logic lives only in the UI. For the
demo backend, `ClinicRepository` enforces role checks and valid state
transitions itself and throws typed exceptions
(`AuthorizationException`, `InvalidQueueTransitionException`,
`DuplicateOperationException`) regardless of what a screen shows. For
the Supabase backend, the same checks are enforced twice independently
— once inside each Postgres RPC function
(`supabase/migrations/0003_functions.sql`), and again by Row-Level
Security policies (`0002_row_level_security.sql`) that would block a
disallowed write even if a function had a bug — with database errors
translated back into the same typed exceptions so screens' catch
blocks don't need to know which backend is active. Both cover spec
Scenario 9 (secretary must not be able to perform a doctor-only
override even if a button were somehow shown).

## Non-goals (per spec section 21)

This app does not diagnose, triage, recommend treatment, or infer
clinical urgency from any data. All priority beyond arrival order is
either clinic-configured or an explicit, reasoned, audited doctor
decision.
