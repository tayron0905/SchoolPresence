-- Keep attendance and substitution history while allowing an account to be removed.
alter table public.attendance_records alter column recorded_by drop not null;
alter table public.substitutions alter column substitute_teacher_id drop not null;
alter table public.substitutions alter column created_by drop not null;
