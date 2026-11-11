-- Extended SchoolPresence modules: schedules, rooms, holidays, substitutions,
-- historical class membership, absence detail and persistent notifications.
create table public.school_years (
  id uuid primary key default gen_random_uuid(), school_id uuid not null references public.schools(id),
  name text not null, starts_on date not null, ends_on date not null, active boolean not null default false,
  check(ends_on>starts_on), unique(school_id,name)
);
create unique index school_year_one_active on public.school_years(school_id) where active;
create table public.holidays (
  id uuid primary key default gen_random_uuid(), school_id uuid not null references public.schools(id),
  name text not null, starts_on date not null, ends_on date not null, school_year_id uuid references public.school_years(id),
  check(ends_on>=starts_on)
);
create table public.rooms (
  id uuid primary key default gen_random_uuid(), school_id uuid not null references public.schools(id),
  name text not null, capacity integer check(capacity is null or capacity>0), active boolean not null default true,
  unique(school_id,name)
);
create table public.class_memberships (
  id uuid primary key default gen_random_uuid(), school_id uuid not null references public.schools(id),
  student_id uuid not null references public.students(id), class_id uuid not null references public.classes(id),
  starts_on date not null default current_date, ends_on date, check(ends_on is null or ends_on>=starts_on)
);
create unique index class_membership_one_current on public.class_memberships(student_id) where ends_on is null;
create index class_membership_history on public.class_memberships(school_id,student_id,starts_on desc);
create table public.timetable_slots (
  id uuid primary key default gen_random_uuid(), school_id uuid not null references public.schools(id),
  class_id uuid not null references public.classes(id), weekday integer not null check(weekday between 1 and 5),
  period integer not null check(period between 1 and 20), subject_id uuid not null references public.subjects(id),
  teacher_id uuid references public.profiles(id), room_id uuid references public.rooms(id),
  starts_at time, ends_at time, school_year_id uuid references public.school_years(id),
  check(starts_at is null or ends_at is null or ends_at>starts_at), unique nulls not distinct(class_id,weekday,period,school_year_id)
);
create index timetable_teacher_idx on public.timetable_slots(school_id,teacher_id,weekday,period);
create index timetable_room_idx on public.timetable_slots(school_id,room_id,weekday,period);
create table public.substitutions (
  id uuid primary key default gen_random_uuid(), school_id uuid not null references public.schools(id),
  class_id uuid not null references public.classes(id), substitution_date date not null,
  period integer not null check(period between 1 and 20), subject_id uuid references public.subjects(id),
  original_teacher_id uuid references public.profiles(id), substitute_teacher_id uuid not null references public.profiles(id),
  room_id uuid references public.rooms(id), note text not null default '', created_by uuid not null references public.profiles(id),
  created_at timestamptz not null default now(), unique(class_id,substitution_date,period)
);
create index substitutions_teacher_day on public.substitutions(school_id,substitute_teacher_id,substitution_date);
create table public.absence_details (
  id uuid primary key default gen_random_uuid(), school_id uuid not null references public.schools(id),
  attendance_record_id uuid not null unique references public.attendance_records(id) on delete cascade,
  note text not null default '', reviewed_by uuid references public.profiles(id), reviewed_at timestamptz,
  created_at timestamptz not null default now()
);
alter table public.notifications add column entity_type text;
alter table public.notifications add column entity_id text;
insert into public.school_years(school_id,name,starts_on,ends_on,active)
select id,school_year,'2026-08-01','2027-07-31',true from public.schools on conflict(school_id,name) do nothing;
insert into public.rooms(school_id,name)
select school_id,room from public.classes where room<>'' on conflict(school_id,name) do nothing;
alter table public.classes alter column school_year drop default;
create or replace function private.set_class_school_year() returns trigger language plpgsql security definer set search_path=public,private,pg_temp as $$
begin
 if new.school_year is null or trim(new.school_year)='' then select school_year into new.school_year from public.schools where id=new.school_id; end if;
 return new;
end $$;
create trigger classes_set_school_year before insert on public.classes for each row execute function private.set_class_school_year();

