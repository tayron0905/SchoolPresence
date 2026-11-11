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
  const { data: { session }, error: sessionError } = await supabase.auth.getSession(); fail(sessionError);
  if (!session) return null;
  const { data: { user }, error } = await supabase.auth.getUser(); fail(error);
  if (!user) return null;
  const { data, error: e } = await supabase.from('profiles').select('id,school_id,name,email,role,active').eq('id', user.id).single(); fail(e);
  return { id:data.id, schoolId:data.school_id, name:data.name, email:data.email, role:data.role };
};
const query = async (q) => { const {data,error}=await q;fail(error);return data; };
const logSecurityEvent = async action => { try { await supabase.rpc('log_security_event',{p_action:action}); } catch { /* authentication must not fail solely because audit storage is temporarily unavailable */ } };
const attendanceSessions = async () => {
  const sessions = await query(supabase.from('attendance_sessions').select('id,school_id,class_id,session_date,period,subject_id,teacher_id,status,classes(name,students(id)),subjects(name),profiles(name),attendance_records(id,status)').order('session_date',{ascending:false}).order('period'));
  return sessions.map(s=>{const counts={present:0,excused:0,unexcused:0,late:0,unchecked:0};(s.attendance_records||[]).forEach(r=>counts[r.status]++);return { ...s, class_name:s.classes?.name, subject_name:s.subjects?.name, teacher_name:s.profiles?.name, recorded:s.attendance_records?.length||0, total:s.classes?.students?.length||0, counts };});
};

