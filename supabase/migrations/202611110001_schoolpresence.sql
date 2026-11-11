-- SchoolPresence initial schema. Run once in Supabase SQL Editor.
create extension if not exists pgcrypto;
create schema if not exists private;

create table if not exists public.schools (
  id uuid primary key default gen_random_uuid(), name text not null,
  address text not null default '', school_year text not null default '2026/2027',
  timezone text not null default 'Europe/Berlin', created_at timestamptz not null default now()
);
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  school_id uuid not null references public.schools(id), name text not null,
  email text not null unique, role text not null check (role in ('admin','leadership','teacher','student')),
  active boolean not null default true, created_at timestamptz not null default now()
);
create table if not exists public.classes (
  id uuid primary key default gen_random_uuid(), school_id uuid not null references public.schools(id),
  name text not null, teacher_id uuid references public.profiles(id), room text not null default '',
  school_year text not null default '2026/2027', active boolean not null default true,
  created_at timestamptz not null default now(), unique(school_id,name)
);
create table if not exists public.students (
  id uuid primary key default gen_random_uuid(), school_id uuid not null references public.schools(id),
  first_name text not null, last_name text not null, student_code text not null,
  class_id uuid references public.classes(id), active boolean not null default true,
  created_at timestamptz not null default now(), unique(school_id,student_code)
);
create table if not exists public.subjects (
  id uuid primary key default gen_random_uuid(), school_id uuid not null references public.schools(id), name text not null,
  unique(school_id,name)
);
create table if not exists public.attendance_sessions (
  id uuid primary key default gen_random_uuid(), school_id uuid not null references public.schools(id),
  class_id uuid not null references public.classes(id), session_date date not null, period integer not null check(period between 1 and 20),
  subject_id uuid references public.subjects(id), teacher_id uuid references public.profiles(id),
  status text not null default 'open' check(status in ('open','completed')),
  created_at timestamptz not null default now(), unique(class_id,session_date,period)
);
create table if not exists public.attendance_records (
  id uuid primary key default gen_random_uuid(), session_id uuid not null references public.attendance_sessions(id) on delete cascade,
  student_id uuid not null references public.students(id),
  status text not null check(status in ('present','excused','unexcused','late','unchecked')),
  recorded_by uuid not null references public.profiles(id), updated_at timestamptz not null default now(),
  unique(session_id,student_id)
);
create table if not exists public.audit_logs (
  id uuid primary key default gen_random_uuid(), school_id uuid not null references public.schools(id),
  user_id uuid references public.profiles(id), action text not null, entity text not null, entity_id text not null,
  old_value jsonb, new_value jsonb, created_at timestamptz not null default now()
);
create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(), school_id uuid not null references public.schools(id),
  user_id uuid references public.profiles(id), title text not null, body text not null,
  read boolean not null default false, created_at timestamptz not null default now()
);
revoke all on all tables in schema public from anon;
grant select,insert,update,delete on public.schools,public.profiles,public.classes,public.students,public.subjects,public.attendance_sessions,public.attendance_records,public.audit_logs,public.notifications to authenticated;
create index if not exists students_school_class_idx on public.students(school_id,class_id,last_name);
create index if not exists sessions_school_date_idx on public.attendance_sessions(school_id,session_date desc);
create index if not exists records_student_idx on public.attendance_records(student_id,updated_at desc);
create index if not exists audit_school_created_idx on public.audit_logs(school_id,created_at desc);

create or replace function private.current_school_id() returns uuid
language sql stable security definer set search_path=public,pg_temp
as $$ select school_id from public.profiles where id=auth.uid() and active $$;
create or replace function private.has_role(allowed text[]) returns boolean
language sql stable security definer set search_path=public,pg_temp
as $$ select exists(select 1 from public.profiles where id=auth.uid() and active and role=any(allowed)) $$;
create or replace function private.can_access_class(target uuid) returns boolean
language sql stable security definer set search_path=public,pg_temp
as $$ select exists(select 1 from public.classes c where c.id=target and c.school_id=private.current_school_id() and c.active and
  (private.has_role(array['admin','leadership']) or c.teacher_id=auth.uid())) $$;
revoke all on function private.current_school_id() from public;
revoke all on function private.has_role(text[]) from public;
revoke all on function private.can_access_class(uuid) from public;
grant usage on schema private to authenticated;
grant execute on all functions in schema private to authenticated;

