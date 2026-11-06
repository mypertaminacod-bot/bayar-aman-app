const {PGlite}=require('@electric-sql/pglite');
const fs=require('node:fs');const path=require('node:path');const assert=require('node:assert/strict');
const root=path.join(__dirname,'..');const read=n=>fs.readFileSync(path.join(root,n),'utf8').replace(/^\\set.*$/mg,'');
(async()=>{for(const legacy of [false,true]){const db=new PGlite();try{
 await db.exec(read('tests/sql-bootstrap.sql'));
 if(legacy)await db.exec(read('tests/legacy-schema.sql'));
 await db.exec(read('supabase/migrations/202611060001_secure_user_data.sql'));
 await db.exec(read(legacy?'tests/legacy-assert.sql':'tests/security.sql'));
 // Old fixture rows are unrelated to the membership scenario.
 await db.exec('delete from public.user_data;');
 await db.exec(read('supabase/migrations/202611060002_automatic_membership.sql'));
 await db.exec(read('tests/membership.sql'));
 if(legacy){
  await db.exec("select setval(pg_get_serial_sequence('public.user_data','id'),9007199254740992);set role authenticated;select set_config('test.uid','00000000-0000-0000-0000-000000000001',false),set_config('test.jwt','{\"is_anonymous\":true}',false);");
  const result=await db.query("select public.bayar_aman_submit_event('{\"type\":\"nomor_pesanan\",\"phone\":\"081234567890\",\"order_number\":\"LARGE-ID\"}') as id");
  assert.equal(result.rows[0].id,'9007199254740993');
  await db.query("select public.bayar_aman_submit_event($1::jsonb)",[JSON.stringify({type:'metode_pembayaran',phone:'081234567890',order_number:'LARGE-ID',order_id:result.rows[0].id,payment:'COD'})]);
  await db.exec('reset role;');
  await db.exec("set role authenticated;select set_config('test.uid','00000000-0000-0000-0000-000000000003',false),set_config('test.jwt','{\"is_anonymous\":false}',false);");
  const adminIds=await db.query('select id from public.bayar_aman_admin_events(0,500)');assert(adminIds.rows.some(r=>r.id==='9007199254740993'));
  await db.exec('reset role;');
 }
 // Two queued registrations must return the same event and preserve remaining quota.
 await db.exec("set role authenticated;select set_config('test.uid','00000000-0000-0000-0000-000000000001',false),set_config('test.jwt','{\"is_anonymous\":true}',false);");
 const results=await Promise.all([1,2].map(()=>db.query("select public.bayar_aman_register_member('Retry','081234567890','Alamat','',current_setting('test.order_id')) as member")));
 assert.equal(results[0].rows[0].member.registration_id,results[1].rows[0].member.registration_id);assert.equal(results[0].rows[0].member.free_shipping_quota,2);
 console.log('PASS:',legacy?'legacy bigint incl. > MAX_SAFE_INTEGER':'fresh UUID','migration, RLS, membership transaction, retry/uniqueness, rollback, Admin access, COD gate');
 }finally{await db.close()}}})().catch(e=>{console.error(e);process.exitCode=1});
