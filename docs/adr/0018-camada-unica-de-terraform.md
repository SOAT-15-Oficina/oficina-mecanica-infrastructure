# ADR-0018. Camada única de Terraform

**Aceita** · 2026-11-15 · Substitui [ADR-0006](./0006-duas-camadas-de-terraform.md)

**Contexto.** A [ADR-0006](./0006-duas-camadas-de-terraform.md) separou a
plataforma em `persistent/` (~US$ 1/mês, sempre de pé) e `ephemeral/` (~US$
0,30/h, sob demanda) para manter o domínio do CloudFront estável entre ciclos e
não reverificar o remetente do SES. Na Fase 4 o uso mudou: o ambiente sobe para
validar e gravar a apresentação e é derrubado logo em seguida. Nesse uso:

- o domínio estável não compensa: não há links de aprovação vivos entre um
  ciclo e outro;
- a camada persistente ainda cobra (Secrets Manager, S3, Datadog) e mantém
  painéis e monitores de um ambiente que não existe;
- a fronteira entre camadas obriga a passar o API Gateway, os segredos e o
  Datadog pelo SSM ([ADR-0007](./0007-contrato-entre-repositorios-via-ssm.md)),
  aresta que o Terraform não valida, e o `lifecycle.ignore_changes` no stage do
  gateway;
- o `infra/` de cada serviço ([ADR-0017](./0017-infra-e-manifestos-no-repositorio-do-servico.md))
  vive dentro da VPC, e o tear-down antigo não o destruía: RDS, security groups
  e target groups ficavam para trás e travavam a remoção da VPC.

**Decisão.**

| Diretório | Conteúdo | Aplicação | Destruído no tear-down |
|---|---|---|---|
| `bootstrap/` | bucket de state, tabela de lock e as **12 roles de deploy** (`oficina-mecanica-{homolog,prod}-gha-<repo>`) | à mão, state local versionado | não |
| `platform/` | todo o resto: VPC, NAT, EKS, ALB interno, Lambda, API Gateway e rotas, CloudFront e S3 do painel, segredos do JWT e do token de serviço, configuration set do SES, SSM, Datadog | `bring-up.yml` | sim |
| `infra/` de cada serviço | banco, filas, IRSA, ECR, target group e regra | `ci.yml` do serviço | sim, pelo `destroy.yml` do serviço |

- O state de `platform/` fica em `<ambiente>/platform/terraform.tfstate`, nos dois
  ambientes; produção perde o caminho legado sem prefixo.
- As roles nascem no bootstrap porque o `bring-up.yml` precisa de uma delas
  para aplicar `platform/`. As permissões delas sobre recursos da plataforma
  são escritas por nome (bucket, segredos, função), porque esses recursos
  passam a ser recriados a cada ciclo.
- A **identidade SES** sai do Terraform: é lida por data source e nunca criada
  nem destruída. O *configuration set* continua gerenciado.
- Segredos com `recovery_window_in_days = 0`, para que o próximo bring-up
  recrie o mesmo nome logo depois.
- O `tear-down.yml` dispara o `destroy.yml` do **OS Service** (as assinaturas
  da `os-inbox` estão nos tópicos dos outros dois), depois **Billing e
  Execution em paralelo**, e só então destrói `platform/`.
- O `terraform.yml` deixa de aplicar em push: só valida `bootstrap/` e
  `platform/`. Aplicar `platform/` num merge subiria o ambiente inteiro.

## Alternativas descartadas

| Opção | Motivo do descarte |
|---|---|
| Manter as duas camadas e só criar o destroy por serviço | resolve o tear-down, mas mantém custo e painéis de um ambiente desligado e a aresta pelo SSM |
| Mover para `platform/` também as roles | o `bring-up.yml` assume a role de infraestrutura para aplicar `platform/`: ela não pode nascer nem morrer ali |
| Gerenciar a identidade SES em `platform/` | cada bring-up exigiria clicar de novo no link de verificação |

## Consequências

| Ganhos | Custos |
|---|---|
| Custo zero com o ambiente desligado, a menos do bucket de state | **o domínio do CloudFront muda a cada bring-up**: a URL pública e os links enviados por e-mail num ciclo não valem no seguinte |
| Uma referência direta no lugar de cada parâmetro que passava entre camadas; o Terraform valida tudo | **o webhook do Mercado Pago precisa ser reconfigurado no painel a cada subida** (o `bring-up.yml` imprime a URL no resumo do run) |
| Tear-down sem sobra: serviços e plataforma saem na ordem certa e o workflow confere | **bring-up e tear-down mais longos**: CloudFront, Forwarder do Datadog e segredos entram no ciclo, e o tear-down espera a distribuição ser desabilitada |
| Ambiente novo não precisa de `apply` humano da plataforma: só do bootstrap | painéis, monitores e histórico de silenciamento do Datadog são recriados a cada ciclo |
| Nenhuma reverificação de e-mail no SES | a identidade SES vira pré-requisito fora do código: se não existir verificada, o apply para |
