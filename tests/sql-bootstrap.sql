-- LOCAL DISPOSABLE POSTGRES ONLY; mock the minimal Supabase Auth interface.
create role anon nologin;
create role authenticated nologin;
create schema auth;
create table auth.users(id uuid primary key);
create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('test.uid',true),'')::uuid $$;
create function auth.jwt() returns jsonb language sql stable as $$ select coalesce(nullif(current_setting('test.jwt',true),''),'{}')::jsonb $$;
grant usage on schema auth to authenticated,anon;
grant execute on all functions in schema auth to authenticated,anon;
create publication supabase_realtime;
insert into auth.users values ('00000000-0000-0000-0000-000000000001'),('00000000-0000-0000-0000-000000000002'),('00000000-0000-0000-0000-000000000003');