create or replace function private.can_access_attendance(target uuid) returns boolean
language sql stable security definer set search_path=public,private,pg_temp as $$
select exists(select 1 from public.attendance_sessions a join public.schools sc on sc.id=a.school_id
  where a.id=target and a.school_id=private.current_school_id() and
    (private.has_role(array['admin','leadership']) or exists(select 1 from public.classes c where c.id=a.class_id and c.teacher_id=auth.uid()) or
      exists(select 1 from public.substitutions v where v.class_id=a.class_id and v.substitution_date=a.session_date and v.period=a.period and v.substitute_teacher_id=auth.uid() and a.session_date=(now() at time zone sc.timezone)::date)))
$$;
revoke all on function private.can_access_attendance(uuid) from public,anon;
grant execute on function private.can_access_attendance(uuid) to authenticated;
create or replace function private.can_access_class(target uuid) returns boolean
language sql stable security definer set search_path=public,private,pg_temp as $$
select exists(select 1 from public.classes c where c.id=target and c.school_id=private.current_school_id() and c.active and
  (private.has_role(array['admin','leadership']) or c.teacher_id=auth.uid()))
$$;
drop policy sessions_read on public.attendance_sessions;
create policy sessions_read on public.attendance_sessions for select to authenticated using(school_id=private.current_school_id() and private.can_access_attendance(id));
drop policy sessions_create on public.attendance_sessions;
create policy sessions_create on public.attendance_sessions for insert to authenticated with check(school_id=private.current_school_id() and status='open' and (private.can_access_class(class_id) or exists(select 1 from public.substitutions v join public.schools sc on sc.id=v.school_id where v.class_id=attendance_sessions.class_id and v.substitute_teacher_id=auth.uid() and v.substitution_date=attendance_sessions.session_date and v.period=attendance_sessions.period and v.substitution_date=(now() at time zone sc.timezone)::date)) and (private.has_role(array['admin','leadership']) or teacher_id=auth.uid()));
drop policy classes_read on public.classes;
create policy classes_read on public.classes for select to authenticated using(school_id=private.current_school_id() and (private.has_role(array['admin','leadership']) or teacher_id=auth.uid() or exists(select 1 from public.substitutions v join public.schools sc on sc.id=v.school_id where v.class_id=classes.id and v.substitute_teacher_id=auth.uid() and v.substitution_date>=(now() at time zone sc.timezone)::date)));
drop policy students_read on public.students;
create policy students_read on public.students for select to authenticated using(school_id=private.current_school_id() and ((private.has_role(array['admin','leadership']) or exists(select 1 from public.classes c where c.id=students.class_id and c.teacher_id=auth.uid())) or exists(select 1 from public.attendance_sessions a where a.class_id=students.class_id and a.school_id=students.school_id and private.can_access_attendance(a.id))));
drop policy records_read on public.attendance_records;
create policy records_read on public.attendance_records for select to authenticated using(private.can_access_attendance(session_id));

alter table public.school_years enable row level security;
alter table public.holidays enable row level security;
alter table public.rooms enable row level security;
alter table public.class_memberships enable row level security;
alter table public.timetable_slots enable row level security;
alter table public.substitutions enable row level security;
alter table public.absence_details enable row level security;
grant select,insert,update,delete on public.school_years,public.holidays,public.rooms,public.class_memberships,public.timetable_slots,public.substitutions,public.absence_details to authenticated;
revoke all on public.school_years,public.holidays,public.rooms,public.class_memberships,public.timetable_slots,public.substitutions,public.absence_details from anon;

