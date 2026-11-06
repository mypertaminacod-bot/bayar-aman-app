const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const root = path.join(__dirname, '..');
const {validate} = require('../route.js');
test('inline JavaScript compiles and public code contains no privileged key', () => {
 for (const file of ['index.html','admin.html']) {
  const html=fs.readFileSync(path.join(root,file),'utf8');
  for(const [,attrs,code] of html.matchAll(/<script([^>]*)>([\s\S]*?)<\/script>/g)) if(!attrs.includes('src=')) new vm.Script(code);
  assert.doesNotMatch(html,/sb_secret_[A-Za-z0-9]+/);
  for(const token of html.match(/eyJ[A-Za-z0-9_.-]+/g)||[]) {
   const payload=JSON.parse(Buffer.from(token.split('.')[1],'base64url'));assert.notEqual(payload.role,'service_role');
  }
 }
});
test('route validation rejects invented verification and malformed coordinates',()=>{
 const point={address:'Alamat masukan',lat:null,lng:null,verified:false,source:''};
 assert.equal(validate([point])[0].verified,false);
 for(const patch of [{verified:true},{lat:0},{lat:91,lng:10},{lat:'0',lng:10},{lat:0,lng:0,verified:true},{lat:NaN,lng:0}])assert.throws(()=>validate([{...point,...patch}]));
 assert.equal(validate([{...point,lat:0,lng:0,verified:true,source:'Konfirmasi penerima'}])[0].lat,0);
 assert.throws(()=>validate(Array(31).fill(point)));
});
