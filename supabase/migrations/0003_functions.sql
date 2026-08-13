-- RPC functions: every write operation from ClinicRepository (Phase 1),
-- reimplemented here so the transition rules, audit logging, and
-- concurrency handling live once, in the database, regardless of which
-- client calls them. See docs/PHASE_2_BACKEND_SCOPE.md §4-5.
--
-- Error convention: exceptions are raised with a prefix
-- (AUTHZ: / INVALID_TRANSITION: / DUPLICATE:) that
-- lib/services/supabase_clinic_api.dart parses to rethrow the same typed
-- exceptions the demo backend uses (AuthorizationException,
-- InvalidQueueTransitionException, DuplicateOperationException), so
-- screens' existing catch blocks work unchanged against either backend.

-- Clinic-wide policy toggles the spec leaves to the clinic (section 13) —
-- see ClinicPolicy in lib/services/clinic_policy.dart for the Dart-side
-- equivalent and its "CONFIRMATION REQUIRED" notes.
create table clinic_settings (
  key text primary key,
  value jsonb not null
);
insert into clinic_settings (key, value) values
  ('requeue_retains_priority_and_arrival', 'true'),
  ('queue_number_resets_daily', 'true');
alter table clinic_settings enable row level security;
create policy clinic_settings_read on clinic_settings for select using (is_active_staff());

create or replace function _setting_bool(p_key text, p_default boolean)
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((select value::text::boolean from clinic_settings where key = p_key), p_default);
$$;

create or replace function require_doctor()
returns void language plpgsql security definer set search_path = public as $$
begin
  if current_staff_role() is distinct from 'DOCTOR' then
    raise exception 'AUTHZ: Only a doctor may perform this action.';
  end if;
end;
$$;

create or replace function require_staff()
returns void language plpgsql security definer set search_path = public as $$
begin
  if not is_active_staff() then
    raise exception 'AUTHZ: Only active staff may perform this action.';
  end if;
end;
$$;

create or replace function _log_event(
  p_queue_entry_id uuid,
  p_type queue_event_type,
  p_old_status queue_status,
  p_new_status queue_status,
  p_old_priority text default null,
  p_new_priority text default null,
  p_reason text default null,
  p_metadata jsonb default '{}'::jsonb
) returns void language plpgsql security definer set search_path = public as $$
begin
  insert into queue_events
    (queue_entry_id, event_type, old_status, new_status, old_priority, new_priority, reason, performed_by, metadata)
  values
    (p_queue_entry_id, p_type, p_old_status, p_new_status, p_old_priority, p_new_priority, p_reason, auth.uid(), p_metadata);
end;
$$;

create table patient_number_counters (
  counter_year int primary key,
  next_number int not null default 1
);
alter table patient_number_counters enable row level security;

-- ------------------------------------------------------------------
-- Patient Service (spec 9.1)
-- ------------------------------------------------------------------

create or replace function register_patient(
  p_first_name text,
  p_middle_name text,
  p_last_name text,
  p_birthdate date,
  p_sex sex,
  p_address text,
  p_guardian_name text,
  p_guardian_contact text
) returns patients
language plpgsql security definer set search_path = public as $$
declare
  v_patient patients;
  v_year int := extract(year from now())::int;
  v_seq int;
begin
  perform require_staff();

  insert into patient_number_counters (counter_year, next_number)
  values (v_year, 2)
  on conflict (counter_year) do update set next_number = patient_number_counters.next_number + 1
  returning next_number - 1 into v_seq;

  insert into patients
    (patient_number, first_name, middle_name, last_name, birthdate, sex, address, guardian_name, guardian_contact, created_by, updated_by)
  values
    ('P' || v_year || '-' || lpad(v_seq::text, 5, '0'), trim(p_first_name), trim(coalesce(p_middle_name, '')),
     trim(p_last_name), p_birthdate, p_sex, trim(p_address), trim(p_guardian_name), trim(p_guardian_contact),
     auth.uid(), auth.uid())
  returning * into v_patient;

  return v_patient;
end;
$$;