create policy school_year_read on public.school_years for select to authenticated using(school_id=private.current_school_id());
create policy school_year_admin on public.school_years for all to authenticated using(school_id=private.current_school_id() and private.has_role(array['admin','leadership'])) with check(school_id=private.current_school_id() and private.has_role(array['admin','leadership']));
create policy holiday_read on public.holidays for select to authenticated using(school_id=private.current_school_id());
create policy holiday_admin on public.holidays for all to authenticated using(school_id=private.current_school_id() and private.has_role(array['admin','leadership'])) with check(school_id=private.current_school_id() and private.has_role(array['admin','leadership']));
create policy rooms_read on public.rooms for select to authenticated using(school_id=private.current_school_id());
create policy rooms_admin on public.rooms for all to authenticated using(school_id=private.current_school_id() and private.has_role(array['admin','leadership'])) with check(school_id=private.current_school_id() and private.has_role(array['admin','leadership']));
create policy membership_read on public.class_memberships for select to authenticated using(school_id=private.current_school_id() and private.has_role(array['admin','leadership']));
create policy membership_admin on public.class_memberships for all to authenticated using(school_id=private.current_school_id() and private.has_role(array['admin','leadership'])) with check(school_id=private.current_school_id() and private.has_role(array['admin','leadership']));
create policy timetable_read on public.timetable_slots for select to authenticated using(school_id=private.current_school_id() and (private.has_role(array['admin','leadership']) or teacher_id=auth.uid() or private.can_access_class(class_id)));
create policy substitution_read on public.substitutions for select to authenticated using(school_id=private.current_school_id() and (private.has_role(array['admin','leadership']) or original_teacher_id=auth.uid() or substitute_teacher_id=auth.uid()));
create policy substitution_admin on public.substitutions for all to authenticated using(school_id=private.current_school_id() and private.has_role(array['admin','leadership'])) with check(school_id=private.current_school_id() and private.has_role(array['admin','leadership']));
create policy absence_detail_read on public.absence_details for select to authenticated using(school_id=private.current_school_id() and private.has_role(array['admin','leadership']));
create policy absence_detail_write on public.absence_details for all to authenticated using(school_id=private.current_school_id() and private.has_role(array['admin','leadership'])) with check(school_id=private.current_school_id() and private.has_role(array['admin','leadership']));
create policy notification_create on public.notifications for insert to authenticated with check(school_id=private.current_school_id() and private.has_role(array['admin','leadership']));
drop policy notifications_update on public.notifications;
revoke update on public.notifications from authenticated;

create or replace function public.mark_notification_read(p_notification_id uuid) returns jsonb
language plpgsql security definer set search_path=public,private,pg_temp as $$
begin
 update public.notifications set read=true where id=p_notification_id and school_id=private.current_school_id() and user_id=auth.uid();
 if not found then raise exception 'Benachrichtigung nicht gefunden'; end if;
 return jsonb_build_object('ok',true);
end $$;
create or replace function public.mark_my_notifications_read() returns jsonb
language plpgsql security definer set search_path=public,private,pg_temp as $$
begin
 update public.notifications set read=true where school_id=private.current_school_id() and user_id=auth.uid() and not read;
 return jsonb_build_object('ok',true);
end $$;
revoke all on function public.mark_notification_read(uuid) from public,anon;
revoke all on function public.mark_my_notifications_read() from public,anon;
grant execute on function public.mark_notification_read(uuid),public.mark_my_notifications_read() to authenticated;

create or replace function public.save_attendance(p_session_id uuid,p_records jsonb,p_complete boolean default false,p_reason text default '')
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
declare s public.attendance_sessions%rowtype; rec jsonb; sid uuid; new_status text; old_status text; student_total integer; record_total integer; open_total integer; actor uuid:=auth.uid();
begin
  select * into s from public.attendance_sessions where id=p_session_id and school_id=private.current_school_id();
  if not found or not private.can_access_attendance(s.id) then raise exception 'Anwesenheitsliste nicht gefunden'; end if;
  if s.status='completed' and not private.has_role(array['admin','leadership']) then raise exception 'Abgeschlossene Listen dürfen nur von der Schulleitung korrigiert werden'; end if;
  for rec in select * from jsonb_array_elements(p_records) loop
    sid:=(rec->>'studentId')::uuid; new_status:=rec->>'status';
    if new_status not in ('present','excused','unexcused','late','unchecked') or not exists(select 1 from public.class_memberships m where m.student_id=sid and m.class_id=s.class_id and m.school_id=s.school_id and m.starts_on<=s.session_date and (m.ends_on is null or m.ends_on>=s.session_date)) then raise exception 'Ungültiger Anwesenheitsstatus oder Schüler'; end if;
    select status into old_status from public.attendance_records where session_id=s.id and student_id=sid;
    if s.status='completed' and old_status is distinct from new_status and trim(coalesce(p_reason,''))='' then raise exception 'Für eine Korrektur abgeschlossener Listen ist ein Änderungsgrund erforderlich'; end if;
    insert into public.attendance_records(session_id,student_id,status,recorded_by) values(s.id,sid,new_status,actor)
      on conflict(session_id,student_id) do update set status=excluded.status,recorded_by=excluded.recorded_by,updated_at=now();
    if old_status is distinct from new_status then insert into public.audit_logs(school_id,user_id,action,entity,entity_id,old_value,new_value) values(s.school_id,actor,'attendance_changed','attendance_record',s.id||':'||sid,case when old_status is null then null else jsonb_build_object('status',old_status) end,jsonb_build_object('status',new_status,'reason',left(coalesce(p_reason,''),300))); end if;
  end loop;
  if p_complete then
    select count(*) into student_total from public.class_memberships m where m.class_id=s.class_id and m.school_id=s.school_id and m.starts_on<=s.session_date and (m.ends_on is null or m.ends_on>=s.session_date);
    select count(*),count(*) filter(where status='unchecked') into record_total,open_total from public.attendance_records where session_id=s.id;
    if record_total<>student_total or open_total>0 then raise exception 'Die Liste enthält noch nicht kontrollierte Einträge'; end if;
    update public.attendance_sessions set status='completed' where id=s.id;
    insert into public.audit_logs(school_id,user_id,action,entity,entity_id,old_value,new_value) values(s.school_id,actor,'completed','attendance_session',s.id::text,jsonb_build_object('status',s.status),jsonb_build_object('status','completed'));
  end if;
  return jsonb_build_object('ok',true);
