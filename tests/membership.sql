-- Disposable database only. auth.users fixture IDs are from sql-bootstrap.sql.
insert into public.bayar_aman_admins values ('00000000-0000-0000-0000-000000000003') on conflict do nothing;
set role authenticated;
select set_config('test.uid','00000000-0000-0000-0000-000000000001',false),set_config('test.jwt','{"is_anonymous":true}',false);
do $$ declare oid text; m jsonb; begin
 oid:=public.bayar_aman_submit_event('{"type":"nomor_pesanan","phone":"081234567890","order_number":"MEMBER-TEST"}');
 perform set_config('test.order_id',oid,false);
 begin
  perform public.bayar_aman_submit_event(jsonb_build_object('type','metode_pembayaran','phone','081234567890','order_number','MEMBER-TEST','order_id',oid,'payment','COD'));
  raise exception 'COD accepted without membership';
 exception when raise_exception then if sqlerrm<>'Keanggotaan aktif diperlukan untuk COD' then raise; end if; end;
 begin
  insert into public.bayar_aman_members(user_id,phone,name,address) values(auth.uid(),'081234567890','Forge','Forge');
  raise exception 'Direct member insert accepted';
 exception when insufficient_privilege then null; end;
 begin
  insert into public.user_data(user_id,data) values(auth.uid(),jsonb_build_object('type','pendaftaran','phone','081234567890','name','Forge','address','Forge','order_id',oid,'order_number','MEMBER-TEST'));
  raise exception 'Direct registration log accepted';
 exception when raise_exception then if sqlerrm<>'Gunakan fungsi pendaftaran anggota' then raise; end if; end;
 m:=public.bayar_aman_register_member('Anggota Uji','081234567890','Alamat Uji','test@example.invalid',oid);
 if m->>'status'<>'active' or (m->>'free_shipping_quota')::int<>3 or (m->>'created')::boolean<>true then raise exception 'Activation failed'; end if;
 m:=public.bayar_aman_register_member('Retry','081234567890','Retry','',oid);
 if (m->>'created')::boolean<>false or (select count(*) from public.user_data where data->>'type'='pendaftaran')<>1 then raise exception 'Duplicate registration'; end if;
 perform public.bayar_aman_submit_event(jsonb_build_object('type','metode_pembayaran','phone','081234567890','order_number','MEMBER-TEST','order_id',oid,'payment','COD'));
 begin
  update public.bayar_aman_members set free_shipping_quota=3;
  raise exception 'Client quota update accepted';
 exception when insufficient_privilege then null; end;
 if public.bayar_aman_my_membership('6281234567890')->>'status'<>'active' then raise exception 'Membership status missing'; end if;
end $$;
reset role;
update public.bayar_aman_members set free_shipping_quota=2 where user_id='00000000-0000-0000-0000-000000000001';
set role authenticated;
do $$ declare m jsonb; begin
 m:=public.bayar_aman_register_member('Retry','081234567890','Retry','',current_setting('test.order_id'));
 if (m->>'free_shipping_quota')::int<>2 then raise exception 'Retry replenished spent quota'; end if;
end $$;
select set_config('test.uid','00000000-0000-0000-0000-000000000002',false);
do $$ declare oid text; begin
 begin perform * from public.bayar_aman_admin_events(0,500);raise exception 'User read Admin events';exception when insufficient_privilege then null;end;
 if (select count(*) from public.bayar_aman_members)<>0 or public.bayar_aman_my_membership('081234567890') is not null then raise exception 'Cross-user member leak'; end if;
 begin
  perform public.bayar_aman_register_member('Foreign','081234567890','Foreign','',current_setting('test.order_id'));
  raise exception 'Foreign order accepted';
 exception when raise_exception then if sqlerrm<>'Pesanan harus milik sesi dan nomor HP ini' then raise; end if; end;
 oid:=public.bayar_aman_submit_event('{"type":"nomor_pesanan","phone":"081234567890","order_number":"OTHER-SESSION"}');
 begin
  perform public.bayar_aman_register_member('Duplicate','081234567890','Duplicate','',oid);
  raise exception 'Cross-session phone duplicate accepted';
 exception when raise_exception then if sqlerrm not like 'Nomor ini sudah terdaftar.%' then raise; end if; end;
 oid:=public.bayar_aman_submit_event('{"type":"nomor_pesanan","phone":"6281234567890","order_number":"PREFIX-ALIAS"}');
 begin
  perform public.bayar_aman_register_member('Alias','6281234567890','Alias','',oid);
  raise exception 'Phone prefix duplicate accepted';
 exception when raise_exception then if sqlerrm not like 'Nomor ini sudah terdaftar.%' then raise; end if; end;
 if (select count(*) from public.bayar_aman_members)<>0 or (select count(*) from public.user_data where data->>'type'='pendaftaran')<>0 then raise exception 'Failed registration left data'; end if;
end $$;
reset role;
-- Inject an event-write failure to verify membership and quota roll back atomically.
create function public.test_registration_failure() returns trigger language plpgsql as $$ begin
 if new.data->>'type'='pendaftaran' and new.data->>'phone'='089999999999' then raise exception 'Injected event failure'; end if;return new;
end $$;
create trigger test_registration_failure before insert on public.user_data for each row execute function public.test_registration_failure();
set role authenticated;
do $$ declare oid text; begin
 oid:=public.bayar_aman_submit_event('{"type":"nomor_pesanan","phone":"089999999999","order_number":"ROLLBACK"}');
 begin
  perform public.bayar_aman_register_member('Rollback','089999999999','Alamat','',oid);
  raise exception 'Injected failure not raised';
 exception when raise_exception then if sqlerrm<>'Injected event failure' then raise; end if; end;
 if (select count(*) from public.bayar_aman_members)<>0 then raise exception 'Partial activation survived'; end if;
end $$;
reset role;
drop trigger test_registration_failure on public.user_data;
drop function public.test_registration_failure();
set role authenticated;
select set_config('test.uid','00000000-0000-0000-0000-000000000003',false),set_config('test.jwt','{"is_anonymous":false}',false);
do $$ begin
 if not exists(select 1 from public.bayar_aman_admin_events(0,500) where data->>'type'='pendaftaran') then raise exception 'Admin events missing'; end if;
 if (select count(*) from public.bayar_aman_members)<>1 then raise exception 'Admin cannot see member'; end if;
 if (select count(*) from public.user_data where data->>'type'='pendaftaran' and data->>'member_status'='active' and data->>'free_shipping_quota'='3')<>1 then raise exception 'Admin activation event missing'; end if;
 begin
  perform public.bayar_aman_register_member('Admin','081234567890','Alamat','',current_setting('test.order_id'));
  raise exception 'Non-anonymous registration accepted';
 exception when insufficient_privilege then null; end;
end $$;
reset role;
set role anon;
do $$ begin
 begin perform public.bayar_aman_register_member('Anon','081234567890','Alamat','','1');raise exception 'No-session registration accepted';exception when insufficient_privilege then null;end;
end $$;
reset role;
select 'PASS: automatic activation, quota, retry, ownership, phone uniqueness, COD gate, forged data denial, Admin event and atomic rollback';
