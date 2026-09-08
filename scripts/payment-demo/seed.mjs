import { readFileSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
const root = new URL('../../', import.meta.url);
const env = Object.fromEntries(readFileSync('/private/tmp/fireflyfm-payment-demo/local.env','utf8').split('\n').filter(x => x.includes('=')).map(x => { const i=x.indexOf('='); return [x.slice(0,i), x.slice(i+1).replace(/^"|"$/g,'')]; }));
const url='http://127.0.0.1:55421';
if (env.API_URL !== url) throw new Error('Refusing any environment except the dedicated local demo');
const key=env.SERVICE_ROLE_KEY;
if (!key) throw new Error('Local service key unavailable');
const sql = text => execFileSync('docker',['exec','-i','supabase_db_fireflyfm-payment-demo','psql','-U','postgres','-d','postgres','-v','ON_ERROR_STOP=1','-At'],{input:text,encoding:'utf8'});
const roles=['director-a','parent-a','teacher-a','director-b','parent-b','hq','new-director'];
const ids=[];
async function request(path, method='GET', body) {
 const r=await fetch(url+path,{method,headers:{apikey:key,Authorization:`Bearer ${key}`,'Content-Type':'application/json'},body:body?JSON.stringify(body):undefined});
 if(!r.ok) throw new Error(`Local Auth request failed: ${r.status}`);
 return r.json();
}
const existing=await request('/auth/v1/admin/users?page=1&per_page=1000');
for(const role of roles){
 const email=`${role}@payment-demo.example.test`;
 let user=existing.users.find(u=>u.email===email);
 if(!user) user=await request('/auth/v1/admin/users','POST',{email,password:'REMOVED_DEMO_PASSWORD',email_confirm:true,user_metadata:{display_name:`Demo ${role}`}});
 ids.push(user.id);
}
if(sql("SELECT count(*) FROM public.schools WHERE id = '20000000-0000-0000-0000-000000000091'").trim() === '0') {
 const fixture=readFileSync(new URL('supabase/tests/009_zelle_manual_billing.sql',root),'utf8');
 let data=fixture.slice(fixture.indexOf('INSERT INTO public.profiles'),fixture.indexOf('SELECT is(public.get_firefly_schema_version()'));
 roles.forEach((_,i)=>data=data.replaceAll(`10000000-0000-0000-0000-00000000009${i+1}`,ids[i]));
 data=data.replaceAll('August tuition','Second semester tuition');
 sql('BEGIN;\n'+data+'\nCOMMIT;');
 sql(`DO $$ DECLARE t UUID; i UUID; r UUID; m UUID; BEGIN
 SELECT id INTO m FROM public.school_memberships WHERE user_id='${ids[1]}' AND role='parent';
 INSERT INTO public.onboarding_templates(school_id,target_role,name,version,status,created_by)
 VALUES('20000000-0000-0000-0000-000000000091','parent','Demo parent setup',1,'published','${ids[0]}') RETURNING id INTO t;
 INSERT INTO public.onboarding_instances(school_id,membership_id,template_id)
 VALUES('20000000-0000-0000-0000-000000000091',m,t) RETURNING id INTO i;
 INSERT INTO public.onboarding_template_requirements(template_id,position,requirement_type,title,subject_scope,blocks_access,child_record_binding,payment_amount_cents,payment_due_days)
 VALUES(t,0,'payment','Demo enrollment deposit','member',TRUE,'none',100,7) RETURNING id INTO r;
 PERFORM public.create_onboarding_assignment(i,r,NULL);
 INSERT INTO public.onboarding_template_requirements(template_id,position,requirement_type,title,description,subject_scope,blocks_access,child_record_binding)
 VALUES(t,1,'acknowledgement','Demo enrollment acknowledgement','Acknowledge this synthetic enrollment form. No personal documents are needed.','member',TRUE,'none') RETURNING id INTO r;
 PERFORM public.create_onboarding_assignment(i,r,NULL);
 PERFORM public.refresh_onboarding_access(m);
 INSERT INTO public.classrooms(school_id,name) VALUES('20000000-0000-0000-0000-000000000091','Demo classroom') RETURNING id INTO t;
 INSERT INTO public.classroom_children(classroom_id,child_id) VALUES(t,'40000000-0000-0000-0000-000000000091');
 INSERT INTO public.classroom_teachers(classroom_id,teacher_id) VALUES(t,'${ids[2]}');
 END $$;`);
}
console.log('Demo accounts ready. Password: REMOVED_DEMO_PASSWORD');
roles.forEach(role=>console.log(`${role}@payment-demo.example.test`));
console.log('Launch Debug Simulator with FIREFLY_PAYMENT_DEMO=1 and FIREFLY_DEMO_ANON_KEY from /private/tmp/fireflyfm-payment-demo/local.env (ANON_KEY).');
