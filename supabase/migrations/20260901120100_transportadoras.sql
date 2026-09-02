-- =============================================================================
-- 02. TRANSPORTADORAS
-- =============================================================================
create table public.transportadoras (
  id        uuid primary key default gen_random_uuid(),
  nome      text not null unique,
  criado_em timestamptz not null default now()
);

alter table public.transportadoras enable row level security;

revoke all on public.transportadoras from anon;
grant select, insert, update, delete on public.transportadoras to authenticated;

create policy "autenticados leem transportadoras"
  on public.transportadoras for select
  to authenticated
  using (true);

create policy "admin gerencia transportadoras"
  on public.transportadoras for all
  to authenticated
  using (public.is_admin())
  with check (public.is_admin());

-- Seed (mesmas 3 do protótipo atual; admin pode renomear/adicionar depois).
insert into public.transportadoras (nome) values
  ('Gramado Transportes'),
  ('Campelo Vip Cargas'),
  ('Fonseca Transportes');
