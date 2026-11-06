const {test}=require('node:test');const assert=require('node:assert/strict');const fs=require('node:fs');const vm=require('node:vm');const path=require('node:path');const root=path.join(__dirname,'..');const {validate}=require('../route.js');
test('all public scripts compile and no privileged keys are shipped',()=>{
 for(const file of ['config.js','user.js','admin.js','route.js']){const text=fs.readFileSync(path.join(root,file),'utf8');new vm.Script(text);assert.doesNotMatch(text,/sb_secret_[A-Za-z0-9_-]{10,}|-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----|gh[pousr]_[A-Za-z0-9]{30,}/);for(const token of text.match(/eyJ[A-Za-z0-9_.-]+/g)||[]){const payload=JSON.parse(Buffer.from(token.split('.')[1],'base64url'));assert.notEqual(payload.role,'service_role')}}
});
test('route validation rejects invented verification and malformed coordinates',()=>{const point={address:'Alamat masukan',lat:null,lng:null,verified:false,source:''};assert.equal(validate([point])[0].verified,false);for(const patch of [{verified:true},{lat:0},{lat:91,lng:10},{lat:'0',lng:10},{lat:0,lng:0,verified:true},{lat:NaN,lng:0}])assert.throws(()=>validate([{...point,...patch}]));assert.equal(validate([{...point,lat:0,lng:0,verified:true,source:'Konfirmasi penerima'}])[0].lat,0);assert.throws(()=>validate(Array(31).fill(point)))});

test('Admin-reported journey position requires verification and is unique',()=>{
 const base={address:'Alamat yang dikonfirmasi Admin',lat:-2.99,lng:104.76,verified:true,source:'Konfirmasi Admin'};
 assert.equal(validate([{...base,current:true}])[0].current,true);
 assert.equal(validate([{...base}])[0].current,false);
 assert.throws(()=>validate([{...base,current:true},{...base,current:true}]),/satu posisi/);
 assert.throws(()=>validate([{...base,verified:false,current:true}]),/terverifikasi/);
 assert.throws(()=>validate([{...base,current:'true'}]),/tidak valid/);
 assert.throws(()=>validate([{...base,current:true,lat:null,lng:null}]),/terverifikasi/);
});

test('Admin route controls exist and are wired to the order update flow',()=>{
 const html=fs.readFileSync(path.join(root,'admin.html'),'utf8');
 const js=fs.readFileSync(path.join(root,'admin.js'),'utf8');
 for(const id of ['startTripBtn','arrivedBtn','changeLocationBtn']){
  assert.match(html,new RegExp('id="'+id+'"'));
  assert.ok(js.includes("$('"+id+"').addEventListener('click'"),'Missing click handler for '+id);
 }
 assert.match(js,/admin_update_order/);
 assert.match(js,/p_expected_updated_at:selectedVersion/);
});
test('User page 3 displays route before details and receives realtime updates',()=>{
 const html=fs.readFileSync(path.join(root,'index.html'),'utf8');
 const js=fs.readFileSync(path.join(root,'user.js'),'utf8');
 const page3=html.slice(html.indexOf('id="page3"'),html.indexOf('id="page4"'));
 assert.ok(page3.indexOf('id="routeView"')<page3.indexOf('Rincian Pesanan'));
 assert.match(js,/postgres_changes/);
 assert.match(js,/refreshDetail/);
});
