\set ON_ERROR_STOP on
insert into public.bayar_aman_admins values ('00000000-0000-0000-0000-000000000003');
set role authenticated;
select set_config('test.uid','00000000-0000-0000-0000-000000000001',false),set_config('test.jwt','{"is_anonymous":true}',false);
insert into public.user_data(id,user_id,data) values ('10000000-0000-0000-0000-000000000001',auth.uid(),'{"type":"nomor_pesanan","phone":"081234567890","order_number":"LOCAL-TEST"}');
do $$ begin
 if public.is_admin() then raise exception 'Anonymous user got admin'; end if;
 begin
  insert into public.user_data(user_id,data) values(auth.uid(),'{"type":"nomor_pesanan","phone":"081234567890","order_number":"FORGE","detail_pesanan":{}}');
  raise exception 'Forged detail accepted';
 exception when raise_exception then if sqlerrm not like 'Unexpected field%' then raise; end if; end;
 begin
  insert into public.user_data(user_id,data) values('00000000-0000-0000-0000-000000000002','{"type":"nomor_hp","phone":"081234567890"}');
  raise exception 'Forged owner accepted';
 exception when insufficient_privilege then null; end;
 begin
  update public.user_data set data='{}';raise exception 'Direct update accepted';
 exception when insufficient_privilege then null; end;
 begin
  delete from public.user_data;raise exception 'Direct delete accepted';
 exception when insufficient_privilege then null; end;
 begin
  perform public.admin_update_order('10000000-0000-0000-0000-000000000001',now(),'{}','[]');raise exception 'Non-admin RPC accepted';
 exception when insufficient_privilege then null; end;
end $$;
insert into public.user_data(user_id,data) values(auth.uid(),'{"type":"metode_pembayaran","phone":"081234567890","order_number":"LOCAL-TEST","order_id":"10000000-0000-0000-0000-000000000001","payment":"COD"}');
select set_config('test.uid','00000000-0000-0000-0000-000000000002',false);
do $$ begin
 if (select count(*) from public.user_data)<>0 then raise exception 'Cross-user read leaked'; end if;
 begin
  insert into public.user_data(user_id,data) values(auth.uid(),'{"type":"metode_pembayaran","phone":"081234567890","order_number":"LOCAL-TEST","order_id":"10000000-0000-0000-0000-000000000001","payment":"COD"}');raise exception 'Foreign order accepted';
 exception when raise_exception then if sqlerrm<>'Order must belong to current user' then raise; end if; end;
end $$;
select set_config('test.uid','00000000-0000-0000-0000-000000000003',false),set_config('test.jwt','{"is_anonymous":false}',false);
do $$ declare v timestamptz; detail jsonb := '{"name":"Uji","phone":"081234567890","address":"Alamat uji","price":"Rp 100","status":"Menunggu verifikasi","product":"Uji"}'; begin
 if not public.is_admin() then raise exception 'Admin not authorized'; end if;
 if (select count(*) from public.user_data)<>2 then raise exception 'Admin cannot read all'; end if;
 select updated_at into v from public.user_data where id='10000000-0000-0000-0000-000000000001';
 begin
  perform public.admin_update_order('10000000-0000-0000-0000-000000000001',v,detail,'[{"address":"Alamat","lat":null,"lng":null,"verified":true,"source":""}]');raise exception 'Unverified coordinates accepted';
 exception when raise_exception then if sqlerrm<>'Verified point requires coordinates' then raise; end if; end;
 perform public.admin_update_order('10000000-0000-0000-0000-000000000001',v,detail,'[{"address":"Alamat","lat":0,"lng":0,"verified":true,"source":"Local fixture"}]');
 begin
  perform public.admin_update_order('10000000-0000-0000-0000-000000000001',v,detail,'[]');raise exception 'Stale edit accepted';
 exception when raise_exception then if sqlerrm<>'Order missing or changed: reload before saving' then raise; end if; end;
end $$;
reset role;
delete from public.bayar_aman_admins;
set role authenticated;
do $$ begin if public.is_admin() then raise exception 'Revoked admin retains access'; end if; end $$;
reset role;
set role anon;
do $$ begin
 begin perform count(*) from public.user_data;raise exception 'Unauthenticated read accepted';exception when insufficient_privilege then null;end;
end $$;
reset role;
select 'PASS: local PostgreSQL migration, RLS isolation, owner spoofing, privileged field spoofing, admin RPC, coordinate validation, stale edit, revocation and unauthenticated denial' as result;
