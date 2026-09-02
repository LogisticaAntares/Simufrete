# Schema do SimuFrete — Supabase/Postgres

Este diretório contém as migrações que criam o banco de dados do SimuFrete a
partir do zero, implementando as seções 3 e 4 do documento de contexto do
projeto. Foram testadas de ponta a ponta (RLS + fórmulas de cálculo) em um
Postgres 16 local antes da entrega — ver `../../test/`.

## Como aplicar

Com a [Supabase CLI](https://supabase.com/docs/guides/cli):

```bash
supabase link --project-ref <seu-projeto>
supabase db push
```

Ou, para rodar contra qualquer Postgres (ex.: um Postgres local com o schema
`auth` e as roles `anon`/`authenticated` já existentes, como todo projeto
Supabase real tem por padrão):

```bash
for f in migrations/*.sql; do psql "$DATABASE_URL" -f "$f"; done
```

## Ordem dos arquivos

| Arquivo | Conteúdo |
|---|---|
| `20260901115900_extensions.sql` | `pgcrypto`, `pg_trgm` |
| `20260901120000_perfis.sql` | Papéis (admin/vendedor), `is_admin()`, trigger de criação automática de perfil, regras de proteção contra auto-exclusão / exclusão do único admin |
| `20260901120100_transportadoras.sql` | CRUD simples, seed com as 3 transportadoras do protótipo |
| `20260901120200_faixas_km.sql` | Faixas de distância + `calcular_faixa(km)` |
| `20260901120300_cidades.sql` | Cidades (sem colunas de custo) + view `cidades_com_faixa` |
| `20260901120400_parametros_custo.sql` | Linha única de parâmetros de custo, leitura/escrita só admin |
| `20260901120500_historico_simulacoes.sql` | Log de simulações (append-only via função, não via INSERT direto) |
| `20260901120600_funcoes_calculo.sql` | Fórmulas (seção 4), view `cidades_com_custo`, função `simular_frete()` (seção 5) |

## Decisões de arquitetura (explicadas antes de implementar, como pedido)

### 1. Papéis via tabela `perfis`, não roles separadas do Postgres
O Supabase autentica todo mundo como a mesma role de conexão
(`authenticated`); não existem roles distintas para admin/vendedor no nível
do Postgres. Por isso `perfis.papel` + a função `is_admin()` (que lê
`auth.uid()`) são a única fonte de verdade sobre permissão, e toda política
de RLS consulta essa função.

### 2. Nada de custo/faixa "congelado" em `cidades`
Como pedido explicitamente na seção 3.1: a tabela `cidades` só guarda `km`.
Faixa, custo Fiorino/Iveco e pedido mínimo são sempre recalculados em tempo
de consulta (`calcular_faixa()`, `calcular_custos_cidade()`), nunca gravados
como coluna. Isso elimina qualquer necessidade de trigger de recálculo em
massa quando o admin edita um parâmetro ou um limite de faixa — a próxima
leitura já reflete o valor novo, automaticamente e sem custo de manutenção.

### 3. Ocultar custo do vendedor exige uma função `SECURITY DEFINER`, não dá para fazer só com RLS
Esse foi o ponto mais delicado do desenho. RLS no Postgres filtra **linhas**,
não colunas — e como admin e vendedor conectam como a mesma role
(`authenticated`), não existe "esconder a coluna X só para vendedor" dentro
da mesma tabela. A solução adotada:

- `parametros_custo` tem RLS de leitura **só para admin**. O vendedor nunca
  consegue fazer `select * from parametros_custo`, nem indiretamente via
  `cidades_com_custo` (a view usa `security_invoker = true`, então a RLS da
  tabela por baixo é avaliada com a identidade de quem consulta a view, não
  de quem a criou — outro detalhe fácil de errar no Postgres/Supabase, e que
  testei explicitamente).
- Só a função `simular_frete()`, marcada `SECURITY DEFINER`, tem permissão
  de ler `parametros_custo` independentemente de quem a chamou. Ela devolve
  o resultado já calculado (o que o vendedor **tem** que ver na tela de
  Simulador, incluindo o detalhamento de custo) sem nunca expor a tabela de
  parâmetros crus. Isso bate com a distinção da seção 2 do documento: a
  restrição vale para a listagem de "Base de dados", não para o resultado de
  uma simulação.

### 4. `historico_simulacoes` é a exceção proposital à regra 2
Diferente de `cidades`, aqui congelar o valor calculado no momento é
correto: é um log de auditoria de "o que foi mostrado ao vendedor naquele
dia", que não deve mudar retroativamente se o admin alterar um parâmetro
depois. Por isso ele grava um snapshot completo (`resultado jsonb`).

### 5. Histórico só é gravado pela própria função de simulação
Não existe policy de `INSERT` para `authenticated` em `historico_simulacoes`
— só `simular_frete()` (rodando como definer) grava. Isso impede que um
vendedor insira diretamente uma linha forjada (ex.: um custo vencedor
inventado) no histórico; o valor salvo é garantidamente o que o servidor
calculou, na mesma transação.

### 6. Regras de proteção de usuário como trigger, não só RLS
"Não excluir o próprio usuário logado" e "não excluir/rebaixar o único
admin" (seção 6, tela Usuários) dependem de contar linhas da própria tabela
(`count(*) from perfis where papel='admin'`) — mais natural como trigger
`BEFORE DELETE/UPDATE` com mensagem de erro clara do que como `USING` de
RLS. Ambos os casos foram testados.

## Decisões em aberto (não assumidas por conta própria)

- **`dias_coleta`**: modelado como texto livre (ex. `'Seg, Qua, Sex'`),
  espelhando o protótipo. Se a equipe quiser filtrar por dia da semana no
  futuro, vale migrar para um array de um enum de dias — mudança de schema
  simples, mas prefiro confirmar com vocês antes.
- **Login usuário + senha numérica → Supabase Auth**: Supabase Auth é
  nativamente baseado em e-mail (ou telefone/OTP). O schema aqui já assume
  `perfis.id = auth.users.id`, então funciona com qualquer estratégia, mas a
  migração de "usuário" para "e-mail" (e-mail sintético tipo
  `usuario@interno.simufrete` vs. exigir e-mail real de cada vendedor) ainda
  precisa ser decidida antes de implementar a tela de login.

## Testes

`../../test/00_shim_supabase.sql` recria um `auth` schema + roles
`anon`/`authenticated` mínimos (o suficiente para simular o ambiente
Supabase num Postgres comum), e `../../test/01_teste_rls_e_calculo.sql`
roda como admin e como vendedor, cobrindo: cálculo de faixa por km,
fórmulas de custo/pedido mínimo, recomendação categórica nas 5 situações da
seção 5.1, vencedor por menor custo (seção 5.2), selos de viabilidade
(seção 5.3), vendedor sem acesso a `parametros_custo`/`cidades_com_custo`,
histórico visível a ambos os papéis, bloqueio de insert direto no
histórico, bloqueio de exclusão de cidade por vendedor, e as 3 regras de
proteção de usuário (auto-exclusão, exclusão do único admin, rebaixamento
do único admin). Os 16 cenários passaram.
