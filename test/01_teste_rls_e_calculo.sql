-- Testa RLS + a função simular_frete() fim a fim, como admin e como vendedor.
\set ON_ERROR_STOP on

-- ---- setup: um admin, um vendedor, uma cidade em cada faixa ----
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-000000000001', 'admin@antares.com'),
  ('00000000-0000-0000-0000-000000000002', 'vendedor@antares.com');

update public.perfis set papel = 'admin' where id = '00000000-0000-0000-0000-000000000001';
-- o vendedor já nasce 'vendedor' pelo trigger.

select id into temp cid_urbano  from public.cidades limit 0; -- no-op, garante schema
insert into public.cidades (transportadora_id, nome, km, regiao_rota)
select id, 'CidadeUrbana', 10, 'Sul' from public.transportadoras limit 1;
insert into public.cidades (transportadora_id, nome, km, regiao_rota)
select id, 'CidadeMedia', 300, 'Sul' from public.transportadoras limit 1;
insert into public.cidades (transportadora_id, nome, km, regiao_rota)
select id, 'CidadeLonga', 500, 'Sul' from public.transportadoras limit 1;
insert into public.cidades (transportadora_id, nome, km, regiao_rota)
select id, 'CidadeFora', 900, 'Sul' from public.transportadoras limit 1;

\echo '=== 1) faixas calculadas corretamente ==='
select nome, km, faixa_codigo, faixa_rotulo from public.cidades_com_faixa order by km;

-- ---- como ADMIN ----
set role authenticated;
set session.test_uid = '00000000-0000-0000-0000-000000000001';

\echo '=== 2) admin le parametros_custo (deve funcionar) ==='
select preco_litro, pct_frota, fiorino_capacidade_kg from public.parametros_custo;

\echo '=== 3) admin ve cidades_com_custo (deve trazer custo/pedido minimo) ==='
select nome, faixa_codigo, custo_total_fiorino, custo_total_iveco, pedido_minimo_fiorino
from public.cidades_com_custo order by km;

\echo '=== 4) simulacao rodada pelo admin p/ cidade urbana (peso baixo, valor alto) ==='
select jsonb_pretty(public.simular_frete(
  (select id from public.cidades where nome = 'CidadeUrbana'),
  100, 50000, null
));

reset role;

-- ---- como VENDEDOR ----
set role authenticated;
set session.test_uid = '00000000-0000-0000-0000-000000000002';

\echo '=== 5) vendedor tenta ler parametros_custo (deve vir vazio) ==='
select count(*) as linhas_visiveis from public.parametros_custo;

\echo '=== 6) vendedor tenta ler cidades_com_custo (colunas de custo devem ser NULL / sem linha) ==='
select nome, faixa_codigo, custo_total_fiorino from public.cidades_com_custo order by km;

\echo '=== 7) vendedor consegue rodar simular_frete normalmente (deve funcionar, com detalhamento) ==='
select jsonb_pretty(public.simular_frete(
  (select id from public.cidades where nome = 'CidadeMedia'),
  250, 8000, null
));

\echo '=== 8) vendedor tenta inserir direto no historico (deve falhar por falta de policy de insert) ==='
do $$
begin
  begin
    insert into public.historico_simulacoes
      (usuario_id, cidade_id, km, peso, modal_vencedor, custo_vencedor, resultado)
    values
      ('00000000-0000-0000-0000-000000000002',
       (select id from public.cidades where nome = 'CidadeMedia'),
       300, 100, 'fiorino', 1, '{}'::jsonb);
    raise notice 'FALHA DO TESTE: insert direto deveria ter sido bloqueado';
  exception when others then
    raise notice 'OK: insert direto bloqueado como esperado (%)', sqlerrm;
  end;
end $$;

\echo '=== 9) vendedor le historico (deve ver as 2 simulacoes ja rodadas, do admin e dele mesmo) ==='
select usuario_id, modal_vencedor, custo_vencedor from public.historico_simulacoes order by criado_em;

-- Nota: RLS bloqueia via filtro de linhas, não via exceção — um DELETE/UPDATE
-- sem permissão simplesmente afeta 0 linhas (comportamento padrão do
-- Postgres). Por isso os testes abaixo checam ROW_COUNT em vez de esperar
-- um erro.
\echo '=== 10) vendedor tenta excluir cidade (deve afetar 0 linhas, so admin gerencia) ==='
do $$
declare
  v_linhas int;
begin
  delete from public.cidades where nome = 'CidadeFora';
  get diagnostics v_linhas = row_count;
  if v_linhas = 0 then
    raise notice 'OK: delete bloqueado por RLS (0 linhas afetadas)';
  else
    raise notice 'FALHA DO TESTE: delete afetou % linha(s), deveria ter sido bloqueado', v_linhas;
  end if;
end $$;

\echo '=== confirmando que CidadeFora ainda existe (delete acima nao deve ter passado) ==='
select count(*) as deve_ser_1 from public.cidades where nome = 'CidadeFora';

\echo '=== 11) simulacao com peso acima da capacidade do Fiorino em rota R2 (deve recomendar Iveco, sem opcao fiorino) ==='
select jsonb_pretty(public.simular_frete(
  (select id from public.cidades where nome = 'CidadeUrbana'),
  700, 20000, null
));

\echo '=== 12) simulacao fora do perimetro (deve recomendar transportadora, mesmo com peso baixo) ==='
select jsonb_pretty(public.simular_frete(
  (select id from public.cidades where nome = 'CidadeFora'),
  50, 3000, null
));

\echo '=== 13) simulacao com volumes informados ==='
select jsonb_pretty(public.simular_frete(
  (select id from public.cidades where nome = 'CidadeMedia'),
  100, 1000, 5
));

reset role;

\echo '=== 14) vendedor tenta se auto-promover a admin (deve falhar por RLS de update) ==='
set role authenticated;
set session.test_uid = '00000000-0000-0000-0000-000000000002';
do $$
declare
  v_linhas int;
begin
  update public.perfis set papel = 'admin' where id = '00000000-0000-0000-0000-000000000002';
  get diagnostics v_linhas = row_count;
  if v_linhas = 0 then
    raise notice 'OK: auto-promocao bloqueada por RLS (0 linhas afetadas)';
  else
    raise notice 'FALHA DO TESTE: auto-promocao afetou % linha(s)', v_linhas;
  end if;
end $$;
reset role;

\echo '=== confirmando papel do vendedor apos a tentativa (deve continuar vendedor) ==='
select id, papel from public.perfis where id = '00000000-0000-0000-0000-000000000002';

\echo '=== 15) admin tenta excluir o proprio usuario (deve falhar pela trigger) ==='
set role authenticated;
set session.test_uid = '00000000-0000-0000-0000-000000000001';
do $$
begin
  begin
    delete from public.perfis where id = '00000000-0000-0000-0000-000000000001';
    raise notice 'FALHA DO TESTE: auto-exclusao deveria ter sido bloqueada';
  exception when others then
    raise notice 'OK: auto-exclusao bloqueada como esperado (%)', sqlerrm;
  end;
end $$;

\echo '=== 16) admin tenta rebaixar o unico admin (deve falhar pela trigger) ==='
do $$
begin
  begin
    update public.perfis set papel = 'vendedor' where id = '00000000-0000-0000-0000-000000000001';
    raise notice 'FALHA DO TESTE: rebaixar unico admin deveria ter sido bloqueado';
  exception when others then
    raise notice 'OK: rebaixamento do unico admin bloqueado como esperado (%)', sqlerrm;
  end;
end $$;
reset role;