end $$;
revoke all on function public.save_attendance(uuid,jsonb,boolean,text) from public,anon;
grant execute on function public.save_attendance(uuid,jsonb,boolean,text) to authenticated;

create or replace function public.attendance_roster(p_session_id uuid)
returns table(student_id uuid,first_name text,last_name text,student_code text,status text,updated_at timestamptz)
language plpgsql stable security definer set search_path=public,private,pg_temp as $$
declare s public.attendance_sessions%rowtype;
begin
 select * into s from public.attendance_sessions where id=p_session_id and school_id=private.current_school_id();
 if not found or not private.can_access_attendance(s.id) then raise exception 'Anwesenheitsliste nicht gefunden'; end if;
 return query select st.id,st.first_name,st.last_name,st.student_code,coalesce(r.status,'unchecked'),r.updated_at
 from public.class_memberships m join public.students st on st.id=m.student_id
 left join public.attendance_records r on r.student_id=st.id and r.session_id=s.id
 where m.school_id=s.school_id and m.class_id=s.class_id and m.starts_on<=s.session_date and (m.ends_on is null or m.ends_on>=s.session_date)
 order by st.last_name,st.first_name;
end $$;
revoke all on function public.attendance_roster(uuid) from public,anon;
grant execute on function public.attendance_roster(uuid) to authenticated;

create or replace function public.save_timetable_slot(p_slot_id uuid,p_class_id uuid,p_weekday integer,p_period integer,p_subject_id uuid,p_teacher_id uuid,p_room_id uuid,p_starts_at time,p_ends_at time)
returns uuid language plpgsql security definer set search_path=public,private,pg_temp as $$
declare sid uuid:=coalesce(p_slot_id,gen_random_uuid()); school uuid:=private.current_school_id(); active_year uuid;
begin
 if not private.has_role(array['admin','leadership']) then raise exception 'Keine Berechtigung'; end if;
 select id into active_year from public.school_years where school_id=school and active limit 1;
 if not exists(select 1 from public.classes where id=p_class_id and school_id=school) or not exists(select 1 from public.subjects where id=p_subject_id and school_id=school) then raise exception 'Klasse oder Fach nicht gefunden'; end if;
 if p_teacher_id is not null and not exists(select 1 from public.profiles where id=p_teacher_id and school_id=school and role='teacher' and active) then raise exception 'Lehrkraft ungültig'; end if;
 if p_room_id is not null and not exists(select 1 from public.rooms where id=p_room_id and school_id=school and active) then raise exception 'Raum ungültig'; end if;
 perform pg_advisory_xact_lock(hashtextextended(school::text||p_weekday::text||p_period::text,0));
 if exists(select 1 from public.timetable_slots x where x.id<>sid and x.school_id=school and x.school_year_id is not distinct from active_year and x.weekday=p_weekday and x.period=p_period and (x.class_id=p_class_id or (p_teacher_id is not null and x.teacher_id=p_teacher_id) or (p_room_id is not null and x.room_id=p_room_id))) then raise exception 'Zeitkonflikt: Klasse, Lehrkraft oder Raum ist bereits belegt'; end if;
 insert into public.timetable_slots(id,school_id,class_id,weekday,period,subject_id,teacher_id,room_id,starts_at,ends_at,school_year_id) values(sid,school,p_class_id,p_weekday,p_period,p_subject_id,p_teacher_id,p_room_id,p_starts_at,p_ends_at,active_year)
 on conflict(id) do update set class_id=excluded.class_id,weekday=excluded.weekday,period=excluded.period,subject_id=excluded.subject_id,teacher_id=excluded.teacher_id,room_id=excluded.room_id,starts_at=excluded.starts_at,ends_at=excluded.ends_at,school_year_id=excluded.school_year_id;
 insert into public.audit_logs(school_id,user_id,action,entity,entity_id,new_value) values(school,auth.uid(),case when p_slot_id is null then 'created' else 'updated' end,'timetable_slot',sid::text,jsonb_build_object('class_id',p_class_id,'weekday',p_weekday,'period',p_period));
 return sid;