-- ------------------------------------------------------------------
-- Queue Service (spec 9.3, 7, 16)
-- ------------------------------------------------------------------

create or replace function check_in(
  p_patient_id uuid,
  p_reason_for_visit text,
  p_newly_registered boolean default false
) returns queue_entries
language plpgsql security definer set search_path = public as $$
declare
  v_visit_id uuid;
  v_entry queue_entries;
  v_normal_category_id uuid;
  v_normal_priority_level int;
  v_today date := current_date;
  v_queue_number int;
begin
  perform require_staff();

  if exists (
    select 1 from visits
    where patient_id = p_patient_id and visit_date = v_today and status = 'OPEN'
  ) then
    raise exception 'DUPLICATE: This patient already has an active visit today.';
  end if;

  insert into visits (patient_id, visit_date, reason_for_visit, status, created_by, updated_by)
  values (p_patient_id, v_today, trim(p_reason_for_visit), 'OPEN', auth.uid(), auth.uid())
  returning id into v_visit_id;

  if p_newly_registered then
    insert into queue_events (queue_entry_id, event_type, performed_by, metadata)
    values (null, 'PATIENT_REGISTERED', auth.uid(), jsonb_build_object('patientId', p_patient_id));
  end if;

  select id, priority_level into v_normal_category_id, v_normal_priority_level
  from priority_categories order by priority_level desc limit 1;

  -- Atomic daily queue number via upsert — avoids the race a plain
  -- "select max(queue_number)+1" would have under concurrent check-ins,
  -- and resets automatically because each date is a fresh row.
  insert into daily_queue_counters (counter_date, next_number)
  values (v_today, 2)
  on conflict (counter_date) do update set next_number = daily_queue_counters.next_number + 1
  returning next_number - 1 into v_queue_number;

  insert into queue_entries
    (visit_id, queue_number, checked_in_at, priority_category_id, priority_level, status)
  values
    (v_visit_id, v_queue_number, now(), v_normal_category_id, v_normal_priority_level, 'WAITING_FOR_INTAKE')
  returning * into v_entry;

  perform _log_event(v_entry.id, 'VISIT_CREATED', null, null, null, null, null,
    jsonb_build_object('reasonForVisit', p_reason_for_visit));
  perform _log_event(v_entry.id, 'CHECK_IN', null, 'CHECKED_IN');
  perform _log_event(v_entry.id, 'QUEUE_CREATED', 'CHECKED_IN', 'WAITING_FOR_INTAKE', null, null, null,
    jsonb_build_object('queueNumber', v_queue_number));

  return v_entry;
end;
$$;

create or replace function start_intake(p_queue_entry_id uuid) returns queue_entries
language plpgsql security definer set search_path = public as $$
declare v_entry queue_entries; v_old queue_status;
begin
  perform require_staff();
  select * into v_entry from queue_entries where id = p_queue_entry_id for update;
  if not found then raise exception 'Unknown queue entry: %', p_queue_entry_id; end if;
  if v_entry.status <> 'WAITING_FOR_INTAKE' then
    raise exception 'INVALID_TRANSITION: Cannot start intake while status is %.', v_entry.status;
  end if;
  v_old := v_entry.status;
  update queue_entries set status = 'IN_INTAKE', updated_at = now()
    where id = p_queue_entry_id returning * into v_entry;
  perform _log_event(p_queue_entry_id, 'INTAKE_STARTED', v_old, v_entry.status);
  return v_entry;
end;
$$;