alter table public.schools enable row level security;
alter table public.profiles enable row level security;
alter table public.classes enable row level security;
alter table public.students enable row level security;
alter table public.subjects enable row level security;
alter table public.attendance_sessions enable row level security;
alter table public.attendance_records enable row level security;
alter table public.audit_logs enable row level security;
alter table public.notifications enable row level security;

create policy school_read on public.schools for select to authenticated using(id=private.current_school_id());
create policy school_admin_update on public.schools for update to authenticated using(id=private.current_school_id() and private.has_role(array['admin'])) with check(id=private.current_school_id() and private.has_role(array['admin']));
create policy profiles_staff_read on public.profiles for select to authenticated using(school_id=private.current_school_id() and private.has_role(array['admin','leadership']));
create policy profile_self_read on public.profiles for select to authenticated using(id=auth.uid() and active);
create policy classes_read on public.classes for select to authenticated using(school_id=private.current_school_id() and (private.has_role(array['admin','leadership']) or teacher_id=auth.uid()));
create policy classes_create on public.classes for insert to authenticated with check(school_id=private.current_school_id() and private.has_role(array['admin','leadership']));
create policy classes_update on public.classes for update to authenticated using(school_id=private.current_school_id() and private.has_role(array['admin','leadership'])) with check(school_id=private.current_school_id() and private.has_role(array['admin','leadership']));
create policy students_read on public.students for select to authenticated using(school_id=private.current_school_id() and private.can_access_class(class_id));
create policy students_create on public.students for insert to authenticated with check(school_id=private.current_school_id() and private.has_role(array['admin','leadership']) and private.can_access_class(class_id));
create policy students_update on public.students for update to authenticated using(school_id=private.current_school_id() and private.has_role(array['admin','leadership'])) with check(school_id=private.current_school_id() and private.has_role(array['admin','leadership']) and private.can_access_class(class_id));
create policy subjects_read on public.subjects for select to authenticated using(school_id=private.current_school_id());
create policy sessions_read on public.attendance_sessions for select to authenticated using(school_id=private.current_school_id() and private.can_access_class(class_id));
create policy sessions_create on public.attendance_sessions for insert to authenticated with check(school_id=private.current_school_id() and private.can_access_class(class_id) and (private.has_role(array['admin','leadership']) or teacher_id=auth.uid()));
create policy records_read on public.attendance_records for select to authenticated using(exists(select 1 from public.attendance_sessions s where s.id=session_id and s.school_id=private.current_school_id() and private.can_access_class(s.class_id)));
create policy audit_read on public.audit_logs for select to authenticated using(school_id=private.current_school_id() and private.has_role(array['admin','leadership']));
create policy notifications_read on public.notifications for select to authenticated using(school_id=private.current_school_id() and (user_id is null or user_id=auth.uid()) and private.has_role(array['admin','leadership','teacher']));
create policy notifications_update on public.notifications for update to authenticated using(school_id=private.current_school_id() and user_id=auth.uid()) with check(school_id=private.current_school_id() and user_id=auth.uid());

