# ADR-0007 — Contrato entre repositórios via SSM Parameter Store

- **Estado:** Aceita
- **Data:** 2026-09-02
- **Relacionada:** [ADR-0006](0006-duas-camadas-de-terraform.md), [RFC-0005](../rfc/0005-segregacao-em-repositorios.md)

## Contexto

Quatro repositórios independentes precisam de identificadores criados por um
quinto lugar: o pipeline do monolito precisa da URL do ECR, do nome do cluster,
do namespace e do nome do Deployment; o da Lambda precisa do nome da função; o
do frontend precisa do bucket e do id da distribuição CloudFront.

Esses nomes mudam a cada `bring-up` — a camada efêmera recria o cluster do zero.
Hardcodá-los em workflow significaria quatro repositórios a editar depois de
cada ciclo.

## Decisão

**O `oficina-mecanica-infrastructure` publica no SSM Parameter Store, sob o
prefixo do ambiente, todo identificador que outro repositório precise. Nenhum
pipeline hardcoda nome de recurso AWS.**

```
/oficina-mecanica/homolog/...        /oficina-mecanica/prod/...
```

| Camada que publica | Parâmetros |
|---|---|
| Persistente | `ecr_repository_url`, `frontend_bucket_name`, `public_domain`, `public_base_url`, `api_gateway_id`, `auth_lambda_name`, `ses_configuration_set` |
| Efêmera | `eks_cluster_name`, `eks_cluster_endpoint`, `kube_namespace`, `api_deployment_name`, `api_service_name`, `database_endpoint`, `database_name`, `vpc_id`, `private_subnet_ids`, `alb_dns_name` |

Consumo, no início de cada job de deploy:

```bash
get() { aws ssm get-parameter --name "${SSM_PREFIX}/$1" --query Parameter.Value --output text; }
echo "ECR_REPOSITORY_URL=$(get ecr_repository_url)" >> "$GITHUB_ENV"
```

`SSM_PREFIX` é derivado da branch, não de input — ver
[ADR-0008](0008-oidc-para-os-pipelines.md).

**Segredo não vai para o SSM.** Chave JWT e credencial do RDS ficam no Secrets
Manager; o SSM guarda apenas identificadores, que não são sigilosos.

Complemento necessário: o Terraform cria a *forma* dos recursos de aplicação
(Deployment, função Lambda) mas ignora o *conteúdo* — a tag da imagem e o
`filename` do zip vivem sob `lifecycle.ignore_changes`. Terraform é dono da
forma; o CD é dono do artefato.

## Alternativas consideradas

**GitHub Variables por repositório.** Seriam ~10 variáveis × 2 ambientes × 4
repositórios, atualizadas à mão a cada bring-up. Inviável.

**`terraform_remote_state` nos outros repositórios.** Daria acesso de leitura ao
state completo — que contém a senha do RDS e a chave JWT — a três pipelines que
não precisam dela. Descartada por segurança.

**Outputs commitados em arquivo.** Exigiria commit automático do repositório de
infra para os outros três, ou submódulo. Acoplamento pior.

**Convenção de nomes determinística.** Já existe em parte (tudo é prefixado por
`oficina-mecanica-<env>-`), mas nem tudo é previsível: a URL do ECR contém o id
da conta e a região, e o domínio do CloudFront é gerado.

## Consequências

**Positivas**
- Um bring-up muda os identificadores e nenhum repositório precisa ser editado.
- Adicionar um consumidor é adicionar um `get` — sem coordenação de secrets.
- Os parâmetros são inspecionáveis: `aws ssm get-parameters-by-path` mostra o
  estado real do contrato.
- Custo zero: Standard tier, dentro do free tier.

**Negativas**
- **Acoplamento por nome de parâmetro, não validado em tempo de plan.** Renomear
  um parâmetro quebra o pipeline consumidor só na execução seguinte. Mitigação:
  a lista vive num único `locals` por camada, e os workflows falham alto quando
  o `get` volta vazio.
- Todo job de deploy precisa de credencial AWS antes de qualquer outra coisa —
  mesmo o do frontend, que só faz `s3 sync`.
- Mais uma dependência de runtime no pipeline: SSM indisponível é deploy parado.
