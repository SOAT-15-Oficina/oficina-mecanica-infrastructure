# Fase 4 — checklist para colocar o ambiente no ar

O código da Fase 4 está pronto e validado localmente: os três serviços, a Lambda
e o painel rodam juntos em `local/docker-compose.local.yml`, e os quatro cenários
BDD (caminho feliz e compensações A, B e C) passam contra eles. O que segue é o
que **só pode ser feito fora daqui**: GitHub, AWS, Mercado Pago e Datadog.

Siga na ordem; cada bloco depende do anterior. Ambiente de referência:
homologação (`hml` → `homolog`). Produção repete os blocos 5 a 7 com `main` →
`production` / `prod`.

Conta AWS `881757053222`, região `sa-east-1`, credencial humana
`AWS_PROFILE=esantana` (o perfil `default` tem chave inválida).

## 1. Repositórios no GitHub

- [x] Renomear `SOAT-15-Oficina/oficina-mecanica-monolith` para
      `oficina-mecanica-os-service`
      (`gh repo rename oficina-mecanica-os-service -R SOAT-15-Oficina/oficina-mecanica-monolith`).
      O ID numérico (1349770766) se mantém, e a trust policy do OIDC já usa
      esse ID.
- [x] Atualizar o remote local:
      `git -C oficina-mecanica-monolith remote set-url origin git@github.com:SOAT-15-Oficina/oficina-mecanica-os-service.git`.
      Se também renomear o diretório local, exporte
      `OS_SERVICE_CONTEXT=../../oficina-mecanica-os-service` antes de subir o
      compose local (ver `local/README.md`).
- [x] Criar os repositórios públicos `oficina-mecanica-billing-service` e
      `oficina-mecanica-execution-service` na organização e enviar o `main` local
      de cada um (`git remote add origin ...` + `git push -u origin main`).
      Depois criar `hml` a partir de `main` nos dois.
- [x] Anotar os IDs dos dois repositórios novos
      (`gh api repos/SOAT-15-Oficina/oficina-mecanica-billing-service --jq .id`)
      e acrescentá-los a `github_repository_ids` (hoje em `bootstrap/variables.tf`)
      (chaves `"billing-service"` e `"execution-service"`). Sem isso, a trust
      policy aceita só o `sub` clássico.
- [x] Ampliar o token `CROSS_REPO_DISPATCH_TOKEN` (secret do
      `-infrastructure`) para incluir `actions:write` nos dois repositórios novos
      e no renomeado: o `bring-up.yml` dispara o `ci.yml` de cada um.
- [x] Adicionar `soat-architecture` como colaborador nos seis repositórios
      (pendência que vem da Fase 3).

## 2. Branches e Pull Requests

Nada foi enviado ao remoto. Branches locais prontas:

| Repositório | Branch local | Destino |
|---|---|---|
| `oficina-mecanica-infrastructure` | `feat/fase4-plataforma` (contém `docs/fase4-microsservicos`) | PR para `hml` |
| `oficina-mecanica-os-service` | `feat/fase4-os-service` | PR para `hml` |
| `oficina-mecanica-serverless` | `feat/fase4-auth-via-os-service` | PR para `hml` |
| `oficina-mecanica-frontend` | `feat/fase4-microsservicos` | PR para `hml` |
| `oficina-mecanica-billing-service` | `main` | push inicial (item 1) |
| `oficina-mecanica-execution-service` | `main` | push inicial (item 1) |

- [x] Abrir os PRs e conferir os checks. O job `bdd` do OS Service faz
      checkout de `main` dos repositórios irmãos: ele só passa depois que o
      `-infrastructure` (compose local) e os dois serviços novos estiverem em
      `main`. Até lá, aceite-o vermelho ou rode o BDD localmente (README do OS
      Service, seção "Teste BDD do fluxo completo").
- [x] `bootstrap/terraform.tfstate` está modificado e **não commitado** (é o
      state depois do destroy de 23/09). Commitar junto com o novo apply do
      bloco 3.

## 3. Bootstrap (uma vez)

- [x] `cd bootstrap && AWS_PROFILE=esantana terraform init && terraform apply`
      (bucket `oficina-mecanica-tfstate-881757053222` e tabela
      `oficina-mecanica-tflock`).
- [x] Commitar o `bootstrap/terraform.tfstate` resultante.

## 4. Configuração dos repositórios novos e do renomeado

Para `oficina-mecanica-billing-service`, `oficina-mecanica-execution-service` e
`oficina-mecanica-os-service`:

- [x] GitHub Environments `homolog` e `production` (production com revisor
      obrigatório, como nos outros).
- [x] Variable de repositório `AWS_REGION=sa-east-1`.
- [x] Só no OS Service: variable `SES_SENDER_EMAIL=emersonsantana.dev@gmail.com`.
- [x] Branch protection em `main` e `hml` com os required checks `lint`, `test`
      e `quality` (no OS Service, também `bdd`), no mesmo padrão de
      2026-09-14: 0 aprovações, conversas resolvidas, sem force-push.
- [x] No OS Service renomeado, revisar a lista de required checks: o job
      `bdd` é novo.

## 5. Roles de deploy e bring-up de homologação

Desde a [ADR-0018](adr/0018-camada-unica-de-terraform.md) não há camada
persistente: as roles ficam no `bootstrap/` e todo o resto em `platform/`, que o
`bring-up` cria e o `tear-down` destrói.

