# bootstrap

Aplicado **à mão**, com credencial humana, e **nunca destruído** pelo
tear-down. Resolve os dois ovos-e-galinhas da plataforma:

- o backend remoto precisa de um bucket S3 e de uma tabela de lock que ainda
  não existem;
- os pipelines autenticam por OIDC assumindo roles que ainda não existem — e o
  `bring-up.yml` precisa de uma delas para aplicar `platform/`.

| Recurso | Arquivo |
|---|---|
| Bucket de state `oficina-mecanica-tfstate-<conta>` e tabela de lock `oficina-mecanica-tflock` | `main.tf` |
| As 12 roles de deploy `oficina-mecanica-{homolog,prod}-gha-<repo>`, com trust policy por repositório, branch e GitHub Environment | `oidc.tf` |
| A policy `deploy` de cada role de serviço (state, ECR, filas, banco, IRSA, target group e regra no listener) | `oidc_services.tf` |

Os dois ambientes nascem juntos, por `for_each` em `deploy_environments`. As
permissões de recursos da plataforma (bucket do painel, distribuição do
CloudFront, segredos do JWT e do token de serviço) são escritas por **nome**, e
não por referência, porque esses recursos são criados e destruídos a cada ciclo
pela `platform/`. A distribuição do CloudFront muda de ID a cada bring-up, por
isso a role do frontend pode invalidar qualquer distribuição da conta.

O provider OIDC do GitHub é lido por data source: ele é da conta, existia antes
do projeto e outro projeto depende dele.

Guarda o state **localmente** (`terraform.tfstate`, versionado neste
repositório por ser o único jeito de compartilhá-lo sem um bucket). Não contém
segredo algum.

```bash
cd bootstrap
AWS_PROFILE=esantana terraform init
AWS_PROFILE=esantana terraform plan
AWS_PROFILE=esantana terraform apply
terraform output github_role_arns
```

O plano deve mostrar **apenas criações**; nada no bucket nem na tabela muda.
