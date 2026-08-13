# Supabase setup (Phase 2)

One-time setup to point this app at a real database instead of the
in-memory demo backend. Takes about 10 minutes.

## 1. Create a project

Go to [supabase.com](https://supabase.com), create a free project (no
card required). Note the **Project URL** and **anon public key** from
Project Settings → API — you'll need both below.

## 2. Run the migrations

Open the SQL Editor in the Supabase dashboard and run the files in
`supabase/migrations/` **in order** (`0001_schema.sql`,
`0002_row_level_security.sql`, `0003_functions.sql`,
`0004_realtime.sql`) — paste each one's contents and click Run.

## 3. Create staff accounts

There is deliberately no self-registration (spec section 9.6 — a small
clinic's staff roster is closed, not open sign-up). For each staff
member:

1. Dashboard → Authentication → Users → **Add user** (email + password).
2. Copy the new user's UUID.
3. In the SQL Editor:
   ```sql
   insert into staff_profiles (id, name, role) values
     ('<uuid-from-step-2>', 'Grace Villanueva', 'SECRETARY');
   ```
   Roles are `ADMIN`, `SECRETARY`, or `DOCTOR` (spec 9.6 — no nurse role
   unless the clinic later adds one).

## 4. Run the app against it

```bash
flutter run \
  --dart-define=BACKEND=supabase \
  --dart-define=SUPABASE_URL=https://xxxxxxxx.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=eyJ...
```

The anon key is meant to be embedded in client apps — Row-Level
Security (`0002_row_level_security.sql`) is what actually restricts
what it can do, not secrecy of the key itself.

## 5. (Optional) Deploy the Supabase-backed build to GitHub Pages

Add `SUPABASE_URL` and `SUPABASE_ANON_KEY` as repository secrets
(Settings → Secrets and variables → Actions), then pass them to the
`flutter build web` step in `.github/workflows/ci-deploy.yml` as
`--dart-define` flags alongside `--dart-define=BACKEND=supabase`. Until
then, the deployed preview keeps using the in-memory demo backend with
seeded fake data, which is why it's safe to leave public.

## Before any real patient data goes in

- Set up scheduled backups — Supabase's free tier does not include
  point-in-time recovery (see docs/PHASE_2_BACKEND_SCOPE.md §8).
- Read docs/PHASE_2_BACKEND_SCOPE.md §8 in full for Philippine Data
  Privacy Act considerations that need clinic/legal confirmation before
  a real pilot.
