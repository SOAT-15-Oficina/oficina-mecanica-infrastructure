# ADR-0017. Infraestrutura e manifestos Kubernetes no repositório do serviço

**Proposta** · 2026-11-11 · Origem [RFC-0006](../rfc/0006-microsservicos-e-saga.md) ·
Revisa [RFC-0005](../rfc/0005-segregacao-em-repositorios.md)

**Contexto.** O enunciado pede que cada microsserviço tenha repositório,
infraestrutura, Dockerfile, manifestos Kubernetes e pipeline próprios, com deploy
automatizado em Kubernetes. Na Fase 3 os manifestos viviam em
`ephemeral/k8s.tf` deste repositório.

**Decisão.**

- `oficina-mecanica-infrastructure` fica com a **plataforma compartilhada**:
  VPC, EKS, AWS Load Balancer Controller, API Gateway, CloudFront e
  observabilidade. Publica no SSM o que os serviços consomem
  ([ADR-0007](./0007-contrato-entre-repositorios-via-ssm.md)).
- Cada serviço tem `infra/` (Terraform com state próprio: banco, filas e tópico
  que possui, role IRSA, ECR, segredos, target group e regra de caminho no
  listener do ALB interno) e `k8s/` (kustomize: Deployment, Service, HPA, PDB,
  ServiceAccount e `TargetGroupBinding`).
- O ALB continua no Terraform da plataforma, porque o VPC Link precisa do ARN do
  listener no plan; por isso o serviço não usa `Ingress`.
- O pipeline do serviço aplica `infra/` e depois `kubectl apply -k k8s/`, com a
  imagem fixada pelo SHA do commit.

## Alternativas descartadas

| Opção | Motivo do descarte |
|---|---|
| Manifestos continuarem no Terraform da plataforma | todo deploy de serviço exigiria PR no repositório da plataforma |
| `Ingress` com IngressGroup | o ALB nasceria assíncrono, criado pelo controller, e o VPC Link do API Gateway não teria o ARN do listener no plan |
| Helm chart por serviço | templating sem necessidade: as diferenças entre ambientes cabem em overlays do kustomize |
| GitOps (Argo CD) | mais um componente no cluster; o pipeline já faz o deploy com OIDC |

## Consequências

| Ganhos | Custos |
|---|---|
| serviço inteiro, código e infraestrutura, num PR só | quatro states de Terraform a manter |
| deploy de um serviço não toca nos outros | ordem de bring-up: plataforma antes dos serviços |
| atende literalmente o enunciado | trechos de pipeline repetidos entre repositórios |
