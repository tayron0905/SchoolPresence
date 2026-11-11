import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const cors = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type', 'Access-Control-Allow-Methods': 'POST, OPTIONS' };
Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  if (req.method !== 'POST') return Response.json({ error: 'Method not allowed' }, { status: 405, headers: cors });
  const url = Deno.env.get('SUPABASE_URL')!;
  const publishable = Deno.env.get('SUPABASE_ANON_KEY')!;
  const secret = Deno.env.get('SUPABASE_SECRET_KEY') ?? Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!secret) return Response.json({ error: 'Secret-Key für die Benutzerverwaltung ist nicht eingerichtet.' }, { status: 500, headers: cors });
  const caller = createClient(url, publishable, { global: { headers: { Authorization: req.headers.get('Authorization') ?? '' } }, auth: { persistSession: false } });
  const admin = createClient(url, secret, { auth: { persistSession: false } });
  const { data: { user }, error: authError } = await caller.auth.getUser();
  if (authError || !user) return Response.json({ error: 'Anmeldung erforderlich.' }, { status: 401, headers: cors });
  const { data: callerProfile } = await admin.from('profiles').select('school_id,role,active').eq('id', user.id).single();
  if (!callerProfile?.active || callerProfile.role !== 'admin') return Response.json({ error: 'Keine Berechtigung.' }, { status: 403, headers: cors });
  let input: {name?:string;email?:string;password?:string;role?:string};
  try { input = await req.json(); } catch { return Response.json({ error: 'Ungültige Anfrage.' }, { status: 400, headers: cors }); }
  const name = String(input.name ?? '').trim(); const email = String(input.email ?? '').trim().toLowerCase(); const password = String(input.password ?? '');
  if (!name || !/^\S+@\S+\.\S+$/.test(email) || password.length < 12 || !['leadership','teacher','student'].includes(String(input.role))) return Response.json({ error: 'Name, gültige E-Mail, Passwort mit mindestens 12 Zeichen und erlaubte Rolle angeben.' }, { status: 400, headers: cors });
  const { data, error } = await admin.auth.admin.createUser({ email, password, email_confirm: true, user_metadata: { name } });
  if (error || !data.user) return Response.json({ error: error?.message ?? 'Benutzer konnte nicht erstellt werden.' }, { status: 400, headers: cors });
  const { error: profileError } = await admin.from('profiles').insert({ id: data.user.id, school_id: callerProfile.school_id, name, email, role: input.role });
  if (profileError) { await admin.auth.admin.deleteUser(data.user.id); return Response.json({ error: 'Profil konnte nicht erstellt werden.' }, { status: 500, headers: cors }); }
  await admin.from('audit_logs').insert({ school_id: callerProfile.school_id, user_id: user.id, action: 'created', entity: 'user', entity_id: data.user.id, new_value: { email, role: input.role } });
  return Response.json({ id: data.user.id }, { headers: cors });
});
