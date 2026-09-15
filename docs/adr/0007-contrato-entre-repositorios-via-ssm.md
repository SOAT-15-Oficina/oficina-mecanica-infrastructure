# ADR-0007. Contrato entre repositórios via SSM Parameter Store

**Aceita** · 2026-09-02 · Relacionada [ADR-0006](./0006-duas-camadas-de-terraform.md),
[RFC-0005](../rfc/0005-segregacao-em-repositorios.md)

**Contexto.** Quatro repositórios independentes precisam de identificadores
criados por um quinto lugar: o pipeline do monolito precisa da URL do ECR, do
nome do cluster, do namespace e do nome do Deployment; o da Lambda, do nome da
função; o do frontend, do bucket e do id da distribuição CloudFront. Esses
nomes mudam a cada `bring-up`, porque a camada efêmera recria o cluster do
zero, e deixá-los fixos em workflow significaria quatro repositórios a editar
depois de cada ciclo.

**Decisão.** O `oficina-mecanica-infrastructure` publica no SSM Parameter
Store, sob o prefixo do ambiente, todo identificador que outro repositório
precise. Nenhum pipeline fixa nome de recurso AWS no código.

| Camada que publica | Parâmetros |
|---|---|
| Persistente | `ecr_repository_url`, `frontend_bucket_name`, `public_domain`, `public_base_url`, `api_gateway_id`, `auth_lambda_name`, `ses_configuration_set` |
| Efêmera | `eks_cluster_name`, `eks_cluster_endpoint`, `kube_namespace`, `api_deployment_name`, `api_service_name`, `database_endpoint`, `database_name`, `vpc_id`, `private_subnet_ids`, `alb_dns_name` |

```bash
get() { aws ssm get-parameter --name "${SSM_PREFIX}/$1" --query Parameter.Value --output text; }
echo "ECR_REPOSITORY_URL=$(get ecr_repository_url)" >> "$GITHUB_ENV"
```

`SSM_PREFIX` é derivado da branch, e não de input ([ADR-0008](./0008-oidc-para-os-pipelines.md)).

**Segredo não vai para o SSM.** Chave JWT e credencial do RDS ficam no Secrets
Manager; o SSM guarda apenas identificadores, que não são sigilosos.

Complemento necessário: o Terraform cria a *forma* dos recursos de aplicação
(Deployment, função Lambda) mas ignora o *conteúdo*, porque a tag da imagem e o
`filename` do zip vivem sob `lifecycle.ignore_changes`. O Terraform é dono da
forma; o CD é dono do artefato.

## Alternativas descartadas

| Opção | Motivo do descarte |
|---|---|
| GitHub Variables por repositório | ~10 variáveis, vezes 2 ambientes, vezes 4 repositórios, atualizadas à mão a cada bring-up |
| `terraform_remote_state` nos outros repositórios | daria leitura do state completo, que contém a senha do RDS e a chave JWT, a três pipelines que não precisam dela |
| Outputs commitados em arquivo | exigiria commit automático entre repositórios, ou submódulo: acoplamento pior |
| Convenção de nomes determinística | já existe em parte (prefixo `oficina-mecanica-<env>-`), mas a URL do ECR contém id de conta e região, e o domínio do CloudFront é gerado |

## Consequências

| Ganhos | Custos |
|---|---|
| Um bring-up muda os identificadores e nenhum repositório precisa ser editado | **acoplamento por nome de parâmetro, não validado em tempo de plan**: renomear quebra o consumidor só na execução seguinte. Mitigação: a lista vive em um `locals` por camada, e os workflows falham alto quando o `get` volta vazio |
| Adicionar um consumidor é adicionar um `get`, sem coordenação de secrets | todo job de deploy precisa de credencial AWS antes de qualquer coisa, inclusive o do frontend, que só faz `s3 sync` |
| Contrato inspecionável: `aws ssm get-parameters-by-path` mostra o estado real | mais uma dependência de runtime: SSM indisponível significa deploy parado |
| Custo zero, no Standard tier | |
