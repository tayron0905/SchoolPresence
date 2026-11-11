-- Run this after both migrations and after confirming the Auth user exists.
-- It grants the admin role only to the supplied initial Auth user UUID.
insert into public.profiles(id,school_id,name,email,role)
select id,
       '11111111-1111-4111-8111-111111111111'::uuid,
       coalesce(nullif(raw_user_meta_data->>'name',''),split_part(email,'@',1)),
       email,
       'admin'
from auth.users
where id='d590819d-0710-4646-9ff5-6f9079d15372'::uuid
on conflict(id) do update set
  school_id=excluded.school_id,
  name=excluded.name,
  email=excluded.email,
  role='admin',
  active=true;