create or replace function record_vitals(
  p_queue_entry_id uuid,
  p_weight_kg numeric default null,
  p_temperature_c numeric default null,
  p_height_cm numeric default null,
  p_oxygen_saturation numeric default null
) returns queue_entries
language plpgsql security definer set search_path = public as $$
declare v_entry queue_entries; v_old queue_status; v_new_status queue_status;
begin
  perform require_staff();
  select * into v_entry from queue_entries where id = p_queue_entry_id for update;
  if not found then raise exception 'Unknown queue entry: %', p_queue_entry_id; end if;
  if v_entry.status not in ('IN_INTAKE', 'VITALS_COMPLETE') then
    raise exception 'INVALID_TRANSITION: Cannot record vitals while status is %.', v_entry.status;
  end if;
  v_old := v_entry.status;

  insert into vitals (visit_id, weight_kg, temperature_c, height_cm, oxygen_saturation, recorded_by)
  values (v_entry.visit_id, p_weight_kg, p_temperature_c, p_height_cm, p_oxygen_saturation, auth.uid());

  v_new_status := case when v_old = 'IN_INTAKE' then 'VITALS_COMPLETE'::queue_status else v_old end;
  update queue_entries set status = v_new_status, updated_at = now()
    where id = p_queue_entry_id returning * into v_entry;
  perform _log_event(p_queue_entry_id, 'VITALS_RECORDED', v_old, v_new_status);
  return v_entry;
end;
$$;

create or replace function complete_intake(
  p_queue_entry_id uuid,
  p_priority_category_id uuid,
  p_needs_doctor_decision boolean default false,
  p_reason_for_visit_override text default null
) returns queue_entries
language plpgsql security definer set search_path = public as $$
declare
  v_entry queue_entries;
  v_old queue_status;
  v_old_category_id uuid;
  v_old_category_name text;
  v_new_category_name text;
  v_new_priority_level int;
  v_doctor_category_id uuid;
  v_new_status queue_status;
begin
  perform require_staff();
  select * into v_entry from queue_entries where id = p_queue_entry_id for update;
  if not found then raise exception 'Unknown queue entry: %', p_queue_entry_id; end if;
  if v_entry.status <> 'VITALS_COMPLETE' then
    raise exception 'INVALID_TRANSITION: Cannot complete intake while status is %.', v_entry.status;
  end if;

  select id into v_doctor_category_id from priority_categories order by priority_level asc limit 1;
  if p_priority_category_id = v_doctor_category_id then
    raise exception 'AUTHZ: Only a doctor may assign the doctor-priority category.';
  end if;

  if p_reason_for_visit_override is not null and length(trim(p_reason_for_visit_override)) > 0 then
    update visits set reason_for_visit = trim(p_reason_for_visit_override), updated_at = now(), updated_by = auth.uid()
      where id = v_entry.visit_id;
  end if;

  v_old := v_entry.status;
  v_old_category_id := v_entry.priority_category_id;
  select name into v_old_category_name from priority_categories where id = v_old_category_id;
  select name, priority_level into v_new_category_name, v_new_priority_level
    from priority_categories where id = p_priority_category_id;

  v_new_status := case when p_needs_doctor_decision then 'NEEDS_DOCTOR_DECISION'::queue_status
                        else 'WAITING_FOR_DOCTOR'::queue_status end;

  update queue_entries
    set priority_category_id = p_priority_category_id, priority_level = v_new_priority_level,
        status = v_new_status, updated_at = now()
    where id = p_queue_entry_id returning * into v_entry;

  if v_old_category_id <> p_priority_category_id then
    perform _log_event(p_queue_entry_id, 'PRIORITY_CHANGED', null, null, v_old_category_name, v_new_category_name);
  end if;
  perform _log_event(
    p_queue_entry_id,
    case when p_needs_doctor_decision then 'NEEDS_DOCTOR_DECISION'::queue_event_type else 'QUEUE_CREATED'::queue_event_type end,
    v_old, v_new_status
  );
  return v_entry;
end;
$$;

