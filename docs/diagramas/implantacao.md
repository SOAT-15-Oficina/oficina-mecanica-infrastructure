# Implantação e ciclo do ambiente

Onde cada artefato roda, quem o publica e por qual caminho. Na Fase 4 cada
serviço aplica o próprio Terraform (`infra/`) e os próprios manifestos (`k8s/`)
([ADR-0017](../adr/0017-infra-e-manifestos-no-repositorio-do-servico.md)); a
plataforma cria o que é compartilhado e publica no SSM o que eles consomem. As
setas pontilhadas são leitura do contrato no SSM e a relação de confiança do
IAM.

```mermaid
flowchart LR
    subgraph gh [GitHub: 6 repositórios]
        R1[oficina-mecanica-infrastructure]
        RO[oficina-mecanica-os-service]
        RB[oficina-mecanica-billing-service]
        RE[oficina-mecanica-execution-service]
        R3[oficina-mecanica-serverless]
        R4[oficina-mecanica-frontend]
    end

    subgraph iam [AWS IAM]
        OIDC[OIDC provider<br/>token.actions.githubusercontent.com]
        RL["bootstrap/: 6 roles por ambiente<br/>oficina-mecanica-&lt;env&gt;-gha-&lt;repo&gt;"]
    end

    subgraph runtime [AWS: ambiente]
        TF[(state no S3<br/>um prefixo por repositório)]
        PLAT[Plataforma: VPC, EKS, ALB e listener,<br/>API Gateway, Lambda, CloudFront]
        SVC[infra/ de cada serviço: RDS ou DynamoDB,<br/>filas e tópico, IRSA, ECR, regra no listener]
        EKS[EKS: kustomize de cada serviço]
        LMB[Lambda auth]
        S3F[(S3: painel)]
        SSMP[SSM Parameter Store]
    end

    R1 -->|terraform apply| PLAT
    R1 -->|publica identificadores| SSMP
    RO -->|terraform apply infra/| SVC
    RB -->|terraform apply infra/| SVC
    RE -->|terraform apply infra/| SVC
    RO -->|kubectl apply -k, Job migrate| EKS
    RB -->|kubectl apply -k, Job migrate| EKS
    RE -->|kubectl apply -k| EKS
    R3 -->|update-function-code| LMB
    R4 -->|s3 sync + invalidation| S3F
    R1 --> TF
    SVC --> TF

    SSMP -.lido por.-> RO
    SSMP -.lido por.-> RB
    SSMP -.lido por.-> RE
    SSMP -.lido por.-> R3
    SSMP -.lido por.-> R4

    OIDC --> RL
    gh -.assume.-> RL
```

## Bootstrap e camada única de Terraform

| Diretório | Custo | Conteúdo | Aplicação | No tear-down |
|---|---|---|---|---|
| `bootstrap/` | centavos | bucket de state, tabela de lock e as 12 roles de deploy (6 repositórios × 2 ambientes) | à mão, state local versionado | fica |
| `platform/` | ~US$ 0,30/h ligada, zero desligada | VPC, NAT, EKS, namespace e RBAC dos pipelines, ALB interno e listener, add-ons, Lambda, API Gateway com rotas e VPC Link, CloudFront e S3 do painel, segredos do JWT e do token de serviço, configuration set do SES, SSM, Datadog | `bring-up.yml` | destruída |
| `infra/` de cada serviço | dois RDS e DynamoDB sob demanda | banco, filas e tópico, IRSA, ECR, segredo, target group e regra | `ci.yml` do serviço | `destroy.yml` do serviço |

O state de `platform/` fica em `<ambiente>/platform/terraform.tfstate` e o de
cada serviço em `<ambiente>/<repo>/terraform.tfstate`, no mesmo bucket. A
identidade SES do remetente fica fora do Terraform e é só lida, para não exigir
nova verificação por e-mail a cada ciclo. Com o ambiente desligado não existe
domínio público: o CloudFront nasce com um domínio novo a cada bring-up
([ADR-0018](../adr/0018-camada-unica-de-terraform.md)).

## Branch decide ambiente

| Branch | GitHub Environment | Prefixo no SSM | Roles |
|---|---|---|---|
| `hml` | `homolog` | `/oficina-mecanica/homolog` | `oficina-mecanica-homolog-gha-*` |
| `main` | `production` | `/oficina-mecanica/prod` | `oficina-mecanica-prod-gha-*` |

Nenhum workflow de aplicação aceita input de ambiente: o `ref` já carrega a
informação. A regra é repetida do lado da AWS, e a trust policy da role de
homologação só aceita `ref:refs/heads/hml` e `environment:homolog`
([ADR-0008](../adr/0008-oidc-para-os-pipelines.md)). `bring-up` e `tear-down` têm input porque são manuais,
mas abortam se ele não bater com o ref de onde foram disparados.

## Ordem de um ciclo completo

