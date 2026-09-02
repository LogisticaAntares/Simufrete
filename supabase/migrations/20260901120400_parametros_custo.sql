-- =============================================================================
-- 05. PARÂMETROS DE CUSTO
-- =============================================================================
-- Linha única (id fixo = 1) com todos os parâmetros da seção 3.4 do
-- documento. Percentuais são guardados como fração (0.03 = 3%), não como
-- número inteiro — deixar isso explícito evita erro de dízima na hora de
-- montar a UI de edição.
create table public.parametros_custo (
  id smallint primary key default 1 check (id = 1),

  -- Fiorino (frota própria, veículo pequeno)
  fiorino_manutencao_km  numeric not null default 0.20,
  fiorino_pneus_km       numeric not null default 0.08,
  fiorino_depreciacao_km numeric not null default 0.15,
  fiorino_seguro_km      numeric not null default 0.07,
  fiorino_consumo_km_l   numeric not null default 10,
  fiorino_capacidade_kg  numeric not null default 650,

  -- Iveco Tector (frota própria, veículo grande)
  iveco_manutencao_km    numeric not null default 0.50,
  iveco_pneus_km         numeric not null default 0.11,
  iveco_depreciacao_km   numeric not null default 0.40,
  iveco_seguro_doc_km    numeric not null default 0.20,
  iveco_consumo_km_l     numeric not null default 5,
  iveco_capacidade_kg    numeric not null default 9000,

  -- Gerais
  preco_litro   numeric not null default 7.00,   -- R$/litro, único para os dois veículos
  pct_frota     numeric not null default 0.03,   -- 3%  (teto do frete próprio sobre o valor do pedido)
  pct_transp    numeric not null default 0.05,   -- 5%  (percentual cobrado pela transportadora)
  frete_min     numeric not null default 80.00,  -- R$  (frete mínimo da transportadora)
  ad_valorem    numeric not null default 0.003,  -- 0,3% (seguro proporcional ao valor)
  preco_volume  numeric not null default 20.00,  -- R$  (cobrança por volume despachado)

  atualizado_em timestamptz not null default now(),
  atualizado_por uuid references public.perfis (id)
);

comment on table public.parametros_custo is
  'Linha única (id=1) com os parâmetros de custo vigentes. Nunca versionada por cidade — toda cidade usa sempre esta linha atual.';

insert into public.parametros_custo (id) values (1);

-- -----------------------------------------------------------------------------
-- RLS: leitura E escrita restritas a admin.
-- -----------------------------------------------------------------------------
-- Diferente de transportadoras/faixas_km/cidades, aqui o vendedor NÃO tem
-- select direto. Motivo: é a única forma real (não apenas de UI) de impedir
-- que o vendedor veja os parâmetros de custo brutos, já que RLS no Postgres
-- filtra LINHAS, não colunas — não existe "esconder a coluna X da role
-- authenticated" quando admin e vendedor são a mesma role de conexão. A
-- tela de Simulador, que o vendedor usa e que PRECISA do resultado do
-- cálculo, não lê esta tabela diretamente: ela chama a função
-- simular_frete() (ver 06_funcoes_calculo.sql), que roda como
-- SECURITY DEFINER e devolve só o resultado já calculado, nunca os
-- parâmetros crus.
alter table public.parametros_custo enable row level security;

revoke all on public.parametros_custo from anon;
grant select, update on public.parametros_custo to authenticated;
-- Sem insert/delete: linha única, já semeada acima.

create policy "admin le parametros"
  on public.parametros_custo for select
  to authenticated
  using (public.is_admin());

create policy "admin atualiza parametros"
  on public.parametros_custo for update
  to authenticated
  using (public.is_admin())
  with check (public.is_admin());