end $$;
revoke all on function public.save_timetable_slot(uuid,uuid,integer,integer,uuid,uuid,uuid,time,time) from public,anon;
grant execute on function public.save_timetable_slot(uuid,uuid,integer,integer,uuid,uuid,uuid,time,time) to authenticated;

create or replace function public.create_substitution(p_class_id uuid,p_date date,p_period integer,p_subject_id uuid,p_original_teacher_id uuid,p_substitute_teacher_id uuid,p_room_id uuid,p_note text)
returns uuid language plpgsql security definer set search_path=public,private,pg_temp as $$
declare sid uuid:=gen_random_uuid(); school uuid:=private.current_school_id(); cls public.classes%rowtype; substitute_name text; date_year uuid;
begin
 if not private.has_role(array['admin','leadership']) then raise exception 'Keine Berechtigung'; end if;
 select * into cls from public.classes where id=p_class_id and school_id=school;
 if not found or not exists(select 1 from public.profiles where id=p_substitute_teacher_id and school_id=school and role='teacher' and active) then raise exception 'Klasse oder Vertretungslehrkraft ungültig'; end if;
 if p_substitute_teacher_id=coalesce(p_original_teacher_id,cls.teacher_id) then raise exception 'Die Vertretungslehrkraft muss eine andere Person sein'; end if;
 if p_subject_id is not null and not exists(select 1 from public.subjects where id=p_subject_id and school_id=school) then raise exception 'Fach ungültig'; end if;
 if p_room_id is not null and not exists(select 1 from public.rooms where id=p_room_id and school_id=school and active) then raise exception 'Raum ungültig'; end if;
 select name into substitute_name from public.profiles where id=p_substitute_teacher_id;
 select id into date_year from public.school_years where school_id=school and p_date between starts_on and ends_on limit 1;
 if exists(select 1 from public.substitutions v where v.school_id=school and v.substitution_date=p_date and v.period=p_period and (v.substitute_teacher_id=p_substitute_teacher_id or (p_room_id is not null and v.room_id=p_room_id))) then raise exception 'Zeitkonflikt mit einer anderen Vertretung'; end if;
 if exists(select 1 from public.timetable_slots t where t.school_id=school and t.school_year_id is not distinct from date_year and t.weekday=extract(isodow from p_date)::integer and t.period=p_period and ((t.teacher_id=p_substitute_teacher_id and t.class_id<>p_class_id) or (p_room_id is not null and t.room_id=p_room_id and t.class_id<>p_class_id))) then raise exception 'Zeitkonflikt mit dem Stundenplan der Lehrkraft oder des Raums'; end if;
 insert into public.substitutions(id,school_id,class_id,substitution_date,period,subject_id,original_teacher_id,substitute_teacher_id,room_id,note,created_by) values(sid,school,p_class_id,p_date,p_period,p_subject_id,coalesce(p_original_teacher_id,cls.teacher_id),p_substitute_teacher_id,p_room_id,left(coalesce(p_note,''),300),auth.uid());
 insert into public.notifications(school_id,user_id,title,body,entity_type,entity_id)
 select school,recipient,case when recipient=p_substitute_teacher_id then 'Neue Vertretungsstunde' else 'Vertretung eingetragen' end,cls.name||' · '||p_period||'. Stunde am '||to_char(p_date,'DD.MM.YYYY'),'substitution',sid::text
 from (values (p_substitute_teacher_id),(coalesce(p_original_teacher_id,cls.teacher_id))) as recipients(recipient) where recipient is not null;
 insert into public.audit_logs(school_id,user_id,action,entity,entity_id,new_value) values(school,auth.uid(),'created','substitution',sid::text,jsonb_build_object('class_id',p_class_id,'date',p_date,'period',p_period,'substitute_teacher_id',p_substitute_teacher_id));
 return sid;
