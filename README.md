# SimuFrete

Simulador de custo de frete da Antares Distribuidora, conectado de verdade ao
Supabase (projeto `xeueqjsomvcwmzloyhns`). Site estático — um único
`index.html`, sem build, sem servidor próprio. Toda regra de negócio
(fórmulas de custo, faixas de distância, permissões admin/vendedor) roda no
Postgres via Row-Level Security e na função `simular_frete()`; este arquivo
só chama a API do Supabase e exibe o resultado.

## Rodar localmente

Não precisa de `npm install` nem de build. Basta servir a pasta com
qualquer servidor estático e abrir no navegador — por exemplo:

```bash
npx serve .
```

ou, com Python:

```bash
python -m http.server 8080
```

(Abrir o arquivo direto com `file://` também funciona na maioria dos casos,
mas um servidor local evita eventuais bloqueios de CORS do navegador.)

## Contas de acesso

- **Admin**: `logistica@antaresdistribuidora.com.br` / `simufrete123`
- Os demais usuários se cadastram sozinhos pela tela de login ("Criar
  conta"). Toda conta nova entra como **vendedor**; o admin promove quem
  precisar pela tela **Usuários** dentro do app.
- Se a confirmação de e-mail estiver ativada no projeto (padrão do
  Supabase), quem se cadastrar recebe um e-mail de confirmação antes de
  conseguir entrar.

**Troque a senha do admin depois do primeiro acesso** (Supabase Dashboard →
Authentication → Users, ou dentro do próprio app quando houver tela de
"esqueci a senha").

## Publicar na Vercel

1. Crie um repositório no GitHub com esta pasta (veja abaixo) ou use o
   Vercel CLI direto.
2. Em [vercel.com/new](https://vercel.com/new), importe o repositório.
3. Não é preciso configurar nada — a Vercel detecta que é um site estático
   (não existe `package.json`) e publica o `index.html` como está.
4. Pronto: a Vercel gera uma URL pública (`https://algo.vercel.app`) já com
   HTTPS.

### Via GitHub (recomendado)

```bash
git init
git add .
git commit -m "SimuFrete conectado ao Supabase"
git branch -M main
git remote add origin <URL do repositório que você criar no GitHub>
git push -u origin main
```

Depois é só importar esse repositório em vercel.com/new.

### Via Vercel CLI (alternativa, exige Node.js instalado)

```bash
npx vercel deploy --prod
```

## Sobre a chave do Supabase no código

O arquivo `index.html` contém a URL do projeto e a chave **anônima
pública** (`anon key`) do Supabase. Isso é esperado e seguro: essa chave
não dá acesso a nada por si só — quem decide o que cada usuário pode ler ou
gravar é o Row-Level Security do banco, não a chave. Nunca coloque aqui a
`service_role key` (essa sim é secreta e nunca deve aparecer em código que
roda no navegador).

## O que cada tabela faz

Ver `supabase/migrations/` (schema original) para o detalhamento completo:
`perfis`, `transportadoras`, `faixas_km`, `cidades`, `parametros_custo`,
`historico_simulacoes`, e a função `simular_frete()`.
