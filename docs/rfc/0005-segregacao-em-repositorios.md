# RFC-0005 — Segregação em repositórios e estratégia de branches

- **Estado:** Aceita
- **Data:** 2026-09-02
- **Decisões derivadas:** [ADR-0007](../adr/0007-contrato-entre-repositorios-via-ssm.md), [ADR-0008](../adr/0008-oidc-para-os-pipelines.md)

## Problema

A fase exige que o projeto seja organizado em **quatro repositórios separados**,
cada um com CI/CD próprio e deploy automático:

1. Lambda (function serverless)
2. Infraestrutura Kubernetes (Terraform)
3. Infraestrutura do banco de dados gerenciado (Terraform)
4. Aplicação principal executando em Kubernetes

O ponto de partida era um repositório único da fase anterior, contendo API,
manifestos e infraestrutura.

Segregar tem um custo que precisa ser explícito: quatro repositórios significam
quatro pipelines, quatro conjuntos de credenciais e a necessidade de um contrato
entre eles. Feito mal, produz quatro repositórios que só funcionam juntos e
precisam ser alterados juntos — o pior dos dois mundos.

## Critério de corte

A pergunta que separa os repositórios não é "que assunto é este?", e sim
**"qual artefato este repositório produz e quem faz o deploy dele?"**.

| Repositório | Artefato | Quem consome |
|---|---|---|
| `oficina-mecanica-infrastructure` | recursos AWS e objetos Kubernetes | os outros três |
| `oficina-mecanica-monolith` | imagem no ECR + schema do banco | EKS |
| `oficina-mecanica-serverless` | zip publicado na função Lambda | API Gateway |
| `oficina-mecanica-frontend` | objetos no S3 | CloudFront |

Cada linha tem ciclo de release próprio. Corrigir um `.html` do painel não
recompila Go nem toca no Terraform.

## Desvio em relação ao enunciado

O enunciado pede a infraestrutura Kubernetes e a do banco em **repositórios
distintos**. Aqui as duas vivem no mesmo repositório, em `ephemeral/` — e o corte
que existe é outro: **por ciclo de vida** (`persistent/` × `ephemeral/`), não por
tipo de recurso ([ADR-0006](../adr/0006-duas-camadas-de-terraform.md)).

A razão é que EKS e RDS **compartilham a mesma VPC, as mesmas subnets privadas e
os mesmos security groups**. Separá-los em repositórios criaria uma dependência
circular de state: o repositório do banco precisaria da VPC criada pelo do
cluster, e o security group do RDS precisaria referenciar o dos nós. Resolver
isso exigiria um terceiro repositório só para a rede, ou `terraform_remote_state`
cruzado — expondo, a mais um pipeline, um state que guarda a senha do RDS.

O quarto repositório entregue é o `oficina-mecanica-frontend`, que não está na
lista do enunciado. A contagem de quatro se mantém; a composição não.

**Se o critério de avaliação for literal**, a separação é viável com o padrão que
já existe neste projeto: extrair `rds.tf`, o `db_subnet_group` e o security group
do banco para um repositório próprio, com state próprio, consumindo `vpc_id` e
`private_subnet_ids` do SSM — parâmetros que a camada efêmera **já publica**
([ADR-0007](../adr/0007-contrato-entre-repositorios-via-ssm.md)) — e publicando
`database_endpoint` de volta. O custo é uma ordem de bring-up a mais para
orquestrar (rede → banco → cluster) e um `terraform apply` adicional no ciclo.

O desvio está registrado aqui para ser uma decisão consciente, não uma omissão.

## Estratégia de branches

Duas branches de longa duração por repositório, e a branch é o que decide o
ambiente:

| Branch | Ambiente | GitHub Environment | Prefixo no SSM |
|---|---|---|---|
| `hml` | homologação | `homolog` | `/oficina-mecanica/homolog` |
| `main` | produção | `production` | `/oficina-mecanica/prod` |

Fluxo: `feat/*` → PR para `hml` → validação em homologação → PR de `hml` para
`main` → produção.

**Nenhum workflow de aplicação aceita input de ambiente.** O `ref` já carrega a
informação, e um input separado poderia contradizê-lo — fazendo deploy do código
de uma branch no ambiente da outra. A mesma regra é imposta três vezes: na
expressão `environment:` do job, num `case` explícito que falha alto se alguém
acrescentar uma branch e esquecer do mapa, e na trust policy do OIDC do lado da
AWS ([ADR-0008](../adr/0008-oidc-para-os-pipelines.md)).

### Proteção

- `main` protegida por ruleset: sem push direto, merge apenas por Pull Request.
- `production` como GitHub Environment com revisor obrigatório — o `apply` de
  produção espera aprovação humana.
- O histórico dos quatro repositórios mostra o fluxo em uso: as promoções para
  `hml` e para `main` foram feitas por PR.

## Conteúdo comum

Todo repositório tem: `README.md` com propósito, tecnologias, passos de execução
e diagrama próprio; pipeline com lint, teste e deploy; e análise de qualidade em
SonarQube efêmero nos PRs. Onde há API, há contrato OpenAPI validado no CI —
`redocly lint` — e um teste que garante que o contrato e as rotas registradas não
divergem.

Os contratos são **disjuntos por desenho**: `/auth/*` pertence ao
`oficina-mecanica-serverless`; todo o resto, ao `oficina-mecanica-monolith`.
Nenhum dos dois documenta rota do outro.

## Consequências

**Positivas**
- Release independente por artefato; blast radius por repositório
  ([ADR-0008](../adr/0008-oidc-para-os-pipelines.md)).
- Pipelines curtos: o do frontend não compila Go.
- Contrato explícito e inspecionável via SSM.

**Negativas**
- Uma mudança que atravessa camadas exige PRs coordenados em mais de um
  repositório.
- Quatro pipelines a manter, com trechos parecidos e sem workflow reutilizável
  hoje.
- Os 2.000 minutos/mês de Actions são compartilhados; daí `concurrency` com
  `cancel-in-progress` em PR e SonarQube apenas em PR.
- O desvio documentado acima: infraestrutura de banco e de cluster no mesmo
  repositório.
