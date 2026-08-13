-- Enables Realtime (postgres_changes) on the tables every screen needs
-- to stay live across devices — the secretary's tablet, the doctor's
-- tablet, and the public display all watch the same queue without
-- polling (spec 10.4-10.6).
alter publication supabase_realtime add table queue_entries;
alter publication supabase_realtime add table visits;
alter publication supabase_realtime add table patients;
alter publication supabase_realtime add table vitals;
alter publication supabase_realtime add table queue_events;
alter publication supabase_realtime add table priority_categories;
