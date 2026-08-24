-- Guest Mode: lets a patient/guardian check themselves into the queue
-- from an unauthenticated device (e.g. a waiting-room tablet) without a
-- staff account, so the secretary doesn't have to type in every
-- patient's details by hand. New-patient registration only — there is
-- deliberately no way for an unauthenticated caller to search or browse
-- existing patient records (that would leak other families' names,
-- addresses, and contact numbers to anyone with the anon key).
--
-- This mirrors register_patient() + check_in() (0003_functions.sql)
-- but is a single function (one round trip, one transaction) that skips
-- require_staff() and returns patient + visit + queue_entry together,
-- since an unauthenticated caller can't follow up with a table SELECT
-- (every read policy requires is_active_staff()).

create or replace function guest_check_in(
  p_first_name text,
  p_middle_name text,
  p_last_name text,
  p_birthdate date,
  p_sex sex,
  p_address text,
  p_guardian_name text,
  p_guardian_contact text,
  p_reason_for_visit text
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_patient patients;
  v_visit visits;
  v_entry queue_entries;
  v_year int := extract(year from now())::int;
  v_seq int;
  v_today date := clinic_day(now());
  v_normal_category_id uuid;
  v_normal_priority_level int;
  v_queue_number int;
begin
  insert into patient_number_counters (counter_year, next_number)
  values (v_year, 2)
  on conflict (counter_year) do update set next_number = patient_number_counters.next_number + 1
  returning next_number - 1 into v_seq;

  insert into patients
    (patient_number, first_name, middle_name, last_name, birthdate, sex, address, guardian_name, guardian_contact)
  values
    ('P' || v_year || '-' || lpad(v_seq::text, 5, '0'), trim(p_first_name), trim(coalesce(p_middle_name, '')),
     trim(p_last_name), p_birthdate, p_sex, trim(p_address), trim(p_guardian_name), trim(p_guardian_contact))
  returning * into v_patient;

  insert into visits (patient_id, visit_date, reason_for_visit, status)
  values (v_patient.id, v_today, trim(p_reason_for_visit), 'OPEN')
  returning * into v_visit;

  insert into queue_events (queue_entry_id, event_type, performed_by, metadata)
  values (null, 'PATIENT_REGISTERED', null, jsonb_build_object('patientId', v_patient.id, 'source', 'guest'));

  select id, priority_level into v_normal_category_id, v_normal_priority_level
  from priority_categories order by priority_level desc limit 1;

  insert into daily_queue_counters (counter_date, next_number)
  values (v_today, 2)
  on conflict (counter_date) do update set next_number = daily_queue_counters.next_number + 1
  returning next_number - 1 into v_queue_number;

  insert into queue_entries
    (visit_id, queue_number, checked_in_at, priority_category_id, priority_level, status)
  values
    (v_visit.id, v_queue_number, now(), v_normal_category_id, v_normal_priority_level, 'WAITING_FOR_INTAKE')
  returning * into v_entry;

  insert into queue_events (queue_entry_id, event_type, old_status, new_status, performed_by, metadata)
  values (v_entry.id, 'VISIT_CREATED', null, null, null, jsonb_build_object('reasonForVisit', p_reason_for_visit, 'source', 'guest'));
  insert into queue_events (queue_entry_id, event_type, new_status, performed_by, metadata)
  values (v_entry.id, 'CHECK_IN', 'CHECKED_IN', null, jsonb_build_object('source', 'guest'));
  insert into queue_events (queue_entry_id, event_type, old_status, new_status, performed_by, metadata)
  values (v_entry.id, 'QUEUE_CREATED', 'CHECKED_IN', 'WAITING_FOR_INTAKE', null,
    jsonb_build_object('queueNumber', v_queue_number, 'source', 'guest'));

  return jsonb_build_object(
    'patient', to_jsonb(v_patient),
    'visit', to_jsonb(v_visit),
    'queue_entry', to_jsonb(v_entry)
  );
end;
$$;

-- Only this one function is opened up to unauthenticated callers — every
-- other RPC still calls require_staff()/require_doctor() internally, and
-- no table gets a direct INSERT/SELECT policy for anon (see 0002's
-- "direct table writes ... not granted" note, which still holds).
grant execute on function guest_check_in(text, text, text, date, sex, text, text, text, text) to anon, authenticated;
