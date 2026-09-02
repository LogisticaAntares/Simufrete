-- =============================================================================
-- 06. HISTÓRICO DE SIMULAÇÕES
-- =============================================================================
-- Esta é a ÚNICA tabela do sistema onde "congelar" um valor calculado é
-- correto, e não um artefato a evitar: o histórico é um registro de
-- auditoria de "o que foi mostrado ao vendedor naquele momento", então ele
-- deve preservar o resultado exatamente como calculado na hora — mesmo que
-- o admin altere os parâmetros de custo depois. Isso é o oposto da regra
-- aplicada a `cidades` (seção 3.1 do documento), e é intencional.
create table public.historico_simulacoes (
  id                  uuid primary key default gen_random_uuid(),
  usuario_id          uuid not null references public.perfis (id),
  cidade_id           uuid not null references public.cidades (id),
  km                  numeric not null,
  peso                numeric not null,
  valor_pedido        numeric,
  quantidade_volumes  integer,
  modal_vencedor      text not null,     -- 'fiorino' | 'iveco' | 'transportadora' | 'volume'
  custo_vencedor      numeric not null,
  resultado           jsonb not null,    -- snapshot completo devolvido por simular_frete()
  criado_em           timestamptz not null default now()
);

create index historico_usuario_id_idx on public.historico_simulacoes (usuario_id);
create index historico_cidade_id_idx on public.historico_simulacoes (cidade_id);
create index historico_criado_em_idx on public.historico_simulacoes (criado_em desc);

alter table public.historico_simulacoes enable row level security;

revoke all on public.historico_simulacoes from anon;
grant select, delete on public.historico_simulacoes to authenticated;
-- Sem "insert" para authenticated de propósito: a única forma de gravar uma
-- linha é através da função simular_frete() (SECURITY DEFINER), para que o
-- vendedor nunca consiga inserir diretamente um resultado forjado no
-- histórico — o valor salvo é sempre o que o servidor de fato calculou.

create policy "autenticados leem historico"
  on public.historico_simulacoes for select
  to authenticated
  using (true);   -- seção 2 do documento: histórico não é restrito ao admin

create policy "admin exclui historico"
  on public.historico_simulacoes for delete
  to authenticated
  using (public.is_admin());