- [x] Aplicar o `bootstrap/` com credencial humana e commitar o
      `bootstrap/terraform.tfstate` (12 roles `oficina-mecanica-{homolog,prod}-gha-<repo>`
      em 2026-11-15; em seguida a política
      `oficina-mecanica-{homolog,prod}-service-boundary` e o `rds:*` restrito
      aos recursos de cada serviço).
- [x] Cadastrar `AWS_DEPLOY_ROLE_ARN` no Environment `homolog` dos seis
      repositórios: `arn:aws:iam::881757053222:role/oficina-mecanica-homolog-gha-<repo>`.
- [x] Segredos do `-infrastructure` no Environment `homolog`:
      `DATADOG_API_KEY` e `DATADOG_APP_KEY` (conta nova, `datadoghq.com`).
- [x] `destroy.yml` dos três serviços em `hml` e `main`.
- [x] `bring-up.yml` com `environment=homolog` na branch `hml`. Ordem:
      `platform/` → Billing e Execution em paralelo → OS Service → serverless
      e frontend.
- [ ] **Produção:** repetir com `main` / `production`. Antes, cadastrar
      `AWS_DEPLOY_ROLE_ARN` (role `prod`) e os segredos do Datadog da conta nova
      no Environment `production` de cada repositório, e os secrets do Mercado
      Pago do bloco 6 no Environment `production` do Billing.

## 6. Mercado Pago (QR Code dinâmico)

Feito uma vez, na conta de teste do vendedor:

- [x] Aplicação de **QR Code** (pagamentos presenciais), loja `OFICINAMATRIZ`
      e caixa `OFICINAMATRIZPOS01` (criados pelo `mp-setup` do Billing).
- [x] Usuário de teste comprador para pagar pelo app.

A cada ambiente, uma vez:

- [ ] Cadastrar no GitHub Environment do Billing (`homolog` e `production`):
      ```bash
      R=SOAT-15-Oficina/oficina-mecanica-billing-service
      gh secret set MERCADOPAGO_ACCESS_TOKEN   --env homolog -R $R
      gh secret set MERCADOPAGO_WEBHOOK_SECRET --env homolog -R $R
      ```
      As variables `SES_SENDER_EMAIL` e `MERCADOPAGO_APP_ID` já estão
      cadastradas nos dois Environments. O deploy do Billing grava esses
      valores no Secrets Manager a cada execução (passo **Update provider
      credentials**), então não é mais preciso editar o segredo nem rodar o
      `ci.yml` de novo depois do bring-up.

A cada bring-up (o domínio do CloudFront muda):

- [ ] Copiar a URL do webhook do resumo do run do Billing (seção "Webhook do
      Mercado Pago", com link direto para a tela de webhooks da aplicação) e
      colar no painel, evento **Order (Mercado Pago)**. É o único passo manual
      que sobra: o Mercado Pago não tem API para cadastrar o webhook da
      aplicação.

## 7. Validação ponta a ponta em homologação

Validado em 2026-11-15 e ambiente derrubado em seguida:

- [x] Login pela Lambda e cadastro pelo painel.
- [x] Caminho feliz até `ENTREGUE` com pagamento real por QR Code no app do
      comprador de teste; Saga `COMPLETED`.
- [x] Caso A (cliente reprova) compensado.
- [x] Caso C (bancada recusa depois do pagamento) com estorno real no
      Mercado Pago.
- [x] Webhook com assinatura inválida responde 401.
- [ ] Caso B (QR expira) só foi provado no BDD local.
- [x] `tear-down.yml` com `confirm=destroy`. O primeiro falhou no bucket do
      Forwarder do Datadog; o passo "Empty Datadog forwarder bucket" resolve.

## 8. Observabilidade

- [x] Conta Datadog nova (`datadoghq.com`) com Log Management ativo; painéis,
      monitores e o painel da Saga sobem com o `platform/`.
- [ ] Depois do próximo bring-up, conferir no APM que uma OS aparece como um
      único trace atravessando os três serviços (o contexto viaja nos message
      attributes do SNS/SQS), e que o painel "Saga" recebe `@event:saga.*`.

## 9. Entregáveis do enunciado

- [x] Evidência de cobertura em cada README: link da execução do CI cujo
      *Summary* traz o resumo do SonarQube do job `quality`. Valores locais:
      OS 83,3%, Billing 95,3%, Execution 95,9%, Lambda 92,4%.
- [ ] Vídeo de até 15 minutos (YouTube ou Vimeo, não listado): fluxo completo,
      Saga com falha e compensação (caso C), deploy automatizado de um serviço
      com os testes passando e o trace distribuído no Datadog.
- [x] PDF: `docs/fase4-entrega.pdf` (participantes, links, diagrama, Saga,
      justificativas). Falta preencher o link do vídeo.

## Pendências de código conhecidas (não bloqueiam o ambiente)

- As ações de security group da role de deploy dos serviços continuam em `*`
  (o EC2 não restringe `CreateSecurityGroup` por nome).
- O `payment_url` da OS continua preenchido depois do pagamento; o painel
  decide pelo status.
- A consulta pública da OS não devolve o `quote_id`: quem só tem código e
  documento vê o status, mas aprova pelo link do e-mail.