export async function api(path, options={}) {
  if (!supabaseReady) throw new Error('Supabase ist noch nicht konfiguriert. Bitte VITE_SUPABASE_URL und VITE_SUPABASE_PUBLISHABLE_KEY eintragen.');
  const method=options.method||'GET'; const body=options.body?JSON.parse(options.body):{}; const parsed=new URL(path,'https://schoolpresence.invalid'); path=parsed.pathname;
  if(path==='/me') return { user:await profile() };
  if(path==='/login'&&method==='POST') { const {error}=await supabase.auth.signInWithPassword({email:body.email,password:body.password});fail(error);await logSecurityEvent('login');return {user:await profile()}; }
  if(path==='/logout') { await logSecurityEvent('logout');const {error}=await supabase.auth.signOut();fail(error);return {ok:true}; }
  if(path==='/password-reset'&&method==='POST'){const {error}=await supabase.auth.resetPasswordForEmail(body.email,{redirectTo:window.location.origin+window.location.pathname});fail(error);return {ok:true};}
  if(path==='/password'&&method==='PUT'){const {error}=await supabase.auth.updateUser({password:body.password});fail(error);await logSecurityEvent('password_changed');return {ok:true};}
  if(path==='/profile'&&method==='PUT')return query(supabase.rpc('update_my_profile',{p_name:body.name}));
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
    const records=await query(supabase.rpc('attendance_roster',{p_session_id:s.id}));
    return {session:{...s,class_name:s.classes?.name,subject_name:s.subjects?.name},records};
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
  const adminUser=path.match(/^\/admin\/users\/([^/]+)$/);
  if(adminUser&&method==='PUT'){const {data,error}=await supabase.functions.invoke('update-user',{body:{...body,id:adminUser[1]}});fail(error);if(data?.error)throw new Error(data.error);return data;}
  if(adminUser&&method==='DELETE'){const {data,error}=await supabase.functions.invoke('update-user',{body:{id:adminUser[1],action:'delete'}});fail(error);if(data?.error)throw new Error(data.error);return data;}
  if(path==='/settings/school'&&method==='PUT'){const user=await profile();return query(supabase.from('schools').update({name:body.name,address:body.address,school_year:body.schoolYear}).eq('id',user.schoolId));}
  if(path==='/absences'&&method==='GET'){
    let q=supabase.from('attendance_records').select('id,status,updated_at,student_id,students!inner(first_name,last_name,student_code,class_id,classes(name)),attendance_sessions!inner(id,session_date,period,subject_id,subjects(name)),absence_details(note,reviewed_at)').in('status',['excused','unexcused','late']).order('updated_at',{ascending:false});
    if(parsed.searchParams.has('classId'))q=q.eq('students.class_id',parsed.searchParams.get('classId'));
    if(parsed.searchParams.has('from'))q=q.gte('attendance_sessions.session_date',parsed.searchParams.get('from'));
    if(parsed.searchParams.has('to'))q=q.lte('attendance_sessions.session_date',parsed.searchParams.get('to'));
    const rows=await query(q);return rows.map(r=>({...r,first_name:r.students?.first_name,last_name:r.students?.last_name,student_code:r.students?.student_code,class_name:r.students?.classes?.name,session_date:r.attendance_sessions?.session_date,period:r.attendance_sessions?.period,subject_name:r.attendance_sessions?.subjects?.name,detail:Array.isArray(r.absence_details)?r.absence_details[0]||null:r.absence_details||null}));
  }
  const absenceDetail=path.match(/^\/absences\/([^/]+)$/);
  if(absenceDetail&&method==='PUT')return query(supabase.rpc('review_absence',{p_record_id:absenceDetail[1],p_note:body.note||''}));
  if(path==='/timetable'&&method==='GET'){
    let q=supabase.from('timetable_slots').select('*,classes(name),subjects(name),profiles!timetable_slots_teacher_id_fkey(name),rooms(name)').order('weekday').order('period');
    const {data:year,error:yearError}=await supabase.from('school_years').select('id').eq('active',true).maybeSingle();if(yearError)throw new Error(yearError.message);if(year?.id)q=q.eq('school_year_id',year.id);
    if(parsed.searchParams.has('classId'))q=q.eq('class_id',parsed.searchParams.get('classId'));
    if(parsed.searchParams.has('teacherId'))q=q.eq('teacher_id',parsed.searchParams.get('teacherId'));
    return (await query(q)).map(x=>({...x,class_name:x.classes?.name,subject_name:x.subjects?.name,teacher_name:x.profiles?.name,room_name:x.rooms?.name}));
  }
  if(path==='/timetable'&&method==='POST')return query(supabase.rpc('save_timetable_slot',{p_slot_id:body.id||null,p_class_id:body.classId,p_weekday:Number(body.weekday),p_period:Number(body.period),p_subject_id:body.subjectId,p_teacher_id:body.teacherId||null,p_room_id:body.roomId||null,p_starts_at:body.startsAt||null,p_ends_at:body.endsAt||null}));
  if(path==='/substitutions'&&method==='GET'){
    let q=supabase.from('substitutions').select('*,classes(name),subjects(name),profiles!substitutions_substitute_teacher_id_fkey(name),rooms(name)').order('substitution_date',{ascending:false}).order('period');
    if(parsed.searchParams.has('from'))q=q.gte('substitution_date',parsed.searchParams.get('from'));
    if(parsed.searchParams.has('to'))q=q.lte('substitution_date',parsed.searchParams.get('to'));
    return (await query(q)).map(x=>({...x,class_name:x.classes?.name,subject_name:x.subjects?.name,substitute_name:x.profiles?.name,room_name:x.rooms?.name}));
  }
  if(path==='/substitutions'&&method==='POST')return query(supabase.rpc('create_substitution',{p_class_id:body.classId,p_date:body.date,p_period:Number(body.period),p_subject_id:body.subjectId||null,p_original_teacher_id:body.originalTeacherId||null,p_substitute_teacher_id:body.substituteTeacherId,p_room_id:body.roomId||null,p_note:body.note||''}));
  const substituteAttendance=path.match(/^\/substitutions\/([^/]+)\/attendance$/);
  if(substituteAttendance&&method==='POST'){
    const sub=await query(supabase.from('substitutions').select('*').eq('id',substituteAttendance[1]).single());
    const {data:session,error}=await supabase.from('attendance_sessions').upsert({school_id:sub.school_id,class_id:sub.class_id,session_date:sub.substitution_date,period:sub.period,subject_id:sub.subject_id,teacher_id:(await profile()).id,status:'open'},{onConflict:'class_id,session_date,period',ignoreDuplicates:true}).select().maybeSingle();fail(error);
    return session||await query(supabase.from('attendance_sessions').select('*').eq('class_id',sub.class_id).eq('session_date',sub.substitution_date).eq('period',sub.period).single());
  }
  if(path==='/notifications'&&method==='GET')return query(supabase.from('notifications').select('*').order('created_at',{ascending:false}).limit(100));
  if(path==='/notifications/read-all'&&method==='PUT')return query(supabase.rpc('mark_my_notifications_read'));
  const notification=path.match(/^\/notifications\/([^/]+)$/);
  if(notification&&method==='PUT')return query(supabase.rpc('mark_notification_read',{p_notification_id:notification[1]}));
  if(path==='/teachers'&&method==='GET')return query(supabase.from('profiles').select('id,name,email').eq('role','teacher').eq('active',true).order('name'));
  if(path==='/rooms'&&method==='GET')return query(supabase.from('rooms').select('id,name,capacity').eq('active',true).order('name'));
  if(path==='/school-years'&&method==='GET')return query(supabase.from('school_years').select('*').order('starts_on',{ascending:false}));
  if(path==='/school-years'&&method==='POST')return query(supabase.rpc('save_school_year',{p_name:body.name,p_starts_on:body.startsOn,p_ends_on:body.endsOn}));
  if(path==='/holidays'&&method==='GET')return query(supabase.from('holidays').select('*').order('starts_on'));
  if(path==='/holidays'&&method==='POST'){const user=await profile();return query(supabase.from('holidays').insert({school_id:user.schoolId,name:body.name,starts_on:body.startsOn,ends_on:body.endsOn}).select('id').single());}
  if(path==='/rooms'&&method==='POST'){const user=await profile();return query(supabase.from('rooms').insert({school_id:user.schoolId,name:body.name,capacity:body.capacity?Number(body.capacity):null}).select('id').single());}
  if(path==='/rooms'&&method==='DELETE'){return query(supabase.from('rooms').update({active:false}).eq('id',body.id));}
  if(path==='/audit/export'&&method==='POST')return query(supabase.rpc('log_export',{p_report_type:body.type||'Bericht'}));
  const klass=path.match(/^\/classes\/([^/]+)$/);
  if(klass&&method==='PUT')return query(supabase.from('classes').update({name:body.name,room:body.room,teacher_id:body.teacherId||null,school_year:body.schoolYear}).eq('id',klass[1]));
  if(klass&&method==='DELETE')return query(supabase.from('classes').update({active:false}).eq('id',klass[1]));
  const student=path.match(/^\/students\/([^/]+)$/);
  if(student&&method==='GET'){
    const s=await query(supabase.from('students').select('*,classes(name)').eq('id',student[1]).single());
    const attendance=await query(supabase.from('attendance_records').select('id,status,updated_at,attendance_sessions!inner(session_date,period,subjects(name))').eq('student_id',student[1]).order('updated_at',{ascending:false}).limit(100));
    return {...s,class_name:s.classes?.name,attendance:attendance.map(r=>({...r,session_date:r.attendance_sessions?.session_date,period:r.attendance_sessions?.period,subject_name:r.attendance_sessions?.subjects?.name}))};
  }
  if(student&&method==='PUT')return query(supabase.from('students').update({first_name:body.firstName,last_name:body.lastName,class_id:body.classId,active:body.active??true}).eq('id',student[1]));
  const history=path.match(/^\/students\/([^/]+)\/history$/);
  if(history&&method==='GET')return query(supabase.from('class_memberships').select('id,class_id,starts_on,ends_on,classes(name)').eq('student_id',history[1]).order('starts_on',{ascending:false}));
  throw new Error(`Aktion ${method} ${path} ist noch nicht verfügbar.`);
}
