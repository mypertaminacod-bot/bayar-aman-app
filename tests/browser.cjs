// UI integration with a simulated backend. This DOES NOT verify Supabase RLS or Realtime.
const {chromium} = require('playwright');
const assert = require('node:assert/strict');
const path = require('node:path');
const http = require('node:http');
const fs = require('node:fs');
(async()=>{
 const server=http.createServer((req,res)=>{const file=path.join(__dirname,'..',req.url.slice(1));res.setHeader('Content-Type',file.endsWith('.js')?'application/javascript':'text/html');try{res.end(fs.readFileSync(file))}catch{res.writeHead(404);res.end()}});
 await new Promise(r=>server.listen(0,'127.0.0.1',r));
 const base='http://127.0.0.1:'+server.address().port;
 const browser=await chromium.launch({headless:true,executablePath:process.env.CHROMIUM_PATH||'/usr/bin/chromium',args:['--no-sandbox']});
 try {
 const records=[];let failInsert=false,denyAdmin=false,conflict=false;
 async function setup(name){
  const context=await browser.newContext({viewport:{width:360,height:800}});const page=await context.newPage();const errors=[];page.on('pageerror',e=>errors.push(e.message));
  await page.exposeFunction('backend',async(op,arg)=>{
   if(op==='insert'){if(failInsert)return {error:{message:'Simulated offline'}};const r={...arg,id:String(records.length+1),created_at:new Date().toISOString(),updated_at:new Date().toISOString()};records.push(r);return {data:{id:r.id}};}
   if(op==='read')return {data:records.find(r=>r.id===arg.id&&r.user_id===arg.user_id)||null};
   if(op==='list')return {data:records.slice(arg.start,arg.end+1)};
   if(op==='is_admin')return {data:!denyAdmin};
   if(op==='admin_update_order'){if(conflict)return {error:{message:'Order changed: reload'}};const r=records.find(r=>r.id===arg.p_id);r.data={...r.data,detail_pesanan:arg.p_detail,route:arg.p_route};r.updated_at=new Date().toISOString();return {data:true};}
  });
  await page.route('https://cdn.jsdelivr.net/**',r=>r.fulfill({contentType:'application/javascript',body:`window.supabase={createClient(url,key,options){window.clientOptions=options;let session=${name==='user'?"{user:{id:'user-1',is_anonymous:true}}":"null"};return {auth:{getSession:async()=>({data:{session}}),signInAnonymously:async()=>({data:{user:{id:'user-1'}}}),signInWithPassword:async()=>{session={user:{id:'admin-1'}};return {}},signOut:async()=>{session=null;return {}},onAuthStateChange:cb=>{}},rpc:(name,args)=>window.backend(name,args),removeChannel:async()=>{},channel(){const c={on(event,filter,cb){window.changed=cb;return c},subscribe(cb){cb('SUBSCRIBED');return c}};return c},from(){let payload,filters={};const q={insert(v){payload=v;return q},select(){return q},eq(k,v){filters[k]=v;return q},order(){return q},range(start,end){return window.backend('list',{start,end})},single(){return window.backend('insert',payload)},async maybeSingle(){const r=await window.backend('read',filters);return {data:r.data?{data:r.data.data}:null,error:r.error}}};return q}}}};` }));
  await page.goto(base+'/'+(name==='user'?'index.html':'admin.html'));
  return {page,errors};
 }
 const {page:user,errors:ue}=await setup('user');
 await user.fill('#phone','12');await user.click('#go1');assert.match(await user.textContent('#msg1'),/10–15/);assert.equal(records.length,0);
 await user.fill('#phone','081234567890');failInsert=true;await user.click('#go1');await user.waitForFunction(()=>document.querySelector('#msg1').textContent.includes('belum terkirim'));assert.equal(await user.locator('#page1').isVisible(),true);failInsert=false;
 await user.click('#go1');await user.waitForSelector('#page2.active');await user.fill('#order','TEST-ONLY-001');await user.click('#go2');await user.waitForSelector('#page3.active');assert.match(await user.textContent('#routeView'),/belum tersedia/);
 const {page:admin,errors:ae}=await setup('admin');await admin.fill('#adminEmail','test@example.invalid');await admin.fill('#adminPassword','mock-only');await admin.click('#loginBtn');await admin.waitForSelector('#dashboard:not(.hidden)');await admin.locator('#rows tr').filter({hasText:'nomor_pesanan'}).click();
 for(const [id,value] of Object.entries({dName:'Nama Uji',dPhone:'081234567890',dAddress:'Alamat uji',dPrice:'Rp 100',dStatus:'Menunggu verifikasi',dProduct:'Produk uji'}))await admin.fill('#'+id,value);
 await admin.fill('#routeJson',JSON.stringify([{address:'<img src=x onerror=alert(1)>',lat:null,lng:null,verified:true,source:''}]));await admin.click('#saveBtn');await admin.waitForFunction(()=>document.querySelector('#saveStatus').textContent.includes('memerlukan'));
 await admin.fill('#routeJson',JSON.stringify([{address:'<img src=x onerror=alert(1)>',lat:null,lng:null,verified:false,source:''},{address:'Alamat uji',lat:-6,lng:106,verified:true,source:'Verifikasi manual uji'}]));
 conflict=true;await admin.click('#saveBtn');await admin.waitForFunction(()=>document.querySelector('#saveStatus').textContent.includes('Order changed'));conflict=false;await admin.click('#saveBtn');await admin.waitForFunction(()=>document.querySelector('#saveStatus').textContent.includes('Perubahan tersimpan'));
 await user.evaluate(()=>window.changed());await user.waitForFunction(()=>document.querySelector('#vName').textContent==='Nama Uji');assert.equal(await user.locator('#routeView img').count(),0);assert.match(await user.textContent('#routeView'),/Koordinat belum diverifikasi/);assert.match(await user.textContent('#routeView'),/Koordinat terverifikasi oleh Admin/);
 assert.equal(await user.locator('.route-dot').first().evaluate(e=>getComputedStyle(e).animationDuration),'1s');
 for(const width of [320,360,412]){await user.setViewportSize({width,height:800});assert.equal(await user.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),true);}
 await user.check('input[value="LinkAja"]');await user.click('#go3');await user.waitForSelector('#page4.active');await user.fill('#memberName','Nama Pendaftar');await user.fill('#memberAddress','Alamat pendaftar');await user.fill('#memberEmail','test@example.invalid');await user.click('#go4');await user.waitForFunction(()=>document.querySelector('#msg4').textContent.includes('Pengajuan tersimpan'));assert.match(await user.textContent('#msg4'),/menunggu verifikasi/);
 assert.deepEqual(records.map(r=>r.data.type),['nomor_hp','nomor_pesanan','metode_pembayaran','pendaftaran']);assert.equal(records[3].data.email,'test@example.invalid');assert.equal(records[3].data.order_id,'2');assert.equal(records[3].data.free_shipping_quota,undefined);
 await user.locator('[data-page="3"]').click();await user.check('input[value="COD"]');await user.click('#go3');await user.waitForSelector('#page4.active');
 await admin.click('#logout');assert.equal(await admin.locator('#dashboard').isVisible(),false);assert.equal(await admin.locator('#rows tr').count(),0);assert.equal(await admin.inputValue('#dAddress'),'');
 denyAdmin=true;await admin.fill('#adminEmail','test@example.invalid');await admin.fill('#adminPassword','mock-only');await admin.click('#loginBtn');await admin.waitForFunction(()=>document.querySelector('#loginStatus').textContent.includes('tidak memiliki izin'));assert.equal(await admin.locator('#dashboard').isVisible(),false);
 assert.equal(await user.evaluate(()=>clientOptions.auth.storageKey),'bayar-aman-user');assert.equal(await admin.evaluate(()=>clientOptions.auth.storageKey),'bayar-aman-admin');assert.deepEqual([...ue,...ae],[]);
 console.log('PASS: mock browser flow, both payment methods, persistence payloads, route validation/XSS/blink, Android widths, failed writes/conflict, admin denial/logout, separate sessions. NOT live Supabase E2E.');
 }finally{await browser.close();server.close()}
})().catch(e=>{console.error(e);process.exitCode=1});