end $$;
revoke all on function public.create_substitution(uuid,date,integer,uuid,uuid,uuid,uuid,text) from public,anon;
grant execute on function public.create_substitution(uuid,date,integer,uuid,uuid,uuid,uuid,text) to authenticated;

create or replace function public.review_absence(p_record_id uuid,p_note text default '') returns jsonb
language plpgsql security definer set search_path=public,private,pg_temp as $$
declare school uuid:=private.current_school_id();
begin
 if not private.has_role(array['admin','leadership']) then raise exception 'Keine Berechtigung'; end if;
 if not exists(select 1 from public.attendance_records r join public.attendance_sessions s on s.id=r.session_id where r.id=p_record_id and s.school_id=school) then raise exception 'Fehlzeit nicht gefunden'; end if;
 insert into public.absence_details(school_id,attendance_record_id,note,reviewed_by,reviewed_at) values(school,p_record_id,left(coalesce(p_note,''),1000),auth.uid(),now())
 on conflict(attendance_record_id) do update set note=excluded.note,reviewed_by=excluded.reviewed_by,reviewed_at=now();
 insert into public.audit_logs(school_id,user_id,action,entity,entity_id,new_value) values(school,auth.uid(),'reviewed','absence_detail',p_record_id::text,jsonb_build_object('reviewed',true));
 return jsonb_build_object('ok',true);
end $$;
revoke all on function public.review_absence(uuid,text) from public,anon;
grant execute on function public.review_absence(uuid,text) to authenticated;

create or replace function private.track_class_membership() returns trigger language plpgsql security definer set search_path=public,private,pg_temp as $$
begin
 if tg_op='INSERT' and new.class_id is not null and new.active then insert into public.class_memberships(school_id,student_id,class_id) values(new.school_id,new.id,new.class_id);
 elsif tg_op='UPDATE' and new.class_id is distinct from old.class_id then
   update public.class_memberships set ends_on=current_date-1 where student_id=new.id and ends_on is null;
   if new.class_id is not null and new.active then insert into public.class_memberships(school_id,student_id,class_id) values(new.school_id,new.id,new.class_id); end if;
 elsif tg_op='UPDATE' and old.active and not new.active then
   update public.class_memberships set ends_on=current_date where student_id=new.id and ends_on is null;
 elsif tg_op='UPDATE' and not old.active and new.active and new.class_id is not null then
   update public.class_memberships set ends_on=current_date-1 where student_id=new.id and ends_on=current_date;
   insert into public.class_memberships(school_id,student_id,class_id) values(new.school_id,new.id,new.class_id);
 end if;
 return new;
end $$;
drop trigger if exists students_track_membership on public.students;
create trigger students_track_membership after insert or update of class_id,active on public.students for each row execute function private.track_class_membership();
insert into public.class_memberships(school_id,student_id,class_id)
select s.school_id,s.id,s.class_id from public.students s where s.class_id is not null and not exists(select 1 from public.class_memberships m where m.student_id=s.id and m.ends_on is null);

