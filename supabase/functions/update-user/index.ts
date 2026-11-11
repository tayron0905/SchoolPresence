import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};
const response = (body: unknown, status = 200) => Response.json(body, { status, headers: cors });

Deno.serve(async req => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  if (req.method !== 'POST') return response({ error: 'Method not allowed' }, 405);

  const url = Deno.env.get('SUPABASE_URL')!;
  const publicKey = Deno.env.get('SUPABASE_ANON_KEY')!;
  let secret = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  try { secret = JSON.parse(Deno.env.get('SUPABASE_SECRET_KEYS') ?? '{}').default ?? secret; } catch { /* legacy fallback */ }
  if (!secret) return response({ error: 'Benutzerverwaltung ist nicht konfiguriert.' }, 500);

  const caller = createClient(url, publicKey, {
    global: { headers: { Authorization: req.headers.get('Authorization') ?? '' } },
    auth: { persistSession: false },
  });
  const admin = createClient(url, secret, { auth: { persistSession: false } });
  const { data: { user }, error: authError } = await caller.auth.getUser();
  if (authError || !user) return response({ error: 'Anmeldung erforderlich.' }, 401);

  const { data: actor } = await admin.from('profiles').select('school_id,role,active').eq('id', user.id).single();
  if (!actor?.active || actor.role !== 'admin') return response({ error: 'Keine Berechtigung.' }, 403);

  let input: { id?: string; role?: string; active?: boolean; action?: string };
  try { input = await req.json(); } catch { return response({ error: 'Ungültige Anfrage.' }, 400); }
  if (!input.id) return response({ error: 'Benutzer fehlt.' }, 400);
  if (input.action && input.action !== 'delete') return response({ error: 'Aktion ungültig.' }, 400);

  const { data: target } = await admin.from('profiles')
    .select('id,name,email,role,active')
    .eq('id', input.id)
    .eq('school_id', actor.school_id)
    .single();
  if (!target) return response({ error: 'Benutzer nicht gefunden.' }, 404);

  if (input.action === 'delete') {
    if (target.id === user.id) return response({ error: 'Das eigene Admin-Konto kann nicht gelöscht werden.' }, 400);

    const updates = [
      admin.from('classes').update({ teacher_id: null }).eq('teacher_id', target.id),
      admin.from('timetable_slots').update({ teacher_id: null }).eq('teacher_id', target.id),
      admin.from('attendance_sessions').update({ teacher_id: null }).eq('teacher_id', target.id),
      admin.from('attendance_records').update({ recorded_by: null }).eq('recorded_by', target.id),
      admin.from('absence_details').update({ reviewed_by: null }).eq('reviewed_by', target.id),
      admin.from('audit_logs').update({ user_id: null }).eq('user_id', target.id),
      admin.from('substitutions').update({ original_teacher_id: null }).eq('original_teacher_id', target.id),
      admin.from('substitutions').update({ substitute_teacher_id: null }).eq('substitute_teacher_id', target.id),
      admin.from('substitutions').update({ created_by: null }).eq('created_by', target.id),
      admin.from('notifications').delete().eq('user_id', target.id),
    ];
    const results = await Promise.all(updates);
    if (results.some(result => result.error)) return response({ error: 'Benutzerverweise konnten nicht bereinigt werden.' }, 500);

    const { error: deleteError } = await admin.auth.admin.deleteUser(target.id);
    if (deleteError) return response({ error: 'Benutzerkonto konnte nicht gelöscht werden.' }, 409);
    await admin.from('audit_logs').insert({
      school_id: actor.school_id,
      user_id: user.id,
      action: 'deleted',
      entity: 'user',
      entity_id: target.id,
      old_value: { name: target.name, email: target.email, role: target.role, active: target.active },
    });
    return response({ ok: true });
  }

  if (!['admin', 'leadership', 'teacher'].includes(String(input.role)) || typeof input.active !== 'boolean') {
    return response({ error: 'Rolle oder Status ungültig.' }, 400);
  }
  if (input.id === user.id && (!input.active || input.role !== 'admin')) {
    return response({ error: 'Das eigene Admin-Konto kann hier nicht deaktiviert oder herabgestuft werden.' }, 400);
  }
  const { error: authUpdateError } = await admin.auth.admin.updateUserById(target.id, {
    ban_duration: input.active ? 'none' : '876000h',
  });
  if (authUpdateError) return response({ error: 'Anmeldestatus konnte nicht aktualisiert werden.' }, 400);
  const { error: profileError } = await admin.from('profiles').update({ role: input.role, active: input.active }).eq('id', target.id);
  if (profileError) return response({ error: 'Profil konnte nicht aktualisiert werden.' }, 500);
  await admin.from('audit_logs').insert({
    school_id: actor.school_id,
    user_id: user.id,
    action: 'updated',
    entity: 'user',
    entity_id: target.id,
    old_value: { role: target.role, active: target.active },
    new_value: { role: input.role, active: input.active },
  });
  return response({ ok: true });
});