create or replace function call_patient(p_queue_entry_id uuid) returns queue_entries
language plpgsql security definer set search_path = public as $$
declare v_entry queue_entries; v_old queue_status; v_serving_count int;
begin
  perform require_staff();

  -- Locks any currently-serving rows for today so two simultaneous
  -- "call" attempts can't both succeed (spec Rule 6 / section 23.6).
  select count(*) into v_serving_count
    from queue_entries
    where status in ('CALLED', 'IN_CONSULTATION') and checked_in_at::date = current_date and id <> p_queue_entry_id
    for update;
  if v_serving_count > 0 then
    raise exception 'INVALID_TRANSITION: A patient is already being served. Complete or skip that consultation first.';
  end if;

  select * into v_entry from queue_entries where id = p_queue_entry_id for update;
  if not found then raise exception 'Unknown queue entry: %', p_queue_entry_id; end if;
  if v_entry.status <> 'WAITING_FOR_DOCTOR' then
    raise exception 'INVALID_TRANSITION: Cannot call this patient while status is %.', v_entry.status;
  end if;
  v_old := v_entry.status;
  update queue_entries set status = 'CALLED', called_at = now(), updated_at = now()
    where id = p_queue_entry_id returning * into v_entry;
  perform _log_event(p_queue_entry_id, 'CALLED', v_old, v_entry.status);
  return v_entry;
end;
$$;

create or replace function call_next() returns queue_entries
language plpgsql security definer set search_path = public as $$
declare v_next_id uuid;
begin
  perform require_staff();
  select id into v_next_id
    from queue_entries
    where status = 'WAITING_FOR_DOCTOR' and checked_in_at::date = current_date
    order by priority_level asc, checked_in_at asc
    limit 1
    for update skip locked;
  if v_next_id is null then
    raise exception 'INVALID_TRANSITION: No patients are waiting for the doctor.';
  end if;
  return call_patient(v_next_id);
end;
$$;

create or replace function start_consultation(p_queue_entry_id uuid) returns queue_entries
language plpgsql security definer set search_path = public as $$
declare v_entry queue_entries; v_old queue_status;
begin
  perform require_staff();
  select * into v_entry from queue_entries where id = p_queue_entry_id for update;
  if not found then raise exception 'Unknown queue entry: %', p_queue_entry_id; end if;
  if v_entry.status <> 'CALLED' then
    raise exception 'INVALID_TRANSITION: Cannot start consultation while status is %.', v_entry.status;
  end if;
  v_old := v_entry.status;
  update queue_entries set status = 'IN_CONSULTATION', consultation_started_at = now(), updated_at = now()
    where id = p_queue_entry_id returning * into v_entry;
  update visits set status = 'IN_CONSULTATION', updated_at = now(), updated_by = auth.uid() where id = v_entry.visit_id;
  perform _log_event(p_queue_entry_id, 'CONSULTATION_STARTED', v_old, v_entry.status);
  return v_entry;
end;
$$;

create or replace function complete_consultation(p_queue_entry_id uuid) returns queue_entries
language plpgsql security definer set search_path = public as $$
declare v_entry queue_entries; v_old queue_status;
begin
  perform require_staff();
  select * into v_entry from queue_entries where id = p_queue_entry_id for update;
  if not found then raise exception 'Unknown queue entry: %', p_queue_entry_id; end if;
  if v_entry.status <> 'IN_CONSULTATION' then
    raise exception 'INVALID_TRANSITION: Cannot complete consultation while status is %.', v_entry.status;
  end if;
  v_old := v_entry.status;
  update queue_entries set status = 'COMPLETED', completed_at = now(), updated_at = now()
    where id = p_queue_entry_id returning * into v_entry;
  update visits set status = 'COMPLETED', updated_at = now(), updated_by = auth.uid() where id = v_entry.visit_id;
  perform _log_event(p_queue_entry_id, 'COMPLETED', v_old, v_entry.status);
  return v_entry;
end;
$$;

create or replace function skip_patient(p_queue_entry_id uuid) returns queue_entries
language plpgsql security definer set search_path = public as $$
declare v_entry queue_entries; v_old queue_status;
begin
  perform require_staff();
  select * into v_entry from queue_entries where id = p_queue_entry_id for update;
  if not found then raise exception 'Unknown queue entry: %', p_queue_entry_id; end if;
  if v_entry.status <> 'CALLED' then
    raise exception 'INVALID_TRANSITION: Cannot mark as skipped while status is %.', v_entry.status;
  end if;
  v_old := v_entry.status;
  update queue_entries set status = 'SKIPPED', called_at = null, updated_at = now()
    where id = p_queue_entry_id returning * into v_entry;
  perform _log_event(p_queue_entry_id, 'SKIPPED', v_old, v_entry.status);
  return v_entry;
