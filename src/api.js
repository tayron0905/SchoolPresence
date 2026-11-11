import { createClient } from '@supabase/supabase-js';

const url = import.meta.env.VITE_SUPABASE_URL;
const key = import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY;
export const supabaseReady = Boolean(url && key);
export const supabase = supabaseReady ? createClient(url, key, {
  auth: { persistSession: true, storage: window.sessionStorage, autoRefreshToken: true, detectSessionInUrl: true },
}) : null;

const fail = (error) => { if (error) throw new Error(error.message || 'Supabase-Anfrage fehlgeschlagen.'); };
const uid = () => crypto.randomUUID();
const profile = async () => {
  const { data: { user }, error } = await supabase.auth.getUser(); fail(error);
  if (!user) return null;
  const { data, error: e } = await supabase.from('profiles').select('id,school_id,name,email,role,active').eq('id', user.id).single(); fail(e);
  return { id:data.id, schoolId:data.school_id, name:data.name, email:data.email, role:data.role };
};
const query = async (q) => { const {data,error}=await q;fail(error);return data; };
const attendanceSessions = async () => {
  const sessions = await query(supabase.from('attendance_sessions').select('id,school_id,class_id,session_date,period,subject_id,teacher_id,status,classes(name,students(id)),subjects(name),profiles(name),attendance_records(id)').order('session_date',{ascending:false}).order('period'));
  return sessions.map(s=>({ ...s, class_name:s.classes?.name, subject_name:s.subjects?.name, teacher_name:s.profiles?.name, recorded:s.attendance_records?.length||0, total:s.classes?.students?.length||0 }));
};

export async function api(path, options={}) {
  if (!supabaseReady) throw new Error('Supabase ist noch nicht konfiguriert. Bitte VITE_SUPABASE_URL und VITE_SUPABASE_PUBLISHABLE_KEY eintragen.');
  const method=options.method||'GET'; const body=options.body?JSON.parse(options.body):{};
  if(path==='/me') return { user:await profile() };
  if(path==='/login'&&method==='POST') { const {error}=await supabase.auth.signInWithPassword({email:body.email,password:body.password});fail(error);return {user:await profile()}; }
  if(path==='/logout') { const {error}=await supabase.auth.signOut();fail(error);return {ok:true}; }
  if(path==='/bootstrap') {
    const user=await profile(); if(!user)throw new Error('Bitte anmelden.');
    const [school,classes,students,subjects]=await Promise.all([
      query(supabase.from('schools').select('id,name,address,school_year,timezone').eq('id',user.schoolId).single()),
      query(supabase.from('classes').select('*,profiles!classes_teacher_id_fkey(name),students(id)').eq('active',true).order('name')),
      query(supabase.from('students').select('*,classes(name)').eq('active',true).order('last_name')),
      query(supabase.from('subjects').select('*').order('name')),
    ]);
    return {school,classes:classes.map(c=>({...c,teacher_name:c.profiles?.name,student_count:c.students?.length||0})),students:students.map(s=>({...s,class_name:s.classes?.name})),subjects,role:user.role};
  }
  if(path==='/attendance'&&method==='GET') return attendanceSessions();
  const detail=path.match(/^\/attendance\/([^/]+)$/);
  if(detail&&method==='GET'){
    const s=await query(supabase.from('attendance_sessions').select('*,classes(name),subjects(name)').eq('id',detail[1]).single());
    const records=await query(supabase.from('students').select('id,first_name,last_name,student_code,attendance_records(status,updated_at)').eq('attendance_records.session_id',s.id).eq('class_id',s.class_id).eq('active',true).order('last_name'));
    return {session:{...s,class_name:s.classes?.name,subject_name:s.subjects?.name},records:records.map(r=>({student_id:r.id,first_name:r.first_name,last_name:r.last_name,student_code:r.student_code,status:r.attendance_records?.[0]?.status||'unchecked',updated_at:r.attendance_records?.[0]?.updated_at}))};
  }
  if(path==='/attendance'&&method==='POST'){
    const user=await profile();const {data,error}=await supabase.from('attendance_sessions').upsert({id:uid(),school_id:user.schoolId,class_id:body.classId,session_date:body.date,period:Number(body.period),subject_id:body.subjectId||null,teacher_id:user.id,status:'open'},{onConflict:'class_id,session_date,period',ignoreDuplicates:true}).select().maybeSingle();
    if(error)throw new Error(error.message);if(data)return data;
    return await query(supabase.from('attendance_sessions').select('*').eq('class_id',body.classId).eq('session_date',body.date).eq('period',Number(body.period)).single());
  }
  if(detail&&method==='PUT') { const result=await query(supabase.rpc('save_attendance',{p_session_id:detail[1],p_records:body.records,p_complete:Boolean(body.complete),p_reason:String(body.reason||'').slice(0,300)}));return result; }
  if(path==='/classes'&&method==='POST'){const user=await profile();return await query(supabase.from('classes').insert({school_id:user.schoolId,name:body.name,room:body.room||'',teacher_id:body.teacherId||null}).select('id').single());}
  if(path==='/students'&&method==='POST'){const user=await profile();return await query(supabase.from('students').insert({school_id:user.schoolId,first_name:body.firstName,last_name:body.lastName,class_id:body.classId,student_code:`SP-${crypto.randomUUID().slice(0,8).toUpperCase()}`}).select('id').single());}
  if(path==='/audit')return query(supabase.from('audit_logs').select('id,action,entity,entity_id,old_value,new_value,created_at,profiles(name)').order('created_at',{ascending:false}).limit(100)).then(xs=>xs.map(x=>({...x,user_name:x.profiles?.name})));
  if(path==='/admin/users'&&method==='GET')return query(supabase.from('profiles').select('id,name,email,role,active,created_at').order('name'));
  if(path==='/admin/users'&&method==='POST'){const {data,error}=await supabase.functions.invoke('create-user',{body});fail(error);if(data?.error)throw new Error(data.error);return data;}
  if(path==='/settings/school'&&method==='PUT'){const user=await profile();return query(supabase.from('schools').update({name:body.name,address:body.address,school_year:body.schoolYear}).eq('id',user.schoolId));}
  throw new Error(`Aktion ${method} ${path} ist noch nicht verfügbar.`);
}
