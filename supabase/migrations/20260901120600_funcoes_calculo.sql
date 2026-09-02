-- =============================================================================
-- 07. FUNÇÕES DE CÁLCULO (fórmulas da seção 4/5 do documento)
-- =============================================================================
-- Tudo aqui é a ÚNICA fonte de verdade das fórmulas. O front-end nunca
-- reimplementa a conta — ele só chama simular_frete() e exibe o resultado.
-- Isso evita o clássico problema de "a fórmula do front-end e a do banco
-- foram divergindo com o tempo".

-- -----------------------------------------------------------------------------
-- custo_km_fiorino / custo_km_iveco
-- -----------------------------------------------------------------------------
create or replace function public.custo_km_fiorino(p public.parametros_custo)
returns numeric
language sql
immutable
as $$
  select (p.preco_litro / p.fiorino_consumo_km_l)
       + p.fiorino_manutencao_km + p.fiorino_pneus_km
       + p.fiorino_depreciacao_km + p.fiorino_seguro_km;
$$;

create or replace function public.custo_km_iveco(p public.parametros_custo)
returns numeric
language sql
immutable
as $$
  select (p.preco_litro / p.iveco_consumo_km_l)
       + p.iveco_manutencao_km + p.iveco_pneus_km
       + p.iveco_depreciacao_km + p.iveco_seguro_doc_km;
$$;

-- -----------------------------------------------------------------------------
-- calcular_custos_cidade(km): custo total e pedido mínimo de cada veículo
-- próprio para uma dada distância, usando os parâmetros vigentes.
-- -----------------------------------------------------------------------------
-- NÃO é security definer de propósito: ela lê parametros_custo como quem a
-- chamou, então a RLS de parametros_custo (só admin) se aplica normalmente.
-- Um vendedor chamando isso direto, ou através de uma view que a use,
-- recebe zero linhas — é assim que a tela "Base de dados" filtra as
-- colunas de custo por papel sem precisar de RLS por coluna.
create or replace function public.calcular_custos_cidade(p_km numeric)
returns table (
  custo_total_fiorino   numeric,
  custo_total_iveco     numeric,
  pedido_minimo_fiorino numeric,
  pedido_minimo_iveco   numeric
)
language sql
stable
as $$
  select
    public.custo_km_fiorino(p) * (p_km * 2)                          as custo_total_fiorino,
    public.custo_km_iveco(p)   * (p_km * 2)                          as custo_total_iveco,
    (public.custo_km_fiorino(p) * (p_km * 2)) / p.pct_frota          as pedido_minimo_fiorino,
    (public.custo_km_iveco(p)   * (p_km * 2)) / p.pct_frota          as pedido_minimo_iveco
  from public.parametros_custo p
  where p.id = 1;
$$;

-- -----------------------------------------------------------------------------
-- View: cidades_com_custo — equivalente da tela "Base de dados" para admin,
-- com as colunas de custo/pedido mínimo recalculadas na hora (nunca lidas de
-- uma coluna congelada). security_invoker garante que a RLS de
-- parametros_custo seja respeitada pelo usuário que consulta a view, não
-- pelo dono dela — por isso um vendedor que tentar ler esta view
-- simplesmente não recebe as colunas de custo (o join com
-- calcular_custos_cidade não retorna linha).
-- -----------------------------------------------------------------------------
create view public.cidades_com_custo
with (security_invoker = true) as
select
  cf.*,
  cc.custo_total_fiorino,
  cc.custo_total_iveco,
  cc.pedido_minimo_fiorino,
  cc.pedido_minimo_iveco
from public.cidades_com_faixa cf
cross join lateral public.calcular_custos_cidade(cf.km) cc;

revoke all on public.cidades_com_custo from anon;
grant select on public.cidades_com_custo to authenticated;