create or replace function private.notify_attendance_created() returns trigger language plpgsql security definer set search_path=public,private,pg_temp as $$
declare cls text;
begin
 select name into cls from public.classes where id=new.class_id;
 insert into public.notifications(school_id,user_id,title,body,entity_type,entity_id)
 select new.school_id,p.id,'Offene Anwesenheitskontrolle',cls||' · '||new.period||'. Stunde am '||to_char(new.session_date,'DD.MM.YYYY'),'attendance',new.id::text
 from public.profiles p where p.school_id=new.school_id and p.active and (p.role in ('admin','leadership') or p.id=new.teacher_id)
 on conflict do nothing;
 return new;
end $$;
create trigger attendance_created_notification after insert on public.attendance_sessions for each row execute function private.notify_attendance_created();

create or replace function private.audit_school_row() returns trigger language plpgsql security definer set search_path=public,private,pg_temp as $$
declare old_json jsonb; new_json jsonb; school uuid; target text; event text;
begin
 if tg_op='INSERT' then old_json:=null;new_json:=to_jsonb(new);event:='created';
 else old_json:=to_jsonb(old);new_json:=to_jsonb(new);event:='updated'; end if;
 if tg_table_name='schools' then school:=new.id; else school:=new.school_id; end if;
 target:=new.id::text;
 if tg_table_name='classes' and tg_op='UPDATE' and old.active and not new.active then event:='archived'; end if;
 insert into public.audit_logs(school_id,user_id,action,entity,entity_id,old_value,new_value) values(school,auth.uid(),event,tg_table_name,target,old_json,new_json);
 return new;
end $$;
create trigger audit_class_changes after insert or update on public.classes for each row execute function private.audit_school_row();
create trigger audit_student_changes after insert or update on public.students for each row execute function private.audit_school_row();
create trigger audit_school_changes after update on public.schools for each row execute function private.audit_school_row();

create or replace function private.notify_school_record() returns trigger language plpgsql security definer set search_path=public,private,pg_temp as $$
declare class_name text; recipients uuid[]; title_text text; body_text text; entity_name text; entity_id_value text;
begin
 if tg_table_name='classes' then
   class_name:=new.name;entity_name:='class';entity_id_value:=new.id::text;title_text:='Klasse geändert';body_text:=class_name||' wurde aktualisiert';
   select array_agg(p.id) into recipients from public.profiles p where p.school_id=new.school_id and p.active and (p.role in ('admin','leadership') or p.id=new.teacher_id);
 else
   select name into class_name from public.classes where id=new.class_id;entity_name:='student';entity_id_value:=new.id::text;title_text:='Schülerzuordnung geändert';body_text:='Eine Zuordnung in Klasse '||coalesce(class_name,'')||' wurde aktualisiert';
   select array_agg(p.id) into recipients from public.profiles p where p.school_id=new.school_id and p.active and (p.role in ('admin','leadership') or p.id=(select teacher_id from public.classes where id=new.class_id));
 end if;
 if recipients is not null then insert into public.notifications(school_id,user_id,title,body,entity_type,entity_id) select new.school_id,x,title_text,body_text,entity_name,entity_id_value from unnest(recipients) x; end if;
 return new;
end $$;
create trigger notify_class_changes after insert or update on public.classes for each row execute function private.notify_school_record();
create trigger notify_student_changes after insert or update on public.students for each row execute function private.notify_school_record();

create or replace function private.notify_attendance_completed() returns trigger language plpgsql security definer set search_path=public,private,pg_temp as $$
declare class_name text; recipients uuid[];
begin
 if old.status is distinct from new.status and new.status='completed' then
  select name into class_name from public.classes where id=new.class_id;
  select array_agg(p.id) into recipients from public.profiles p where p.school_id=new.school_id and p.active and (p.role in ('admin','leadership') or p.id=new.teacher_id);
  if recipients is not null then insert into public.notifications(school_id,user_id,title,body,entity_type,entity_id) select new.school_id,x,'Anwesenheitsliste abgeschlossen',class_name||' · '||new.period||'. Stunde am '||to_char(new.session_date,'DD.MM.YYYY'),'attendance_completed',new.id::text from unnest(recipients) x; end if;
 end if;
 return new;
end $$;
create trigger attendance_completed_notification after update of status on public.attendance_sessions for each row execute function private.notify_attendance_completed();

-- Dedupe notification events and allow the scoped RPCs to create them.
grant insert on public.notifications to authenticated;

