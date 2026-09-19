import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
const password = readFileSync('/private/tmp/fireflyfm-payment-demo/account-password.env', 'utf8').trim();
if (!/^[a-f0-9]{64}$/.test(password)) throw new Error('Run prepare.sh to generate a local demo password');
const env=Object.fromEntries(readFileSync('/private/tmp/fireflyfm-payment-demo/local.env','utf8').split('\n').filter(x=>x.includes('=')).map(x=>{let i=x.indexOf('=');return [x.slice(0,i),x.slice(i+1).replace(/^"|"$/g,'')]}));
const url='http://127.0.0.1:55421';
assert.equal(env.API_URL,url,'Only isolated local demo may be tested');
const key=env.ANON_KEY;
async function req(token,path,body,method=body?'POST':'GET',expected=200){
 const r=await fetch(url+path,{method,headers:{apikey:key,Authorization:`Bearer ${token||key}`,'Content-Type':'application/json'},body:body?JSON.stringify(body):undefined});
 const text=await r.text(); let data;try{data=JSON.parse(text)}catch{data=text}
 if(expected==='error'){assert.ok(!r.ok,`Expected rejection: ${path}`);return data;}
 assert.ok(r.ok,`${path}: HTTP ${r.status} (response body omitted)`);return data;
}
async function login(role){return (await req(null,'/auth/v1/token?grant_type=password',{email:`${role}@payment-demo.example.test`,password})).access_token}
const [parent,director,teacher,other,hq,newDirector]=await Promise.all(['parent-a','director-a','teacher-a','parent-b','hq','new-director'].map(login));
const rpc=(token,name,body,expected)=>req(token,`/rest/v1/rpc/${name}`,body,'POST',expected);
const invoices=await req(parent,'/rest/v1/zelle_invoices?select=*');
const deposit=invoices.find(x=>x.onboarding_requirement_instance_id);
assert.ok(deposit,'Run prepare.sh --reset before verify.mjs');
assert.equal(deposit.is_demo,true);
assert.deepEqual(await req(other,`/rest/v1/zelle_invoices?id=eq.${deposit.id}`),[]);
assert.deepEqual(await req(teacher,`/rest/v1/zelle_invoices?id=eq.${deposit.id}`),[]);
await req(parent,`/rest/v1/zelle_invoices?id=eq.${deposit.id}`,{status:'paid'},'PATCH','error');
const school=deposit.school_id;
const dashboard=()=>rpc(parent,'fetch_my_onboarding_dashboard',{input_school_id:school});
const transfer=async(invoice,scenario)=>(await rpc(parent,'create_zelle_demo_transfer',{input_invoice_id:invoice.id,input_scenario:scenario}))[0];
const submit=async(invoice,reference,idempotency=crypto.randomUUID(),expected)=>rpc(parent,'submit_zelle_payment',{input_invoice_id:invoice.id,input_amount_cents:invoice.amount_due_cents,input_sent_at:new Date().toISOString(),input_confirmation_reference:reference,input_idempotency_key:idempotency},expected);
const review=(submission,decision,note=null,expected)=>rpc(director,'review_zelle_payment',{input_submission_id:submission.id,input_decision:decision,input_reviewer_note:note},expected);
for(const scenario of ['missing','wrong_amount']){
 const bank=await transfer(deposit,scenario);
 const [claim]=await submit(deposit,bank.reference);
 await review(claim,'approved',null,'error');
 await review(claim,'rejected','Please contact the school about this mismatch; do not pay again.');
}
const bank=await transfer(deposit,'matching');
let [claim]=await submit(deposit,bank.reference);
await review(claim,'rejected','Please confirm the date. Do not send money again.');
const history=await req(parent,`/rest/v1/zelle_payment_submissions?invoice_id=eq.${deposit.id}`);
assert.ok(history.some(x=>x.reviewer_note?.includes('confirm the date')));
const idempotency=crypto.randomUUID();
[claim]=await submit(deposit,bank.reference,idempotency);
const [retry]=await submit(deposit,bank.reference,idempotency);assert.equal(retry.id,claim.id);
await rpc(parent,'review_zelle_payment',{input_submission_id:claim.id,input_decision:'approved'},'error');
// Two real authenticated requests race; only one approval may win.
const concurrent=await Promise.allSettled([review(claim,'approved'),review(claim,'approved')]);
assert.equal(concurrent.filter(x=>x.status==='fulfilled').length,1);
let steps=await dashboard();assert.equal(steps.find(x=>x.requirement_type==='payment').status,'approved');
assert.notEqual(steps.find(x=>x.requirement_type==='acknowledgement').status,'approved');
const acknowledgement=steps.find(x=>x.requirement_type==='acknowledgement');
const [form]=await rpc(parent,'submit_assignment_with_payload',{input_assignment_id:acknowledgement.assignment_id,input_structured_payload:{},input_feedback_text:'I acknowledge the demo enrollment form.',input_idempotency_key:crypto.randomUUID()});
await rpc(director,'review_assignment_submission_v2',{input_submission_id:form.id,input_status:'accepted',input_idempotency_key:crypto.randomUUID()});
steps=await dashboard();assert.ok(steps.every(x=>['approved','waived'].includes(x.status)));
const term=invoices.find(x=>!x.onboarding_requirement_instance_id);
await submit(term,bank.reference,crypto.randomUUID(),'error');
const termBank=await transfer(term,'matching');
const [termClaim]=await submit(term,termBank.reference);await review(termClaim,'approved');
const termResult=await req(parent,`/rest/v1/zelle_invoices?id=eq.${term.id}`);assert.equal(termResult[0].status,'paid');
assert.equal(await rpc(teacher,'fetch_child_enrollment_readiness',{input_child_id:'40000000-0000-0000-0000-000000000091'}),'Enrollment ready');
const [directorInvoice]=await req(newDirector,'/rest/v1/zelle_invoices?select=*');
await rpc(newDirector,'void_zelle_invoice',{input_invoice_id:directorInvoice.id,input_reason:'Self approval test'},'error');
await rpc(hq,'void_zelle_invoice',{input_invoice_id:directorInvoice.id,input_reason:'Demo replace test'});
const [replacement]=await rpc(hq,'replace_zelle_invoice',{input_invoice_id:directorInvoice.id,input_reason:'Demo new instructions'});
await rpc(hq,'waive_zelle_requirement',{input_invoice_id:replacement.id,input_reason:'Demo scholarship'});
console.log('PASS: real authenticated demo flow, isolation, failed bank matching, correction, idempotency, concurrent approval, onboarding, later invoice, teacher readiness, HQ replacement and waiver.');