-- -----------------------------------------------------------------------------
-- simular_frete(): implementa as seções 4 e 5 do documento por inteiro.
-- -----------------------------------------------------------------------------
-- SECURITY DEFINER de propósito: é o único caminho pelo qual um vendedor
-- obtém números derivados de parametros_custo, sem nunca ler a tabela em si.
-- A função também grava o histórico dentro da mesma transação — assim o
-- valor salvo em historico_simulacoes é garantidamente o mesmo que foi
-- calculado, e o vendedor não tem uma policy de INSERT direta na tabela
-- para forjar esse valor (ver 06_historico_simulacoes.sql).
create or replace function public.simular_frete(
  p_cidade_id uuid,
  p_peso      numeric,
  p_valor     numeric default null,
  p_volumes   integer default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_cidade                  record;
  v_faixa                   public.faixas_km;
  v_params                  public.parametros_custo;
  v_km2                     numeric;
  v_custo_km_fiorino        numeric;
  v_custo_km_iveco          numeric;
  v_custo_total_fiorino     numeric;
  v_custo_total_iveco       numeric;
  v_pedido_minimo_fiorino   numeric;
  v_pedido_minimo_iveco     numeric;
  v_frete_transportadora    numeric;
  v_custo_volume            numeric;
  v_fiorino_excede_capac    boolean;
  v_recomendacao            text;
  v_opcoes                  jsonb := '[]'::jsonb;
  v_vencedor                jsonb;
  v_selo_fiorino            text;
  v_selo_iveco              text;
  v_selo_transportadora     text;
  v_resultado               jsonb;
begin
  if p_peso is null or p_peso <= 0 then
    raise exception 'Peso deve ser maior que zero.';
  end if;

  select c.*, t.nome as transportadora_nome
    into v_cidade
  from public.cidades c
  join public.transportadoras t on t.id = c.transportadora_id
  where c.id = p_cidade_id;

  if not found then
    raise exception 'Cidade não encontrada: %', p_cidade_id;
  end if;

  select * into v_params from public.parametros_custo where id = 1;
  v_faixa := public.calcular_faixa(v_cidade.km);

  v_km2 := v_cidade.km * 2;
  v_custo_km_fiorino      := public.custo_km_fiorino(v_params);
  v_custo_km_iveco        := public.custo_km_iveco(v_params);
  v_custo_total_fiorino   := v_custo_km_fiorino * v_km2;
  v_custo_total_iveco     := v_custo_km_iveco * v_km2;
  v_pedido_minimo_fiorino := v_custo_total_fiorino / v_params.pct_frota;
  v_pedido_minimo_iveco   := v_custo_total_iveco / v_params.pct_frota;
  v_fiorino_excede_capac  := p_peso > v_params.fiorino_capacidade_kg;

  if p_valor is not null then
    v_frete_transportadora := greatest(
      v_params.frete_min,
      p_valor * v_params.pct_transp + p_valor * v_params.ad_valorem
    );
  end if;

  if p_volumes is not null then
    v_custo_volume := p_volumes * v_params.preco_volume;
  end if;

  -- ---- Recomendação categórica (seção 5.1), nesta ordem exata ----
  if v_faixa.codigo = 'Fora' then
    v_recomendacao := 'Transportadora recomendada (fora do raio de frota própria).';
  elsif v_fiorino_excede_capac and v_faixa.codigo <> 'R1-Urbano' then
    v_recomendacao := 'Iveco recomendado (peso excede a capacidade do Fiorino).';
  elsif v_faixa.codigo in ('R1-Urbano', 'R2-Curta') then
    v_recomendacao := 'Fiorino recomendado (distância curta favorece frota própria).';
  elsif v_faixa.codigo = 'R3-Media' then
    v_recomendacao := 'Avaliar ambos (comparar caso a caso; acima de 200 kg o Iveco tende a compensar).';
  else
    v_recomendacao := 'Transportadora tende a ser mais competitiva.';
  end if;

  -- ---- Selos de viabilidade (seção 5.3) — só se valor do pedido foi informado ----
  if p_valor is not null then
    if v_fiorino_excede_capac then
      v_selo_fiorino := 'inviavel';
    elsif p_valor >= v_pedido_minimo_fiorino then
      v_selo_fiorino := 'viavel';
    else
      v_selo_fiorino := 'avaliar';
    end if;

    if p_valor >= v_pedido_minimo_iveco then
      v_selo_iveco := 'viavel';
    else
      v_selo_iveco := 'avaliar';
    end if;

    if v_frete_transportadora <= p_valor * v_params.pct_transp * 3 then
      v_selo_transportadora := 'viavel';
    else
      v_selo_transportadora := 'avaliar';
    end if;
  end if;

  -- ---- Vencedor real: menor custo entre as opções disponíveis (seção 5.2) ----
  if not v_fiorino_excede_capac then
    v_opcoes := v_opcoes || jsonb_build_object('modal', 'fiorino', 'custo', v_custo_total_fiorino);
  end if;
  v_opcoes := v_opcoes || jsonb_build_object('modal', 'iveco', 'custo', v_custo_total_iveco);
  if v_frete_transportadora is not null then
    v_opcoes := v_opcoes || jsonb_build_object('modal', 'transportadora', 'custo', v_frete_transportadora);
  end if;
  if v_custo_volume is not null then
    v_opcoes := v_opcoes || jsonb_build_object('modal', 'volume', 'custo', v_custo_volume);
  end if;

  select o into v_vencedor
  from jsonb_array_elements(v_opcoes) o
  order by (o ->> 'custo')::numeric asc
  limit 1;

  v_resultado := jsonb_build_object(
    'cidade', jsonb_build_object(
      'id', v_cidade.id, 'nome', v_cidade.nome, 'km', v_cidade.km,
      'transportadora', v_cidade.transportadora_nome
    ),
    'faixa', jsonb_build_object('codigo', v_faixa.codigo, 'rotulo', v_faixa.rotulo),
    'fiorino', jsonb_build_object(
      'custo_km', v_custo_km_fiorino,
      'custo_total', v_custo_total_fiorino,
      'pedido_minimo', v_pedido_minimo_fiorino,
      'excede_capacidade', v_fiorino_excede_capac,
      'selo', v_selo_fiorino,
      'detalhamento', jsonb_build_object(
        'combustivel_km', v_params.preco_litro / v_params.fiorino_consumo_km_l,
        'manutencao_km', v_params.fiorino_manutencao_km,
        'pneus_km', v_params.fiorino_pneus_km,
        'depreciacao_km', v_params.fiorino_depreciacao_km,
        'seguro_km', v_params.fiorino_seguro_km
      )
    ),
    'iveco', jsonb_build_object(
      'custo_km', v_custo_km_iveco,
      'custo_total', v_custo_total_iveco,
      'pedido_minimo', v_pedido_minimo_iveco,
      'selo', v_selo_iveco,
      'detalhamento', jsonb_build_object(
        'combustivel_km', v_params.preco_litro / v_params.iveco_consumo_km_l,
        'manutencao_km', v_params.iveco_manutencao_km,
        'pneus_km', v_params.iveco_pneus_km,
        'depreciacao_km', v_params.iveco_depreciacao_km,
        'seguro_doc_km', v_params.iveco_seguro_doc_km
      )
    ),
    'transportadora', jsonb_build_object('custo', v_frete_transportadora, 'selo', v_selo_transportadora),
    'volume', case when v_custo_volume is not null
                   then jsonb_build_object('quantidade', p_volumes, 'custo', v_custo_volume)
                   else null end,
    'recomendacao_categorica', v_recomendacao,
    'vencedor', v_vencedor
  );

  insert into public.historico_simulacoes (
    usuario_id, cidade_id, km, peso, valor_pedido, quantidade_volumes,
    modal_vencedor, custo_vencedor, resultado
  ) values (
    auth.uid(), p_cidade_id, v_cidade.km, p_peso, p_valor, p_volumes,
    v_vencedor ->> 'modal', (v_vencedor ->> 'custo')::numeric, v_resultado
  );

  return v_resultado;
end;
$$;

grant execute on function public.simular_frete(uuid, numeric, numeric, integer) to authenticated;
revoke execute on function public.simular_frete(uuid, numeric, numeric, integer) from anon;