create or replace function public.log_export(p_report_type text) returns jsonb
language plpgsql security definer set search_path=public,private,pg_temp as $$
declare school uuid:=private.current_school_id();
begin
 if school is null or not private.has_role(array['admin','leadership','teacher']) then raise exception 'Keine Berechtigung'; end if;
 insert into public.audit_logs(school_id,user_id,action,entity,entity_id,new_value) values(school,auth.uid(),'exported','report',left(p_report_type,80),jsonb_build_object('type',left(p_report_type,80)));
 return jsonb_build_object('ok',true);
end $$;
revoke all on function public.log_export(text) from public,anon;
grant execute on function public.log_export(text) to authenticated;

create or replace function public.save_school_year(p_name text,p_starts_on date,p_ends_on date) returns uuid
language plpgsql security definer set search_path=public,private,pg_temp as $$
declare school uuid:=private.current_school_id(); sid uuid:=gen_random_uuid();
begin
 if not private.has_role(array['admin','leadership']) then raise exception 'Keine Berechtigung'; end if;
 if trim(coalesce(p_name,''))='' or p_starts_on is null or p_ends_on is null or p_ends_on<=p_starts_on then raise exception 'Bezeichnung oder Zeitraum des Schuljahres ist ungültig'; end if;
 update public.school_years set active=false where school_id=school and active;
 insert into public.school_years(id,school_id,name,starts_on,ends_on,active) values(sid,school,left(trim(p_name),30),p_starts_on,p_ends_on,true);
 update public.schools set school_year=left(trim(p_name),30) where id=school;
 insert into public.audit_logs(school_id,user_id,action,entity,entity_id,new_value) values(school,auth.uid(),'created','school_year',sid::text,jsonb_build_object('name',left(trim(p_name),30),'starts_on',p_starts_on,'ends_on',p_ends_on));
 return sid;
end $$;
revoke all on function public.save_school_year(text,date,date) from public,anon;
grant execute on function public.save_school_year(text,date,date) to authenticated;

create or replace function public.log_security_event(p_action text) returns jsonb
language plpgsql security definer set search_path=public,private,pg_temp as $$
declare school uuid:=private.current_school_id(); action_name text:=left(coalesce(p_action,''),40);
begin
 if school is null or action_name not in ('login','logout','password_changed') then raise exception 'Ungültige Sicherheitsaktion'; end if;
 insert into public.audit_logs(school_id,user_id,action,entity,entity_id) values(school,auth.uid(),action_name,'user',auth.uid()::text);
 return jsonb_build_object('ok',true);
end $$;
revoke all on function public.log_security_event(text) from public,anon;
grant execute on function public.log_security_event(text) to authenticated;

create or replace view public.teachers with (security_invoker=true) as
select id,school_id,name,email,active,created_at from public.profiles where role='teacher';
create or replace view public.absence_records with (security_invoker=true) as
select r.id,r.session_id,r.student_id,r.status,r.recorded_by,r.updated_at,s.school_id,s.class_id,s.session_date,s.period,s.subject_id
from public.attendance_records r join public.attendance_sessions s on s.id=r.session_id where r.status in ('excused','unexcused','late');
grant select on public.teachers,public.absence_records to authenticated;

create or replace function public.update_my_profile(p_name text) returns jsonb
language plpgsql security definer set search_path=public,private,pg_temp as $$
declare school uuid:=private.current_school_id(); old_name text; new_name text:=left(trim(coalesce(p_name,'')),100);
begin
 if school is null or new_name='' then raise exception 'Name fehlt'; end if;
 select name into old_name from public.profiles where id=auth.uid() and school_id=school and active;
 if not found then raise exception 'Profil nicht gefunden'; end if;
 update public.profiles set name=new_name where id=auth.uid();
 insert into public.audit_logs(school_id,user_id,action,entity,entity_id,old_value,new_value) values(school,auth.uid(),'updated','profile',auth.uid()::text,jsonb_build_object('name',old_name),jsonb_build_object('name',new_name));
 return jsonb_build_object('ok',true);
end $$;
revoke all on function public.update_my_profile(text) from public,anon;
grant execute on function public.update_my_profile(text) to authenticated;
