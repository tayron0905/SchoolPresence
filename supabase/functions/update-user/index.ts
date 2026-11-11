import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const cors={'Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'authorization, x-client-info, apikey, content-type','Access-Control-Allow-Methods':'POST, OPTIONS'};
Deno.serve(async req=>{
  if(req.method==='OPTIONS')return new Response('ok',{headers:cors});
  if(req.method!=='POST')return Response.json({error:'Method not allowed'},{status:405,headers:cors});
  const url=Deno.env.get('SUPABASE_URL')!;const publicKey=Deno.env.get('SUPABASE_ANON_KEY')!;let secret=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');try{secret=JSON.parse(Deno.env.get('SUPABASE_SECRET_KEYS')??'{}').default??secret}catch{/* keep legacy key fallback */}
  if(!secret)return Response.json({error:'Benutzerverwaltung ist nicht konfiguriert.'},{status:500,headers:cors});
  const caller=createClient(url,publicKey,{global:{headers:{Authorization:req.headers.get('Authorization')??''}},auth:{persistSession:false}});const admin=createClient(url,secret,{auth:{persistSession:false}});
  const {data:{user},error}=await caller.auth.getUser();if(error||!user)return Response.json({error:'Anmeldung erforderlich.'},{status:401,headers:cors});
  const {data:actor}=await admin.from('profiles').select('school_id,role,active').eq('id',user.id).single();if(!actor?.active||actor.role!=='admin')return Response.json({error:'Keine Berechtigung.'},{status:403,headers:cors});
  let input:{id?:string;role?:string;active?:boolean};try{input=await req.json()}catch{return Response.json({error:'Ungültige Anfrage.'},{status:400,headers:cors})}
  if(!input.id||!['admin','leadership','teacher'].includes(String(input.role))||typeof input.active!=='boolean')return Response.json({error:'Rolle oder Status ungültig.'},{status:400,headers:cors});
  if(input.id===user.id&&(!input.active||input.role!=='admin'))return Response.json({error:'Das eigene Admin-Konto kann hier nicht deaktiviert oder herabgestuft werden.'},{status:400,headers:cors});
  const {data:target}=await admin.from('profiles').select('id,role,active,email').eq('id',input.id).eq('school_id',actor.school_id).single();if(!target)return Response.json({error:'Benutzer nicht gefunden.'},{status:404,headers:cors});
  const {error:authUpdateError}=await admin.auth.admin.updateUserById(target.id,{ban_duration:input.active?'none':'876000h'});if(authUpdateError)return Response.json({error:'Anmeldestatus konnte nicht aktualisiert werden.'},{status:400,headers:cors});
  const {error:profileError}=await admin.from('profiles').update({role:input.role,active:input.active}).eq('id',target.id);if(profileError)return Response.json({error:'Profil konnte nicht aktualisiert werden.'},{status:500,headers:cors});
  await admin.from('audit_logs').insert({school_id:actor.school_id,user_id:user.id,action:'updated',entity:'user',entity_id:target.id,old_value:{role:target.role,active:target.active},new_value:{role:input.role,active:input.active}});
  return Response.json({ok:true},{headers:cors});
});