```mermaid
sequenceDiagram
    autonumber
    actor DEV as Mantenedor
    participant GHA as GitHub Actions
    participant TF as Terraform
    participant AWS as AWS
    participant APP as Pipelines dos repositórios

    DEV->>GHA: bring-up.yml (manual, input environment)
    GHA->>GHA: aborta se o input não bate com a branch
    GHA->>TF: apply de platform/
    TF->>AWS: VPC, NAT, EKS, ALB (listener 404), Lambda, API Gateway,<br/>CloudFront, segredos, Datadog
    TF->>AWS: publica no SSM (inclui eks_oidc_provider_arn,<br/>eks_node_security_group_id, alb_listener_arn)
    GHA->>APP: billing-service e execution-service em paralelo
    APP->>AWS: infra/ (banco, inbox, tópico, regra de prefixo), imagem, kustomize
    GHA->>APP: os-service depois dos dois
    APP->>AWS: infra/ (RDS, os-inbox, assinaturas, regra /*), imagem, Job migrate, kustomize
    GHA->>APP: serverless e frontend
    APP->>AWS: zip da Lambda e s3 sync
    GHA-->>DEV: URLs do painel, da API e do webhook do Mercado Pago no resumo do run
```

Billing e Execution vão antes do OS Service porque o `infra/` do OS lê do SSM as
filas de entrada e os tópicos de eventos dos dois (`billing_inbox_queue_arn`,
`billing_events_topic_arn`, `execution_inbox_queue_arn`,
`execution_events_topic_arn`) para assinar a `os-inbox` e ganhar permissão de
envio. Até o OS subir, a regra padrão do listener responde 404 e a Lambda não
autentica, porque a tabela `users` mora no banco do OS.

**Tear-down:** o `tear-down.yml` dispara o `destroy.yml` do OS Service, que
remove os objetos do `k8s/` (liberando o `TargetGroupBinding`) e destrói o
`infra/` dele, inclusive as assinaturas da `os-inbox` nos tópicos dos outros
dois; depois o de Billing e o de Execution em paralelo; e por fim destrói
`platform/`. A checagem final procura VPC, Elastic IP, cluster, RDS, tabela
DynamoDB, distribuição CloudFront e parâmetros SSM do ambiente que tenham
sobrado.

```mermaid
sequenceDiagram
    autonumber
    actor DEV as Mantenedor
    participant GHA as tear-down.yml
    participant OS as os-service destroy.yml
    participant SV as billing e execution destroy.yml
    participant TF as Terraform platform/

    DEV->>GHA: manual, environment + "destroy"
    GHA->>OS: dispara e aguarda
    OS->>OS: kubectl delete do overlay, terraform destroy de infra/
    GHA->>SV: dispara os dois e aguarda
    SV->>SV: kubectl delete do overlay, terraform destroy de infra/
    GHA->>TF: terraform destroy
    GHA->>GHA: verifica que nada sobrou
```

## O que cada pipeline faz

| Repositório | Etapas do deploy |
|---|---|
| `oficina-mecanica-os-service`, `-billing-service`, `-execution-service` | `terraform apply` do `infra/`, lê o SSM, `docker build/push` no ECR do serviço, sincroniza o Secret, `kubectl kustomize \| kubectl apply`, Job `migrate` (OS e Billing) |
| `oficina-mecanica-serverless` | lê o nome da função no SSM, publica o zip com `update-function-code`, faz um `invoke` de fumaça |
| `oficina-mecanica-frontend` | lê bucket e id da distribuição no SSM, `s3 sync`, invalidação do CloudFront |

A role de deploy de cada serviço (`bootstrap/oidc_services.tf`) só alcança
recursos com o nome do próprio serviço: o prefixo do state, o ECR
`oficina-mecanica/<ambiente>/<repo>`, filas e tópicos `oficina-<ambiente>-<serviço>-*`,
a role IRSA `oficina-<ambiente>-<serviço>*`, segredos e parâmetros SSM com o
nome do serviço, o target group próprio e as regras do listener da plataforma.
O acesso ao cluster vem de uma access entry por role, com `AmazonEKSEditPolicy`
no namespace e um `Role` que libera `TargetGroupBinding`. As mesmas permissões
cobrem o `destroy.yml`: cada `Create*` da lista tem o `Delete*` correspondente.

| Tempo ou custo | Valor |
|---|---|
| Do zero até um ambiente demonstrável | 35 a 45 minutos (CloudFront e Forwarder do Datadog entram no ciclo) |
| Destruir a distribuição CloudFront | 15 a 25 minutos (precisa ser desabilitada antes) |
| Tear-down completo | 30 a 45 minutos |
| Ambiente ligado | ~US$ 0,30/hora da plataforma, mais os dois RDS dos serviços |
| Ambiente desligado | ~US$ 0 (só o bucket de state e a tabela de lock) |
