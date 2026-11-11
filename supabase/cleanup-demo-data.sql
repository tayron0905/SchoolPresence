-- Entfernt ausschließlich die ursprünglich mit SchoolPresence angelegten Demo-Schüler und Demo-Klassen.
-- Keep the school audit trigger safe when updating the school row.
create or replace function private.audit_school_row() returns trigger language plpgsql security definer set search_path=public,private,pg_temp as $$
declare old_json jsonb; new_json jsonb; school uuid; target text; event text;
begin
 if tg_op='INSERT' then old_json:=null;new_json:=to_jsonb(new);event:='created';
 else old_json:=to_jsonb(old);new_json:=to_jsonb(new);event:='updated'; end if;
 if tg_table_name='schools' then school:=new.id; else school:=new.school_id; end if;
 target:=new.id::text;
 if tg_table_name='classes' and tg_op='UPDATE' then
   if old.active and not new.active then event:='archived'; end if;
 end if;
 insert into public.audit_logs(school_id,user_id,action,entity,entity_id,old_value,new_value) values(school,auth.uid(),event,tg_table_name,target,old_json,new_json);
 return new;
end $$;

-- Reale Schüler in einer Beispielklasse bleiben erhalten; deren Klasse und Unterrichtsdaten werden nicht entfernt.
begin;

create temporary table _schoolpresence_demo_classes on commit drop as
select id
from public.classes
where school_id = '11111111-1111-4111-8111-111111111111'::uuid
  and id in (
    '11111111-1111-4111-8111-111111111101'::uuid,
    '11111111-1111-4111-8111-111111111102'::uuid,
    '11111111-1111-4111-8111-111111111103'::uuid,
    '11111111-1111-4111-8111-111111111104'::uuid,
    '11111111-1111-4111-8111-111111111105'::uuid,
    '11111111-1111-4111-8111-111111111106'::uuid,
    '11111111-1111-4111-8111-111111111107'::uuid
  );

delete from public.class_memberships m
using public.students s
where m.student_id = s.id and s.student_code like 'DEMO-%';

delete from public.attendance_records r
using public.students s
where r.student_id = s.id and s.student_code like 'DEMO-%';

delete from public.students where student_code like 'DEMO-%';

delete from public.class_memberships m
using _schoolpresence_demo_classes c
where m.class_id = c.id
  and not exists (select 1 from public.students s where s.class_id = c.id);

delete from public.substitutions x
using _schoolpresence_demo_classes c
where x.class_id = c.id
  and not exists (select 1 from public.students s where s.class_id = c.id);

delete from public.timetable_slots x
using _schoolpresence_demo_classes c
where x.class_id = c.id
  and not exists (select 1 from public.students s where s.class_id = c.id);

delete from public.attendance_sessions x
using _schoolpresence_demo_classes c
where x.class_id = c.id
  and not exists (select 1 from public.students s where s.class_id = c.id);

delete from public.classes c
using _schoolpresence_demo_classes d
where c.id = d.id
  and not exists (select 1 from public.students s where s.class_id = c.id)
  and not exists (select 1 from public.attendance_sessions a where a.class_id = c.id)
  and not exists (select 1 from public.timetable_slots t where t.class_id = c.id)
  and not exists (select 1 from public.substitutions x where x.class_id = c.id);

update public.schools
set name = 'Meine Schule', address = ''
where id = '11111111-1111-4111-8111-111111111111'::uuid
  and name = 'Schule an der Ruhraue';

commit;
