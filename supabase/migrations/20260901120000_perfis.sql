-- =============================================================================
-- 01. PERFIS (papéis de usuário: admin / vendedor)
-- =============================================================================
-- Autenticação real fica a cargo do Supabase Auth (auth.users). Esta tabela
-- guarda só o que é específico da aplicação: nome de exibição e papel.
-- Decisão: perfis.id = auth.users.id (relação 1:1), em vez de criar roles
-- separadas no Postgres para admin/vendedor. Isso porque o RLS do Supabase
-- é avaliado por linha usando auth.uid() dentro de uma única role de
-- conexão ("authenticated") — não existem duas roles de banco distintas
-- para admin/vendedor. Toda a distinção de permissão vem das policies
-- abaixo, que consultam esta tabela.

create type public.papel_usuario as enum ('admin', 'vendedor');

create table public.perfis (
  id        uuid primary key references auth.users (id) on delete cascade,
  nome      text not null,
  papel     public.papel_usuario not null default 'vendedor',
  criado_em timestamptz not null default now()
);

comment on table public.perfis is
  'Perfil de aplicação (nome + papel) de cada usuário autenticado. 1:1 com auth.users.';

-- -----------------------------------------------------------------------------
-- Função auxiliar is_admin()
-- -----------------------------------------------------------------------------
-- SECURITY DEFINER é necessário aqui: se fosse SECURITY INVOKER, a checagem
-- "select ... from perfis where id = auth.uid()" dispararia a própria RLS de
-- perfis (que chama is_admin()) e entraria em recursão / bloquearia a leitura
-- antes mesmo de decidir se o usuário é admin. Rodando como definer, esta
-- função específica ignora a RLS só para essa checagem pontual e segura
-- (ela não devolve dados, só um boolean).
create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.perfis
    where id = auth.uid() and papel = 'admin'
  );
$$;

-- -----------------------------------------------------------------------------
-- Cria perfil automaticamente quando um usuário se cadastra no Supabase Auth
-- -----------------------------------------------------------------------------
-- Todo usuário novo entra como 'vendedor' por padrão; promover a admin é uma
-- ação explícita feita depois, pela tela de Usuários (só admin pode fazer).
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.perfis (id, nome, papel)
  values (new.id, coalesce(new.raw_user_meta_data ->> 'nome', new.email), 'vendedor');
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- -----------------------------------------------------------------------------
-- Regra de negócio (seção 6.6 do documento): não deletar o próprio usuário
-- logado, nem o único admin do sistema. Também bloqueamos "rebaixar" o
-- último admin para vendedor pelo mesmo motivo (extensão razoável da regra).
-- -----------------------------------------------------------------------------
create or replace function public.proteger_perfil()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'DELETE' then
    if old.id = auth.uid() then
      raise exception 'Não é permitido excluir o próprio usuário logado.';
    end if;
    if old.papel = 'admin' and (select count(*) from public.perfis where papel = 'admin') <= 1 then
      raise exception 'Não é permitido excluir o único admin do sistema.';
    end if;
    return old;
  end if;

  if tg_op = 'UPDATE' then
    if old.papel = 'admin' and new.papel <> 'admin'
       and (select count(*) from public.perfis where papel = 'admin') <= 1 then
      raise exception 'Não é permitido rebaixar o único admin do sistema.';
    end if;
    return new;
  end if;

  return new;
end;
$$;

create trigger before_delete_perfil
  before delete on public.perfis
  for each row execute function public.proteger_perfil();

create trigger before_update_perfil
  before update on public.perfis
  for each row execute function public.proteger_perfil();

-- -----------------------------------------------------------------------------
-- RLS
-- -----------------------------------------------------------------------------
alter table public.perfis enable row level security;

revoke all on public.perfis from anon;
grant select, update, delete on public.perfis to authenticated;
-- Sem "insert" para authenticated: perfis só nasce via trigger on_auth_user_created.

create policy "usuario ve o proprio perfil"
  on public.perfis for select
  to authenticated
  using (id = auth.uid());

create policy "admin ve todos os perfis"
  on public.perfis for select
  to authenticated
  using (public.is_admin());

create policy "admin atualiza perfis"
  on public.perfis for update
  to authenticated
  using (public.is_admin())
  with check (public.is_admin());

create policy "admin exclui perfis"
  on public.perfis for delete
  to authenticated
  using (public.is_admin());
