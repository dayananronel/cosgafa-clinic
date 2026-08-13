# Cosgafa Pediatric Clinic — Reception & Queue Management

A Flutter implementation of the MVP described in
`pediatric_clinic_reception_queue_management_spec.md`: a reception and
queue workflow for a small pediatric clinic where one secretary handles
intake and vitals, and the doctor holds sole authority over clinical
priority decisions.

This is the **Phase 1 prototype** called for in the spec (section 19,
"Build clickable/mock UI before backend implementation") — a real,
runnable Flutter app with the full business logic implemented, but
backed by an in-memory repository instead of a networked API and
database.

## Getting started

```bash
flutter pub get
flutter run -d chrome      # or any connected device
flutter test                # unit + widget tests
```

Sign in as one of the three seeded demo accounts (Secretary, Doctor,
Admin) on the login screen — no password is required in this prototype
(see Assumptions below).

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
  services/    ClinicRepository — the business-logic/service layer
               (Patient/Visit/Queue "services" from spec section 22,
               combined into one class for MVP scope). Owns validation,
               role authorization, the queue algorithm, and audit
               logging, independent of any screen.
  providers/   AuthProvider (session) + ClinicRepository exposed via
               `provider` for reactive UI updates.
  screens/     One folder per actor (secretary/, doctor/, public/, auth/).
  widgets/     Shared UI (status badges, app bar, avatars, stat cards).
```

`ClinicRepository`'s method boundaries mirror what a real backend would
expose (see spec section 15's endpoint list) so the in-memory
implementation can be swapped for real HTTP calls later without
rewriting screens.

## Assumptions requiring clinic confirmation

The spec repeatedly warns against inventing clinical or operational
policy (Rule 2, Rule 9). Where a decision was left to the clinic, this
prototype makes an explicit, documented assumption rather than a silent
one. Search the codebase for `ASSUMPTION` / `CONFIRMATION REQUIRED` to
find every instance; the main ones are:

- **Authentication is simulated.** Sign-in picks a seeded account with
  no password. Spec section 14/15 requires real authenticated access
  (hashed passwords, session tokens, server-side authorization) before
  any production or pilot deployment.
- **No real backend/database.** All data lives in memory for the app
  session (spec 19 Phase 3 prototype scope). Nothing persists across
  restarts.
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

None of this authorization/priority logic lives only in the UI: the
service layer (`ClinicRepository`) enforces role checks and valid state
transitions itself and throws typed exceptions
(`AuthorizationException`, `InvalidQueueTransitionException`,
`DuplicateOperationException`) regardless of what a screen shows —
covering spec Scenario 9 (secretary must not be able to perform a
doctor-only override even if a button were somehow shown).

## Non-goals (per spec section 21)

This app does not diagnose, triage, recommend treatment, or infer
clinical urgency from any data. All priority beyond arrival order is
either clinic-configured or an explicit, reasoned, audited doctor
decision.
