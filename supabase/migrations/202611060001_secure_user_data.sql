-- REVIEW BEFORE APPLYING. Transaction rolls back on incompatible existing schema.
-- Existing unowned records are retained, never assigned based on phone/order number.
begin;
create table if not exists public.user_data (
 id uuid primary key default gen_random_uuid(),
 user_id uuid references auth.users(id),
 data jsonb not null,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
alter table public.user_data add column if not exists user_id uuid references auth.users(id);
alter table public.user_data add column if not exists updated_at timestamptz not null default now();
do $$
begin
 if not exists (select 1 from information_schema.columns where table_schema='public' and table_name='user_data' and column_name='data' and data_type='jsonb')
 or not exists (select 1 from information_schema.columns where table_schema='public' and table_name='user_data' and column_name='user_id' and data_type='uuid')
 or not exists (select 1 from information_schema.columns where table_schema='public' and table_name='user_data' and column_name='created_at' and data_type='timestamp with time zone')
 or not exists (select 1 from information_schema.columns where table_schema='public' and table_name='user_data' and column_name='updated_at' and data_type='timestamp with time zone')
 or not exists (select 1 from information_schema.columns where table_schema='public' and table_name='user_data' and column_name='id' and data_type in ('uuid','bigint','integer','text'))
 then raise exception 'Incompatible user_data schema: inspect and adapt migration before retrying'; end if;
end $$;
-- Normalize nullable legacy timestamps without changing ownership or user data.
update public.user_data set updated_at=coalesce(created_at,clock_timestamp()) where updated_at is null;
alter table public.user_data alter column updated_at set default now();
alter table public.user_data alter column updated_at set not null;
-- Dedicated allowlist. No grants to browser roles. Never trust user_metadata.
create table public.bayar_aman_admins (user_id uuid primary key references auth.users(id) on delete cascade);
alter table public.bayar_aman_admins enable row level security;
revoke all on public.bayar_aman_admins from public, anon, authenticated;
create or replace function public.is_admin() returns boolean language sql stable security definer set search_path = '' as $$
 select exists (select 1 from public.bayar_aman_admins a where a.user_id = (select auth.uid()))
 and coalesce((select auth.jwt())->>'is_anonymous','false') = 'false';
$$;
revoke all on function public.is_admin() from public, anon;
grant execute on function public.is_admin() to authenticated;

-- Drop ALL old policies: permissive policies combine with OR and can leak other users' rows.
-- Inspect pg_policies before applying; this intentionally replaces the table's access contract.
do $$ declare p record; begin
 for p in select policyname from pg_policies where schemaname='public' and tablename='user_data' loop
 execute format('drop policy %I on public.user_data',p.policyname);
 end loop;
end $$;
alter table public.user_data enable row level security;
alter table public.user_data force row level security;
revoke all on public.user_data from public, anon, authenticated;
grant select, insert on public.user_data to authenticated;
-- Legacy bigint/serial id: grant only the sequence attached to this column.
do $$ declare seq text; begin
 seq:=pg_get_serial_sequence('public.user_data','id');
 if seq is not null then execute format('grant usage on sequence %s to authenticated',seq); end if;
end $$;
create policy read_owned_or_admin on public.user_data for select to authenticated
 using (user_id=(select auth.uid()) or (select public.is_admin()));
create policy insert_owned on public.user_data for insert to authenticated
 with check (user_id=(select auth.uid()) and (select auth.jwt())->>'is_anonymous'='true');
-- No browser UPDATE/DELETE grants. Admin writes only through the checked RPC below.

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
 when 'pendaftaran' then
  allowed:=allowed||array['order_number','order_id','name','address','email','promo_requested'];
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
create trigger bayar_aman_insert_guard before insert on public.user_data for each row execute function public.bayar_aman_validate_insert();

create or replace function public.admin_update_order(p_id text,p_expected_updated_at timestamptz,p_detail jsonb,p_route jsonb)
returns boolean language plpgsql security definer set search_path = '' as $$
declare point jsonb; k text; n integer;
begin
 if not public.is_admin() then raise exception 'Admin access required' using errcode='42501'; end if;
 if jsonb_typeof(p_detail) is distinct from 'object' or octet_length(p_detail::text)>16000 then raise exception 'Invalid detail'; end if;
 foreach k in array array['name','phone','address','price','status','product'] loop
  if jsonb_typeof(p_detail->k) is distinct from 'string' or length(btrim(p_detail->>k))=0 then raise exception 'Missing detail: %',k; end if;
 end loop;
 if (select count(*) from jsonb_object_keys(p_detail))<>6 then raise exception 'Unexpected detail field'; end if;
 if jsonb_typeof(p_route) is distinct from 'array' then raise exception 'Route must be array'; end if;
 if jsonb_array_length(p_route)>30 then raise exception 'Too many route points'; end if;
 for point in select * from jsonb_array_elements(p_route) loop
  if jsonb_typeof(point) is distinct from 'object' then raise exception 'Invalid point'; end if;
  if jsonb_typeof(point->'address') is distinct from 'string' or length(btrim(point->>'address'))=0 or length(point->>'address')>1000
   or jsonb_typeof(point->'verified') is distinct from 'boolean' or jsonb_typeof(point->'source') is distinct from 'string' or length(point->>'source')>1000
   then raise exception 'Invalid point address/verification'; end if;
  if point->'lat'='null'::jsonb and point->'lng'='null'::jsonb then
   if (point->>'verified')::boolean then raise exception 'Verified point requires coordinates'; end if;
  else
   if jsonb_typeof(point->'lat') is distinct from 'number' or jsonb_typeof(point->'lng') is distinct from 'number' then raise exception 'Coordinates must be numbers'; end if;
   if abs((point->>'lat')::numeric)>90 or abs((point->>'lng')::numeric)>180 then raise exception 'Invalid coordinates'; end if;
  end if;
  if (point->>'verified')::boolean and length(btrim(point->>'source'))=0 then raise exception 'Verification source required'; end if;
 end loop;
 update public.user_data set data=data||jsonb_build_object('detail_pesanan',p_detail,'route',p_route,'admin_updated_at',clock_timestamp()),updated_at=clock_timestamp()
 where id::text=p_id and data->>'type'='nomor_pesanan' and updated_at=p_expected_updated_at;
 get diagnostics n=row_count;
 if n<>1 then raise exception 'Order missing or changed: reload before saving'; end if;
 return true;
end $$;
revoke all on function public.admin_update_order(text,timestamptz,jsonb,jsonb) from public,anon;
grant execute on function public.admin_update_order(text,timestamptz,jsonb,jsonb) to authenticated;
create index if not exists bayar_aman_user_owner on public.user_data(user_id);
do $$ begin
 if not exists (select 1 from pg_publication where pubname='supabase_realtime') then raise exception 'supabase_realtime publication missing'; end if;
 if not exists (select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='user_data') then
  alter publication supabase_realtime add table public.user_data;
 end if;
end $$;
commit;
