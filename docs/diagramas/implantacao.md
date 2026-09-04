# Diagrama de implantação

Onde cada artefato roda, quem o publica e por qual caminho.

```mermaid
flowchart LR
    subgraph gh [GitHub — 4 repositórios]
        R1[oficina-mecanica-infrastructure]
        R2[oficina-mecanica-monolith]
        R3[oficina-mecanica-serverless]
        R4[oficina-mecanica-frontend]
    end

    subgraph iam [AWS IAM]
        OIDC[OIDC provider<br/>token.actions.githubusercontent.com]
        RL[4 roles, uma por repositório<br/>por ambiente]
    end

    subgraph runtime [AWS — ambiente]
        TF[(state no S3<br/>lock no DynamoDB)]
        ECR[(ECR)]
        EKS[EKS — Deployment api]
        LMB[Lambda auth]
        S3F[(S3 — painel)]
        CFD[CloudFront]
        SSMP[SSM Parameter Store]
    end

    R1 -->|terraform apply| TF
    R1 -->|cria recursos| runtime
    R1 -->|publica identificadores| SSMP

    R2 -->|docker build/push| ECR
    R2 -->|Job migrate + kubectl set image| EKS
    R3 -->|update-function-code| LMB
    R4 -->|s3 sync + invalidation| S3F
    S3F --- CFD

    SSMP -.lido por.-> R2
    SSMP -.lido por.-> R3
    SSMP -.lido por.-> R4

    R1 -.assume.-> RL
    R2 -.assume.-> RL
    R3 -.assume.-> RL
    R4 -.assume.-> RL
    OIDC --> RL
```

## Branch → ambiente

Nenhum workflow de aplicação aceita input de ambiente. O `ref` já carrega a
informação, e um input separado poderia contradizê-lo.

| Branch | GitHub Environment | Prefixo no SSM | Roles |
|---|---|---|---|
| `hml` | `homolog` | `/oficina-mecanica/homolog` | `oficina-mecanica-homolog-gha-*` |
| `main` | `production` | `/oficina-mecanica/prod` | `oficina-mecanica-prod-gha-*` |

A regra é repetida do lado da AWS: a trust policy da role de homologação só
aceita `ref:refs/heads/hml` e `environment:homolog`. Um push em `hml` não obtém
credencial de produção nem trocando o ARN do secret.

## Ordem de um ciclo completo

```mermaid
sequenceDiagram
    autonumber
    actor DEV as Mantenedor
    participant GHA as GitHub Actions
    participant TF as Terraform
    participant AWS as AWS
    participant APP as Pipelines de aplicação

    DEV->>GHA: bring-up.yml (manual, input environment)
    GHA->>GHA: aborta se o input não bate com a branch
    GHA->>TF: apply da camada efêmera
    TF->>AWS: VPC, NAT, EKS, RDS, ALB, Lambda, VPC Link, objetos K8s
    TF->>AWS: publica identificadores no SSM
    Note over AWS: o Deployment sobe com registry.k8s.io/pause —<br/>nenhum target saudável ainda, o que é esperado
    GHA->>APP: dispara ci.yml dos 3 repositórios com --ref da branch
    APP->>AWS: monolith: imagem → Job migrate → rollout
    APP->>AWS: serverless: zip → update-function-code → invoke de fumaça
    APP->>AWS: frontend: s3 sync → invalidação do CloudFront
    GHA->>AWS: verifica o endpoint público
    GHA-->>DEV: URL do ambiente
```

O `tear-down.yml` faz o inverso e **verifica que nada sobrou**: remove os
`TargetGroupBinding` antes do destroy (senão o controller recria targets em um
ALB que o Terraform está removendo) e falha se algum recurso da camada efêmera
persistir.

A camada persistente não participa desse ciclo — ver
[ADR-0006](../adr/0006-duas-camadas-de-terraform.md).
