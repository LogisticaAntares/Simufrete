-- Shim mínimo do ambiente Supabase (auth schema + roles + auth.uid/auth.role)
-- só para validar as migrações localmente. Não faz parte do projeto.
create schema if not exists auth;

create table auth.users (
  id uuid primary key default gen_random_uuid(),
  email text,
  raw_user_meta_data jsonb default '{}'::jsonb
);

do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'anon') then
    create role anon nologin;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then
    create role authenticated nologin;
  end if;
end
$$;

grant usage on schema public to anon, authenticated;
grant usage on schema auth to anon, authenticated;

-- auth.uid() / auth.role(): no Supabase real, leem claims do JWT via
-- current_setting. Aqui, para os testes, lemos de uma GUC de sessão que o
-- script de teste define com `set local session.test_uid = '...'`.
create or replace function auth.uid() returns uuid
language sql stable as $$
  select nullif(current_setting('session.test_uid', true), '')::uuid;
$$;

create or replace function auth.role() returns text
language sql stable as $$
  select current_setting('session.test_role', true);
$$;
