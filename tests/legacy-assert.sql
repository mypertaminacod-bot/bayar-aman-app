set role authenticated;
select set_config('test.uid','00000000-0000-0000-0000-000000000001',false),set_config('test.jwt','{"is_anonymous":true}',false);
insert into public.user_data(user_id,data) values(auth.uid(),'{"type":"nomor_hp","phone":"081234567890"}');
reset role;
do $$ begin
 if exists(select 1 from pg_policies where schemaname='public' and tablename='user_data' and policyname='unsafe_legacy') then raise exception 'Legacy permissive policy survived'; end if;
 if (select count(*) from public.user_data)<>1 then raise exception 'Serial insert failed'; end if;
end $$;
select 'PASS: legacy bigint/serial insert and unsafe policy replacement';
