-- Automatic membership is server-owned and atomic. Apply only after staging review.
begin;
-- Keep the submitted phone visible, but deduplicate common Indonesian prefixes.
create or replace function public.bayar_aman_phone_key(p_phone text) returns text
language sql immutable strict set search_path='' as $$
 select case when p_phone like '08%' then '62'||substr(p_phone,2)
 when p_phone like '00628%' then substr(p_phone,3) else p_phone end;
$$;
revoke all on function public.bayar_aman_phone_key(text) from public,anon;
grant execute on function public.bayar_aman_phone_key(text) to authenticated;
create table public.bayar_aman_members (
 user_id uuid primary key references auth.users(id) on delete cascade,
 phone text not null check(phone ~ '^[0-9]{10,15}$'),
 phone_key text generated always as (public.bayar_aman_phone_key(phone)) stored unique,
 name text not null, address text not null, email text not null default '',
 status text not null default 'active' check(status='active'),
 free_shipping_quota integer not null default 3 check(free_shipping_quota between 0 and 3),
 registration_id text unique,
 activated_at timestamptz not null default clock_timestamp()
);
alter table public.bayar_aman_members enable row level security;
alter table public.bayar_aman_members force row level security;
revoke all on public.bayar_aman_members from public,anon,authenticated;
grant select on public.bayar_aman_members to authenticated;
create policy members_read_owned_or_admin on public.bayar_aman_members for select to authenticated
 using(user_id=(select auth.uid()) or (select public.is_admin()));
create or replace function public.bayar_aman_validate_insert() returns trigger language plpgsql set search_path = '' as $$
declare allowed text[]; k text; t text := new.data->>'type';
begin
 if jsonb_typeof(new.data) is distinct from 'object' or octet_length(new.data::text)>16000 then raise exception 'Invalid data'; end if;
 allowed := array['type','phone','submitted_at'];
 case t
 when 'nomor_hp' then null;
 when 'nomor_pesanan' then allowed:=allowed||array['order_number'];
 when 'metode_pembayaran' then
  allowed:=allowed||array['order_number','order_id','payment'];
  if coalesce(new.data->>'payment','') not in ('COD','LinkAja') then raise exception 'Invalid payment'; end if;
  if new.data->>'payment'='COD' and not exists(select 1 from public.bayar_aman_members m where m.user_id=new.user_id and m.phone_key=public.bayar_aman_phone_key(new.data->>'phone') and m.status='active') then raise exception 'Keanggotaan aktif diperlukan untuk COD'; end if;
 when 'pendaftaran' then
  -- Only the definer registration transaction may produce an activation event.
  if current_user in ('authenticated','anon') then raise exception 'Gunakan fungsi pendaftaran anggota'; end if;
  allowed:=allowed||array['order_number','order_id','name','address','email','promo_requested','member_status','free_shipping_quota'];
  if length(btrim(coalesce(new.data->>'name','')))=0 or length(btrim(coalesce(new.data->>'address','')))=0 then raise exception 'Name/address required'; end if;
 else raise exception 'Invalid type';
 end case;
 for k in select jsonb_object_keys(new.data) loop
  if not k=any(allowed) or jsonb_typeof(new.data->k)<>'string' then raise exception 'Unexpected field or type: %',k; end if;
 end loop;
 if coalesce(new.data->>'phone','') !~ '^[0-9]{10,15}$' then raise exception 'Invalid phone'; end if;
 if t<>'nomor_hp' and (length(btrim(coalesce(new.data->>'order_number','')))=0 or length(new.data->>'order_number')>80) then raise exception 'Invalid order number'; end if;
 if t in ('metode_pembayaran','pendaftaran') and not exists (
  select 1 from public.user_data u where u.id::text=new.data->>'order_id' and u.user_id=new.user_id
  and u.data->>'type'='nomor_pesanan' and u.data->>'order_number'=new.data->>'order_number'
 ) then raise exception 'Order must belong to current user'; end if;
 new.created_at:=clock_timestamp(); new.updated_at:=new.created_at;
 return new;
end $$;

-- Returning id::text on the server avoids JSON bigint rounding in browsers.
create or replace function public.bayar_aman_submit_event(p_data jsonb) returns text
language plpgsql security invoker set search_path='' as $$
declare result text;
begin
 if coalesce(p_data->>'type','') not in ('nomor_hp','nomor_pesanan','metode_pembayaran') then raise exception 'Invalid event type'; end if;
 insert into public.user_data(user_id,data) values(auth.uid(),p_data||jsonb_build_object('submitted_at',clock_timestamp())) returning id::text into result;
 return result;
