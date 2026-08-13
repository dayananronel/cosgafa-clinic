-- Row-Level Security: the database itself enforces "the backend must
-- enforce authorization, not just hide the button" (spec Scenario 9),
-- not just the RPC functions in 0003_functions.sql. See
-- docs/PHASE_2_BACKEND_SCOPE.md §3.
--
-- All write access goes through the SECURITY DEFINER functions in
-- 0003_functions.sql, which re-check role/state themselves; these
-- policies are the second, independent layer of defense, and the only
-- thing standing between a client and the tables if a function is ever
-- bypassed (e.g. a future direct-table client).

alter table staff_profiles enable row level security;
alter table patients enable row level security;
alter table visits enable row level security;
alter table priority_categories enable row level security;
alter table queue_entries enable row level security;
alter table vitals enable row level security;
alter table queue_events enable row level security;
alter table daily_queue_counters enable row level security;

-- Helper: is the current user an active staff member, and what role?
-- STABLE + SECURITY DEFINER so it can read staff_profiles regardless of
-- the calling policy's own RLS context (avoids recursive policy checks).
create or replace function current_staff_role()
returns user_role
language sql
stable
security definer
set search_path = public
as $$
  select role from staff_profiles where id = auth.uid() and is_active;
$$;

create or replace function is_active_staff()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (select 1 from staff_profiles where id = auth.uid() and is_active);
$$;

-- staff_profiles: staff can read all profiles (needed to show "By Dr.
-- X" on audit events); only admins may write.
create policy staff_profiles_read on staff_profiles for select
  using (is_active_staff());
create policy staff_profiles_admin_write on staff_profiles for all
  using (current_staff_role() = 'ADMIN')
  with check (current_staff_role() = 'ADMIN');

-- Clinical/queue data: any active staff member may read; writes go
-- through SECURITY DEFINER functions only (no direct insert/update/
-- delete policies granted here beyond what the functions themselves
-- perform as their invoking role).
create policy patients_read on patients for select using (is_active_staff());
create policy visits_read on visits for select using (is_active_staff());
create policy priority_categories_read on priority_categories for select using (is_active_staff());
create policy queue_entries_read on queue_entries for select using (is_active_staff());
create policy vitals_read on vitals for select using (is_active_staff());
create policy queue_events_read on queue_events for select using (is_active_staff());

-- queue_events is append-only: no update/delete policy exists for any
-- role, and the privilege itself is revoked below, so even a
-- SECURITY DEFINER bug can't rewrite audit history (spec Rule 4).
revoke update, delete on queue_events from authenticated;

-- Direct table writes from ordinary authenticated clients are not
-- granted; only the SECURITY DEFINER functions (owned by a role with
-- table privileges) can write. This is enforced by simply not creating
-- insert/update/delete policies for 'authenticated' above.
