# Diagrama de componentes

Visão de nuvem completa: borda, rede privada, aplicações, banco, serviços
gerenciados e observabilidade. Os quatro repositórios aparecem como donos dos
artefatos que produzem.

```mermaid
flowchart TB
    subgraph clientes [Atores]
        OP[Atendente / mecânico<br/>navegador]
        CLI[Cliente da oficina<br/>link de aprovação por e-mail]
    end

    subgraph edge [Borda — camada persistente]
        CF[CloudFront<br/>1 distribuição, 2 origens<br/>Function remove o prefixo /api]
        S3[(S3 privado<br/>painel web<br/>Origin Access Control)]
        GW[API Gateway HTTP API<br/>única porta pública<br/>throttling 100 rps / burst 200]
    end

    subgraph vpc [VPC — camada efêmera]
        direction TB
        LINK[VPC Link<br/>ENIs em subnets privadas]
        ALB[ALB interno<br/>TargetGroupBinding]

        subgraph eks [EKS 1.31]
            HPA{{HPA<br/>2 a 10 réplicas}}
            POD[Deployment api<br/>monolito Go / Fiber]
            JOB[Job migrate<br/>por deploy]
            MS[metrics-server]
            LBC[aws-load-balancer-controller]
        end

        LMB[Lambda auth<br/>Go / provided.al2023<br/>subnets privadas]
        RDS[(RDS PostgreSQL 17<br/>gp3 criptografado<br/>sem acesso público)]
        NAT[NAT Gateway]
    end

    subgraph aws [Serviços gerenciados]
        SM[Secrets Manager<br/>JWT + credencial do RDS]
        SSM[SSM Parameter Store<br/>contrato entre repositórios]
        SES[SES<br/>orçamento e mudança de status]
        ECR[(ECR)]
    end

    subgraph obs [Observabilidade]
        CWAPI[CloudWatch Logs<br/>access log do API Gateway]
        CWLMB[CloudWatch Logs<br/>Lambda]
        APM[Agente APM / OTel<br/>latência, CPU, memória, uptime]
        DASH[Dashboards e alertas]
    end

    OP --> CF
    CLI --> CF
    CF -->|/*| S3
    CF -->|/api/*| GW
    GW -->|POST /auth/*| LMB
    GW -->|$default| LINK --> ALB --> POD
    HPA -.escala.-> POD
    MS -.métricas.-> HPA
    LBC -.registra targets.-> ALB
    JOB --> RDS
    LMB --> RDS
    POD --> RDS
    LMB --> SM
    POD -->|IRSA| SES
    POD --> NAT --> ECR

    GW -.-> CWAPI
    LMB -.-> CWLMB
    POD -.-> APM
    eks -.-> APM
    CWAPI --> DASH
    CWLMB --> DASH
    APM --> DASH
```

## Quem é dono de quê

| Componente | Repositório dono | Artefato |
|---|---|---|
| CloudFront, S3, API Gateway, ECR, Secrets Manager, SSM, SES, IAM/OIDC | `oficina-mecanica-infrastructure` (`persistent/`) | recursos AWS |
| VPC, NAT, EKS, ALB, RDS, Lambda (a *função*), VPC Link, rotas do API Gateway, todos os objetos Kubernetes | `oficina-mecanica-infrastructure` (`ephemeral/`) | recursos AWS + Kubernetes |
| Imagem do monolito, schema do banco, contrato OpenAPI da API de negócio | `oficina-mecanica-monolith` | imagem no ECR |
| Código da Lambda de autenticação, contrato OpenAPI de `/auth/*` | `oficina-mecanica-serverless` | zip publicado na função |
| Painel web estático | `oficina-mecanica-frontend` | objetos no S3 |

A separação entre *forma* e *conteúdo* é deliberada: o Terraform cria o
`Deployment` e a `aws_lambda_function`, mas ignora a tag da imagem e o
`filename` do zip (`lifecycle.ignore_changes`). Quem publica o artefato é o
pipeline do repositório de código. Ver [ADR-0007](../adr/0007-contrato-entre-repositorios-via-ssm.md).

## Superfície pública

Exatamente um endereço é alcançável da internet: o domínio do CloudFront.

- O bucket S3 só aceita requisições assinadas pelo Origin Access Control.
- O API Gateway aceita qualquer origem, mas só expõe `/auth/*` e o `$default`.
- ALB, EKS, RDS e Lambda vivem em subnets privadas. Não têm IP público e não são
  alcançáveis fora da VPC — o VPC Link é a única ponte, e ele só entra.

Ver [ADR-0003](../adr/0003-api-gateway-como-unica-porta-publica.md).