-- Critical attendance writes run atomically and verify class scope on the server.
create or replace function public.save_attendance(p_session_id uuid,p_records jsonb,p_complete boolean default false,p_reason text default '')
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
declare s public.attendance_sessions%rowtype; rec jsonb; sid uuid; new_status text; old_status text; student_total integer; record_total integer; open_total integer; actor uuid:=auth.uid();
begin
  select * into s from public.attendance_sessions where id=p_session_id and school_id=private.current_school_id();
  if not found or not private.can_access_class(s.class_id) then raise exception 'Anwesenheitsliste nicht gefunden'; end if;
  if s.status='completed' and not private.has_role(array['admin','leadership']) then raise exception 'Abgeschlossene Listen dürfen nur von der Schulleitung korrigiert werden'; end if;
  for rec in select * from jsonb_array_elements(p_records) loop
    sid:=(rec->>'studentId')::uuid; new_status:=rec->>'status';
    if new_status not in ('present','excused','unexcused','late','unchecked') or not exists(select 1 from public.students where id=sid and class_id=s.class_id and school_id=s.school_id and active) then raise exception 'Ungültiger Anwesenheitsstatus oder Schüler'; end if;
    select status into old_status from public.attendance_records where session_id=s.id and student_id=sid;
    insert into public.attendance_records(session_id,student_id,status,recorded_by) values(s.id,sid,new_status,actor)
      on conflict(session_id,student_id) do update set status=excluded.status,recorded_by=excluded.recorded_by,updated_at=now();
    if old_status is distinct from new_status then insert into public.audit_logs(school_id,user_id,action,entity,entity_id,old_value,new_value) values(s.school_id,actor,'attendance_changed','attendance_record',s.id||':'||sid,case when old_status is null then null else jsonb_build_object('status',old_status) end,jsonb_build_object('status',new_status,'reason',left(coalesce(p_reason,''),300))); end if;
  end loop;
  if p_complete then
    select count(*) into student_total from public.students where class_id=s.class_id and active;
    select count(*),count(*) filter(where status='unchecked') into record_total,open_total from public.attendance_records where session_id=s.id;
    if record_total<>student_total or open_total>0 then raise exception 'Die Liste enthält noch nicht kontrollierte Einträge'; end if;
    update public.attendance_sessions set status='completed' where id=s.id;
    insert into public.audit_logs(school_id,user_id,action,entity,entity_id,old_value,new_value) values(s.school_id,actor,'completed','attendance_session',s.id::text,jsonb_build_object('status',s.status),jsonb_build_object('status','completed'));
  end if;
  return jsonb_build_object('ok',true);
end $$;
revoke all on function public.save_attendance(uuid,jsonb,boolean,text) from public,anon;
grant execute on function public.save_attendance(uuid,jsonb,boolean,text) to authenticated;

-- Fictional demo school data only. After creating the first Auth account, assign it an admin profile in SQL Editor (see README).
insert into public.schools(id,name,address,school_year,timezone) values('11111111-1111-4111-8111-111111111111','Schule an der Ruhraue','Essen','2026/2027','Europe/Berlin') on conflict(id) do nothing;
insert into public.subjects(school_id,name) select '11111111-1111-4111-8111-111111111111',n from unnest(array['Mathematik','Deutsch','Englisch','Biologie','Geschichte']) n on conflict(school_id,name) do nothing;
insert into public.classes(id,school_id,name,room) values
 ('11111111-1111-4111-8111-111111111101','11111111-1111-4111-8111-111111111111','5a','R. 12'),
 ('11111111-1111-4111-8111-111111111102','11111111-1111-4111-8111-111111111111','5b','R. 14'),
 ('11111111-1111-4111-8111-111111111103','11111111-1111-4111-8111-111111111111','6a','R. 21'),
 ('11111111-1111-4111-8111-111111111104','11111111-1111-4111-8111-111111111111','7a','R. 23'),
 ('11111111-1111-4111-8111-111111111105','11111111-1111-4111-8111-111111111111','8a','R. 31'),
 ('11111111-1111-4111-8111-111111111106','11111111-1111-4111-8111-111111111111','9a','R. 33'),
 ('11111111-1111-4111-8111-111111111107','11111111-1111-4111-8111-111111111111','10a','R. 41') on conflict(id) do nothing;
insert into public.students(school_id,first_name,last_name,student_code,class_id)
select '11111111-1111-4111-8111-111111111111',n.first_name,n.last_name,'DEMO-'||c.name||'-'||lpad(n.idx::text,2,'0'),c.id
from public.classes c cross join (values (1,'Lena','Hoffmann'),(2,'Ben','Fischer'),(3,'Mia','Schneider'),(4,'Noah','Weber'),(5,'Emma','Wagner'),(6,'Paul','Becker'),(7,'Sofia','Schulz'),(8,'Elias','Hoffmann'),(9,'Lea','Koch'),(10,'Leon','Bauer'),(11,'Amira','Richter'),(12,'Finn','Klein'),(13,'Hannah','Wolf'),(14,'Oskar','Neumann'),(15,'Mila','Schwarz')) as n(idx,first_name,last_name)
where c.school_id='11111111-1111-4111-8111-111111111111' on conflict(school_id,student_code) do nothing;

-- One-time setup after creating an Auth user in Authentication > Users:
-- insert into public.profiles(id,school_id,name,email,role)
-- select id,'11111111-1111-4111-8111-111111111111','School Admin',email,'admin'
-- from auth.users where email='YOUR-ADMIN-EMAIL';
