begin;
select plan(7);

insert into auth.users(id,email,aud,role,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
values('22222222-2222-4222-8222-222222222222','teacher-test@schoolpresence.invalid','authenticated','authenticated','{"provider":"email","providers":["email"]}','{"name":"Test Lehrkraft"}',now(),now());
insert into public.profiles(id,school_id,name,email,role)
values('22222222-2222-4222-8222-222222222222','11111111-1111-4111-8111-111111111111','Test Lehrkraft','teacher-test@schoolpresence.invalid','teacher');
update public.classes set teacher_id='22222222-2222-4222-8222-222222222222' where id='11111111-1111-4111-8111-111111111101';
insert into public.attendance_sessions(id,school_id,class_id,session_date,period,subject_id,teacher_id)
select '22222222-2222-4222-8222-222222222201','11111111-1111-4111-8111-111111111111','11111111-1111-4111-8111-111111111101',current_date,1,id,'22222222-2222-4222-8222-222222222222'
from public.subjects where school_id='11111111-1111-4111-8111-111111111111' and name='Mathematik';

set local role authenticated;
select set_config('request.jwt.claim.sub','22222222-2222-4222-8222-222222222222',true);
select is((select count(*)::integer from public.classes),1,'Teacher only sees the assigned class');
select is((select count(*)::integer from public.students where class_id='11111111-1111-4111-8111-111111111101'),15,'Teacher sees students in the assigned class');
select is((select count(*)::integer from public.students where class_id='11111111-1111-4111-8111-111111111102'),0,'Teacher cannot see students in another class');
select is((select count(*)::integer from public.attendance_sessions),1,'Teacher sees the assigned class attendance session');
select is((select count(*)::integer from public.attendance_roster('22222222-2222-4222-8222-222222222201')),15,'Attendance roster is scoped to the assigned session');
select throws_ok($$select public.save_attendance('22222222-2222-4222-8222-222222222201','[]'::jsonb,true,'')$$,'P0001','Die Liste enthält noch nicht kontrollierte Einträge','Cannot complete a list with missing attendance');
select throws_ok($$insert into public.attendance_records(session_id,student_id,status,recorded_by) values('22222222-2222-4222-8222-222222222201','11111111-1111-4111-8111-111111111001','present','22222222-2222-4222-8222-222222222222')$$,'42501','new row violates row-level security policy for table "attendance_records"','Attendance records cannot be inserted outside the atomic RPC');

reset role;
select * from finish();
rollback;