end;
$$;

create or replace function requeue_patient(p_queue_entry_id uuid) returns queue_entries
language plpgsql security definer set search_path = public as $$
declare v_entry queue_entries; v_old queue_status; v_retain boolean; v_normal_id uuid; v_normal_level int;
begin
  perform require_staff();
  select * into v_entry from queue_entries where id = p_queue_entry_id for update;
  if not found then raise exception 'Unknown queue entry: %', p_queue_entry_id; end if;
  if v_entry.status <> 'SKIPPED' then
    raise exception 'INVALID_TRANSITION: Cannot requeue this patient while status is %.', v_entry.status;
  end if;
  v_old := v_entry.status;
  v_retain := _setting_bool('requeue_retains_priority_and_arrival', true);

  if v_retain then
    update queue_entries set status = 'WAITING_FOR_DOCTOR', updated_at = now()
      where id = p_queue_entry_id returning * into v_entry;
  else
    select id, priority_level into v_normal_id, v_normal_level
      from priority_categories order by priority_level desc limit 1;
    update queue_entries
      set status = 'WAITING_FOR_DOCTOR', checked_in_at = now(),
          priority_category_id = v_normal_id, priority_level = v_normal_level, updated_at = now()
      where id = p_queue_entry_id returning * into v_entry;
  end if;

  perform _log_event(p_queue_entry_id, 'REQUEUED', v_old, v_entry.status, null, null, null,
    jsonb_build_object('retainedOriginalPosition', v_retain));
  return v_entry;
end;
$$;

create or replace function mark_temporarily_away(p_queue_entry_id uuid) returns queue_entries
language plpgsql security definer set search_path = public as $$
declare v_entry queue_entries; v_old queue_status;
begin
  perform require_staff();
  select * into v_entry from queue_entries where id = p_queue_entry_id for update;
  if not found then raise exception 'Unknown queue entry: %', p_queue_entry_id; end if;
  if v_entry.status not in ('WAITING_FOR_DOCTOR', 'NEEDS_DOCTOR_DECISION', 'WAITING_FOR_INTAKE') then
    raise exception 'INVALID_TRANSITION: Cannot mark temporarily away while status is %.', v_entry.status;
  end if;
  v_old := v_entry.status;
  update queue_entries set status = 'TEMPORARILY_AWAY', updated_at = now()
    where id = p_queue_entry_id returning * into v_entry;
  perform _log_event(p_queue_entry_id, 'TEMPORARILY_AWAY', v_old, v_entry.status, null, null, null,
    jsonb_build_object('previousStatus', v_old));
  return v_entry;
end;
$$;

create or replace function return_from_away(p_queue_entry_id uuid) returns queue_entries
language plpgsql security definer set search_path = public as $$
declare v_entry queue_entries; v_old queue_status; v_restored queue_status; v_prev text;
begin
  perform require_staff();
  select * into v_entry from queue_entries where id = p_queue_entry_id for update;
  if not found then raise exception 'Unknown queue entry: %', p_queue_entry_id; end if;
  if v_entry.status <> 'TEMPORARILY_AWAY' then
    raise exception 'INVALID_TRANSITION: Cannot return from temporarily away while status is %.', v_entry.status;
  end if;
  v_old := v_entry.status;

  select metadata->>'previousStatus' into v_prev
    from queue_events
    where queue_entry_id = p_queue_entry_id and event_type = 'TEMPORARILY_AWAY'
    order by created_at desc limit 1;
  v_restored := coalesce(v_prev::queue_status, 'WAITING_FOR_DOCTOR'::queue_status);

  update queue_entries set status = v_restored, updated_at = now()
    where id = p_queue_entry_id returning * into v_entry;
  perform _log_event(p_queue_entry_id, 'RETURNED', v_old, v_entry.status);
  return v_entry;
end;
$$;

