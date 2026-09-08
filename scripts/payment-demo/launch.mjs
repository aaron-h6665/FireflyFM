import {readFileSync} from 'node:fs';
import {execFileSync} from 'node:child_process';
const env=Object.fromEntries(readFileSync('/private/tmp/fireflyfm-payment-demo/local.env','utf8').split('\n').filter(x=>x.includes('=')).map(x=>{const i=x.indexOf('=');return [x.slice(0,i),x.slice(i+1).replace(/^"|"$/g,'')]}));
if(env.API_URL!=='http://127.0.0.1:55421')throw new Error('Only the isolated demo endpoint is allowed');
const app=process.argv[2]||'/private/tmp/firefly-payment-build/Build/Products/Debug-iphonesimulator/FireflyFM.app';
const devices=JSON.parse(execFileSync('xcrun',['simctl','list','devices','available','--json'],{encoding:'utf8'}));
const device=Object.values(devices.devices).flat().find(x=>x.name==='iPhone 17 Pro');
if(!device)throw new Error('Create an iPhone 17 Pro simulator in Xcode first');
if(device.state!=='Booted')execFileSync('xcrun',['simctl','boot',device.udid]);
execFileSync('xcrun',['simctl','bootstatus',device.udid,'-b']);
execFileSync('xcrun',['simctl','install',device.udid,app]);
const bundle=execFileSync('/usr/libexec/PlistBuddy',['-c','Print CFBundleIdentifier',`${app}/Info.plist`],{encoding:'utf8'}).trim();
try{execFileSync('xcrun',['simctl','terminate',device.udid,bundle],{stdio:'ignore'})}catch{}
execFileSync('xcrun',['simctl','launch',device.udid,bundle],{env:{...process.env,SIMCTL_CHILD_FIREFLY_PAYMENT_DEMO:'1',SIMCTL_CHILD_FIREFLY_DEMO_ANON_KEY:env.ANON_KEY},stdio:'inherit'});
execFileSync('open',['-a','Simulator']);
