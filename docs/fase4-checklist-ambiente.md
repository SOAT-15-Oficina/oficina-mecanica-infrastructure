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

- [ ] Aplicar o `bootstrap/` com credencial humana. O plano deve ter **só
      criações** (as 12 roles `oficina-mecanica-{homolog,prod}-gha-<repo>`, as
      duas policies `oficina-mecanica-{homolog,prod}-ssm-read` e as policies
      inline e anexos de cada role); nada no bucket nem na tabela muda:
      ```bash
      cd bootstrap
      AWS_PROFILE=esantana terraform init
      AWS_PROFILE=esantana terraform plan -out=roles.tfplan
      AWS_PROFILE=esantana terraform apply roles.tfplan
      terraform output github_role_arns
      ```
- [ ] Commitar o `bootstrap/terraform.tfstate` resultante.
- [ ] Cadastrar `AWS_DEPLOY_ROLE_ARN` no Environment `homolog` dos seis
      repositórios: `arn:aws:iam::881757053222:role/oficina-mecanica-homolog-gha-<repo>`,
      com `<repo>` = `infrastructure`, `os-service`, `billing-service`,
      `execution-service`, `serverless`, `frontend`. Cada ARN vai no repositório
      e no Environment corretos, senão dá `AccessDenied` ao assumir a role.
- [ ] Conferir os segredos do `-infrastructure` no Environment `homolog`:
      `DATADOG_API_KEY` e `DATADOG_APP_KEY` (ver bloco 8), e as variables
      `TF_VAR_SES_VERIFIED_EMAILS` e `TF_VAR_SES_SENDER_EMAIL`.
- [ ] Levar o `destroy.yml` dos três serviços (branch `feat/destroy-workflow`)
      até `hml` **e** `main`: o GitHub só despacha `workflow_dispatch` de um
      workflow que exista na branch padrão.
- [ ] Rodar `bring-up.yml` com `environment=homolog` na branch `hml` do
      `-infrastructure`. Ordem: `platform/` (VPC, EKS, ALB com listener 404,
      Lambda, API Gateway, CloudFront, segredos, Datadog) → **Billing e
      Execution em paralelo** → **OS Service** (o `infra/` dele lê do SSM as
      filas e tópicos dos outros dois) → serverless e frontend.
- [ ] Se algum pipeline de serviço falhar no primeiro apply, rodar de novo o
      `ci.yml` daquele repositório na branch `hml` (`workflow_dispatch`).
- [ ] Anotar as URLs do resumo do run (painel, API e webhook do Mercado Pago):
      o domínio do CloudFront é novo a cada bring-up.
- [ ] Conferir `https://<cloudfront>/api/ping`, `/api/billing/swagger` e
      `/api/execution/swagger`.

## 6. Mercado Pago (credenciais de teste)

- [ ] Criar a aplicação em <https://www.mercadopago.com.br/developers/panel>,
      gerar as **credenciais de teste** (access token `TEST-...`) e os usuários
      de teste (vendedor e comprador).
- [ ] Em Webhooks, configurar a URL
      `https://<cloudfront>/api/billing/webhooks/mercadopago`, evento
      **Pagamentos**, e copiar a **assinatura secreta**.
- [ ] Gravar os dois valores no segredo
      `oficina-mecanica/homolog/billing-service` (chaves
      `MERCADOPAGO_ACCESS_TOKEN` e `MERCADOPAGO_WEBHOOK_SECRET`). O Terraform
      ignora mudanças no conteúdo, então editar pelo console não é revertido.
- [ ] Rodar de novo o `ci.yml` do Billing em `hml`: o deploy sincroniza o
      segredo para o cluster.
- [ ] Testar o webhook pelo simulador do painel do Mercado Pago (deve receber
      200) e conferir que o CloudFront repassa `POST` com query string para
      `/api/*`.
- [ ] **A cada bring-up**, refazer o webhook e o segredo: o domínio do
      CloudFront muda e o `destroy.yml` do Billing apaga o segredo
      `oficina-mecanica/homolog/billing-service`, que volta com `CHANGE_ME`.

## 7. Validação ponta a ponta em homologação

- [ ] Registrar um usuário pelo painel (`/api/auth/register`) e fazer login.
- [ ] Percorrer o caminho feliz pelo painel: abrir OS → bancada (diagnóstico) →
      e-mail do orçamento → aprovar → pagar no checkout de teste com cartão de
      teste → bancada (reparo) → FINALIZADA → entregar.
- [ ] Caso C: marcar a bancada da `MATRIZ` como indisponível antes de pagar e
      conferir `CANCELADA` + pagamento `ESTORNADO` no painel da OS.
- [ ] SES em sandbox só entrega para endereços verificados: incluir o e-mail do
      cliente de teste em `TF_VAR_SES_VERIFIED_EMAILS`, ou pedir acesso de
      produção do SES.
- [ ] Ao terminar a gravação, rodar `tear-down.yml` com
      `environment=homolog`, `confirm=destroy`, na branch `hml`. Ele destrói o
      OS Service, depois Billing e Execution, depois `platform/`, e falha se
      sobrar VPC, Elastic IP, cluster, RDS, tabela DynamoDB, distribuição
      CloudFront ou parâmetro SSM do ambiente.

## 8. Observabilidade

A conta Datadog da Fase 3 ia ser encerrada (memória de 2026-09-23). O
enunciado pede a observabilidade da Fase 3 e o vídeo pede o rastreamento dos
fluxos distribuídos.

- [ ] Decidir: reativar a conta (ou abrir um trial) e cadastrar
      `DATADOG_API_KEY`/`DATADOG_APP_KEY` nos Environments do `-infrastructure`
      com `TF_VAR_DATADOG_ENABLED=true`, **antes** do bring-up do bloco 5.
- [ ] Depois do bring-up, conferir no APM que uma OS aparece como um único
      trace atravessando os três serviços (o contexto viaja nos message
      attributes do SNS/SQS), e que o painel "Saga" recebe `@event:saga.*`.

## 9. Entregáveis do enunciado

- [ ] Evidência de cobertura em cada README: print ou link do resumo do job
      `quality` (SonarQube) do primeiro PR de cada repositório. Valores locais
      medidos em 2026-11-11: OS 83,3%, Billing 94,6%, Execution 95,9%,
      Lambda 92,4%.
- [ ] Vídeo de até 15 minutos (YouTube ou Vimeo, não listado): fluxo completo,
      Saga com falha e compensação (caso C), deploy automatizado de um serviço
      com os testes passando e o trace distribuído no Datadog.
- [ ] PDF: participantes, links dos seis repositórios, link do vídeo, diagrama
      geral (`docs/diagramas/componentes.md` + RFC-0006), estratégia da Saga
      (RFC-0006 seção 4 e ADR-0013) e justificativa da divisão (ADR-0012 e
      ADR-0015).

## Pendências de código conhecidas (não bloqueiam o ambiente)

- A role de deploy dos serviços tem `rds:*` e ações de security group em `*`, e
  as roles IRSA que os serviços criam não têm permissions boundary.
- No OS Service, o `status` de cada item da OS fica `PENDENTE` (o andamento real
  está na ficha do Execution) e o `payment_url` continua preenchido depois do
  pagamento; o painel contorna os dois.
- A consulta pública da OS não devolve o `quote_id`: quem só tem código e
  documento vê o status, mas aprova pelo link do e-mail.
- As mensagens de erro 409 do Billing e do OS estão em inglês.