create or replace function cancel_queue_entry(p_queue_entry_id uuid, p_reason text) returns queue_entries
language plpgsql security definer set search_path = public as $$
declare v_entry queue_entries; v_old queue_status;
begin
  perform require_staff();
  select * into v_entry from queue_entries where id = p_queue_entry_id for update;
  if not found then raise exception 'Unknown queue entry: %', p_queue_entry_id; end if;
  if v_entry.status not in (
    'WAITING_FOR_INTAKE', 'IN_INTAKE', 'VITALS_COMPLETE', 'WAITING_FOR_DOCTOR',
    'NEEDS_DOCTOR_DECISION', 'TEMPORARILY_AWAY'
  ) then
    raise exception 'INVALID_TRANSITION: Cannot cancel this visit while status is %.', v_entry.status;
  end if;
  v_old := v_entry.status;
  update queue_entries set status = 'CANCELLED', updated_at = now()
    where id = p_queue_entry_id returning * into v_entry;
  update visits set status = 'CANCELLED', updated_at = now(), updated_by = auth.uid() where id = v_entry.visit_id;
  perform _log_event(p_queue_entry_id, 'CANCELLED', v_old, v_entry.status, null, null, p_reason);
  return v_entry;
end;
$$;

create or replace function doctor_override(
  p_queue_entry_id uuid,
  p_reason text,
  p_other_explanation text default null
) returns queue_entries
language plpgsql security definer set search_path = public as $$
declare
  v_entry queue_entries; v_old queue_status;
  v_old_category_name text; v_new_category_id uuid; v_new_category_name text; v_new_level int;
  v_final_reason text;
begin
  perform require_doctor();
  select * into v_entry from queue_entries where id = p_queue_entry_id for update;
  if not found then raise exception 'Unknown queue entry: %', p_queue_entry_id; end if;
  if v_entry.status not in ('WAITING_FOR_DOCTOR', 'NEEDS_DOCTOR_DECISION') then
    raise exception 'INVALID_TRANSITION: Cannot override priority while status is %.', v_entry.status;
  end if;
  v_old := v_entry.status;
  select name into v_old_category_name from priority_categories where id = v_entry.priority_category_id;
  select id, name, priority_level into v_new_category_id, v_new_category_name, v_new_level
    from priority_categories order by priority_level asc limit 1;

  v_final_reason := case when p_reason = 'Other' and coalesce(trim(p_other_explanation), '') <> ''
                          then trim(p_other_explanation) else p_reason end;

  update queue_entries
    set priority_category_id = v_new_category_id, priority_level = v_new_level,
        status = 'WAITING_FOR_DOCTOR', updated_at = now()
    where id = p_queue_entry_id returning * into v_entry;

  perform _log_event(p_queue_entry_id, 'DOCTOR_OVERRIDE', v_old, v_entry.status,
    v_old_category_name, v_new_category_name, v_final_reason);
  return v_entry;
end;
$$;

create or replace function doctor_keep_normal_priority(p_queue_entry_id uuid) returns queue_entries
language plpgsql security definer set search_path = public as $$
declare v_entry queue_entries; v_old queue_status;
begin
  perform require_doctor();
  select * into v_entry from queue_entries where id = p_queue_entry_id for update;
  if not found then raise exception 'Unknown queue entry: %', p_queue_entry_id; end if;
  if v_entry.status <> 'NEEDS_DOCTOR_DECISION' then
    raise exception 'INVALID_TRANSITION: Cannot resolve priority decision while status is %.', v_entry.status;
  end if;
  v_old := v_entry.status;
  update queue_entries set status = 'WAITING_FOR_DOCTOR', updated_at = now()
    where id = p_queue_entry_id returning * into v_entry;
  perform _log_event(p_queue_entry_id, 'PRIORITY_CHANGED', v_old, v_entry.status, null, null,
    'Doctor reviewed and kept current priority');
  return v_entry;
end;
$$;

-- Every RPC above is SECURITY DEFINER (so it can write despite the
-- table-level RLS lockdown in 0002) but starts with require_staff() /
-- require_doctor(), so authorization is still checked on every call —
-- exactly like ClinicRepository's Dart checks, just server-side.
grant execute on all functions in schema public to authenticated;
