-- =============================================================================
-- 04. CIDADES (base de destinos)
-- =============================================================================
-- Nota: dias_coleta / prazo_entrega / prazo_entrega_consolidado ficam como
-- texto livre por enquanto (ex.: 'Seg, Qua, Sex' / '3 dias úteis'), espelhando
-- o protótipo. Se a equipe quiser filtrar/ordenar por dia da semana no futuro,
-- vale migrar dias_coleta para um array de um enum de dias — sinalizando aqui
-- como decisão em aberto, não tomada unilateralmente.
--
-- Importante: esta tabela NÃO tem colunas de custo Fiorino/Iveco nem de
-- pedido mínimo (o protótipo tinha essas colunas "congeladas" — ver seção 3.1
-- do documento). Esses valores são sempre recalculados a partir de
-- parametros_custo + km, nas views/funções definidas mais abaixo.
create table public.cidades (
  id                       uuid primary key default gen_random_uuid(),
  transportadora_id        uuid not null references public.transportadoras (id),
  regiao_rota              text,
  nome                     text not null,
  km                       numeric not null check (km >= 0),
  dias_coleta              text,
  prazo_entrega            text,
  prazo_entrega_consolidado text,
  criado_em                timestamptz not null default now(),
  unique (nome, transportadora_id)
);

create index cidades_transportadora_id_idx on public.cidades (transportadora_id);
create index cidades_nome_idx on public.cidades using gin (nome gin_trgm_ops);

alter table public.cidades enable row level security;

revoke all on public.cidades from anon;
grant select, insert, update, delete on public.cidades to authenticated;

create policy "autenticados leem cidades"
  on public.cidades for select
  to authenticated
  using (true);

create policy "admin gerencia cidades"
  on public.cidades for all
  to authenticated
  using (public.is_admin())
  with check (public.is_admin());

-- -----------------------------------------------------------------------------
-- View: cidades_com_faixa
-- -----------------------------------------------------------------------------
-- Base para a tela "Base de dados" quando acessada por um vendedor: nome,
-- transportadora, região, km, faixa (calculada), prazos — sem nenhuma coluna
-- de custo. Todo usuário autenticado pode ler.
--
-- "security_invoker = true" é proposital: por padrão, uma view do Postgres
-- executa com os privilégios de quem a CRIOU (o dono), não de quem a
-- consulta. Como as migrações costumam rodar com um usuário com privilégios
-- amplos, uma view "clássica" poderia acabar contornando a RLS das tabelas
-- de baixo sem querer. Com security_invoker, a RLS é sempre avaliada com a
-- identidade de quem está de fato consultando — é o comportamento que
-- queremos em todas as views deste projeto.
create view public.cidades_com_faixa
with (security_invoker = true) as
select
  c.id,
  c.nome,
  c.transportadora_id,
  t.nome as transportadora_nome,
  c.regiao_rota,
  c.km,
  f.codigo as faixa_codigo,
  f.rotulo as faixa_rotulo,
  c.dias_coleta,
  c.prazo_entrega,
  c.prazo_entrega_consolidado
from public.cidades c
join public.transportadoras t on t.id = c.transportadora_id
cross join lateral public.calcular_faixa(c.km) f;

-- Views não herdam GRANTs das tabelas de baixo — precisam do próprio grant.
revoke all on public.cidades_com_faixa from anon;
grant select on public.cidades_com_faixa to authenticated;
