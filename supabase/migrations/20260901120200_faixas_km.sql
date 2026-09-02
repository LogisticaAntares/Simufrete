-- =============================================================================
-- 03. FAIXAS DE DISTÂNCIA
-- =============================================================================
-- limite_km = null significa "sem limite" (a faixa "Fora do Perímetro").
-- ordem define a ordem de exibição/avaliação nas telas e relatórios.
create table public.faixas_km (
  id        uuid primary key default gen_random_uuid(),
  codigo    text not null unique,      -- 'R1-Urbano', 'R2-Curta', ... 'Fora'
  rotulo    text not null,             -- 'R1 — Urbano'
  limite_km numeric check (limite_km is null or limite_km > 0),
  ordem     smallint not null unique,
  criado_em timestamptz not null default now()
);

alter table public.faixas_km enable row level security;

revoke all on public.faixas_km from anon;
grant select, insert, update, delete on public.faixas_km to authenticated;

create policy "autenticados leem faixas"
  on public.faixas_km for select
  to authenticated
  using (true);

create policy "admin gerencia faixas"
  on public.faixas_km for all
  to authenticated
  using (public.is_admin())
  with check (public.is_admin());

-- Seed com os valores padrão do documento (seção 3.3).
insert into public.faixas_km (codigo, rotulo, limite_km, ordem) values
  ('R1-Urbano', 'R1 — Urbano',          30,  1),
  ('R2-Curta',  'R2 — Curta',          150,  2),
  ('R3-Media',  'R3 — Média',          350,  3),
  ('R4-Longa',  'R4 — Longa',          600,  4),
  ('Fora',      'Fora do Perímetro',  null,  5);

-- -----------------------------------------------------------------------------
-- calcular_faixa(km): dada uma distância, devolve a faixa correspondente.
-- -----------------------------------------------------------------------------
-- Decisão central do documento (seção 3.1): a faixa de uma cidade NUNCA é
-- gravada como coluna fixa. Ela é sempre derivada, em tempo de consulta, do
-- km da cidade + dos limites atuais de faixas_km. Isso elimina de vez a
-- necessidade de triggers de recálculo em massa quando o admin edita um
-- limite de faixa: a próxima leitura já reflete o valor novo automaticamente.
create or replace function public.calcular_faixa(p_km numeric)
returns public.faixas_km
language sql
stable
as $$
  select f.*
  from public.faixas_km f
  where f.limite_km is null or f.limite_km >= p_km
  order by (f.limite_km is null) asc, f.limite_km asc
  limit 1;
$$;

comment on function public.calcular_faixa(numeric) is
  'Resolve a faixa de distância aplicável a um km. Sempre calculada em tempo real, nunca cacheada em coluna.';
