begin;
select plan(23);

select has_table('public','schools','Schools table exists');
select has_table('public','profiles','Auth profiles table exists');
select has_table('public','classes','Classes table exists');
select has_table('public','students','Students table exists');
select has_table('public','class_memberships','Historical memberships table exists');
select has_table('public','attendance_sessions','Attendance sessions table exists');
select has_table('public','attendance_records','Attendance records table exists');
select has_view('public','absence_records','Scoped absence view exists');
select has_table('public','timetable_slots','Timetable table exists');
select has_table('public','substitutions','Substitutions table exists');
select has_table('public','notifications','Notifications table exists');
select has_table('public','audit_logs','Audit table exists');
select has_table('public','school_years','School year table exists');
select has_table('public','holidays','Holiday table exists');
select has_table('public','rooms','Room table exists');
select has_table('public','absence_details','Protected absence details exist');
select has_view('public','teachers','Role-filtered teacher view exists');
select ok((select relrowsecurity from pg_class where oid='public.students'::regclass),'Student rows have row level security enabled');
select ok((select relrowsecurity from pg_class where oid='public.attendance_records'::regclass),'Attendance rows have row level security enabled');
select ok(to_regprocedure('public.save_attendance(uuid,jsonb,boolean,text)') is not null,'Atomic attendance save RPC exists');
select ok(to_regprocedure('public.attendance_roster(uuid)') is not null,'Session-scoped historical roster RPC exists');
select ok(to_regprocedure('public.create_substitution(uuid,date,integer,uuid,uuid,uuid,uuid,text)') is not null,'Guarded substitution RPC exists');
select is((select count(*)::integer from public.classes where school_id='11111111-1111-4111-8111-111111111111'),7,'Fictional class seed is present');

select * from finish();
rollback;
