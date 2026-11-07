create table public.user_data(id bigserial primary key,user_id uuid,data jsonb,created_at timestamptz default now());
alter table public.user_data enable row level security;
create policy unsafe_legacy on public.user_data for all using (true) with check(true);