end $$;
revoke all on function public.bayar_aman_submit_event(jsonb) from public,anon;
grant execute on function public.bayar_aman_submit_event(jsonb) to authenticated;

create or replace function public.bayar_aman_my_membership(p_phone text) returns jsonb
language sql stable security invoker set search_path='' as $$
 select jsonb_build_object('status',m.status,'free_shipping_quota',m.free_shipping_quota)
 from public.bayar_aman_members m where m.user_id=auth.uid() and m.phone_key=public.bayar_aman_phone_key(p_phone);
$$;
revoke all on function public.bayar_aman_my_membership(text) from public,anon;
grant execute on function public.bayar_aman_my_membership(text) to authenticated;

create or replace function public.bayar_aman_register_member(p_name text,p_phone text,p_address text,p_email text,p_order_id text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare owner_id uuid:=auth.uid(); m public.bayar_aman_members; order_no text; event_id text;
begin
 if owner_id is null or coalesce(auth.jwt()->>'is_anonymous','false')<>'true' then raise exception 'Sesi User diperlukan' using errcode='42501'; end if;
 if p_phone is null or p_phone !~ '^[0-9]{10,15}$'
 or p_name is null or length(btrim(p_name)) not between 1 and 200
 or p_address is null or length(btrim(p_address)) not between 1 and 2000
 or p_email is null or length(p_email)>254 or (p_email<>'' and p_email !~ '^[^[:space:]@]+@[^[:space:]@]+[.][^[:space:]@]+$')
 then raise exception 'Data pendaftaran tidak valid'; end if;
 select u.data->>'order_number' into order_no from public.user_data u
 where u.id::text=p_order_id and u.user_id=owner_id and u.data->>'type'='nomor_pesanan' and u.data->>'phone'=p_phone;
 if not found then raise exception 'Pesanan harus milik sesi dan nomor HP ini'; end if;
 -- Serialize retries from the same session, including simultaneous requests.
 perform pg_advisory_xact_lock(hashtextextended(owner_id::text,0));
 select * into m from public.bayar_aman_members where user_id=owner_id for update;
 if found then
  if m.phone_key<>public.bayar_aman_phone_key(p_phone) then raise exception 'Sesi ini sudah memiliki keanggotaan. Hubungi Admin untuk pemulihan.'; end if;
  return jsonb_build_object('status',m.status,'free_shipping_quota',m.free_shipping_quota,'registration_id',m.registration_id,'created',false);
 end if;
 begin
  insert into public.bayar_aman_members(user_id,phone,name,address,email)
  values(owner_id,p_phone,btrim(p_name),btrim(p_address),btrim(p_email)) returning * into m;
 exception when unique_violation then
  raise exception 'Nomor ini sudah terdaftar. Gunakan sesi awal atau hubungi Admin untuk pemulihan.';
 end;
 -- Membership, quota and the Admin event commit or roll back together.
 insert into public.user_data(user_id,data) values(owner_id,jsonb_build_object(
  'type','pendaftaran','name',m.name,'phone',m.phone,'address',m.address,'email',m.email,
  'order_id',p_order_id,'order_number',order_no,'promo_requested','3_kali_gratis_ongkir',
  'member_status','active','free_shipping_quota','3','submitted_at',clock_timestamp())) returning id::text into event_id;
 update public.bayar_aman_members set registration_id=event_id where user_id=owner_id;
 return jsonb_build_object('status','active','free_shipping_quota',3,'registration_id',event_id,'created',true);
end $$;
revoke all on function public.bayar_aman_register_member(text,text,text,text,text) from public,anon;
grant execute on function public.bayar_aman_register_member(text,text,text,text,text) to authenticated;
-- Text IDs also protect the Admin editor from bigint rounding.
create or replace function public.bayar_aman_admin_events(p_offset integer default 0,p_limit integer default 500)
returns table(id text,user_id uuid,data jsonb,created_at timestamptz,updated_at timestamptz)
language plpgsql security definer set search_path='' as $$
begin
 if not public.is_admin() then raise exception 'Admin access required' using errcode='42501'; end if;
 if p_offset is null or p_offset<0 or p_limit is null or p_limit not between 1 and 500 then raise exception 'Invalid pagination'; end if;
 return query select u.id::text,u.user_id,u.data,u.created_at,u.updated_at from public.user_data u
 order by u.created_at desc,u.id desc limit p_limit offset p_offset;
end $$;
revoke all on function public.bayar_aman_admin_events(integer,integer) from public,anon;
grant execute on function public.bayar_aman_admin_events(integer,integer) to authenticated;
commit;
