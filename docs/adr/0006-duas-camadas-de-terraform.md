# ADR-0006. Duas camadas de Terraform: persistente e efêmera

**Aceita** · 2026-09-02

**Contexto.** O ambiente é sob demanda: sobe, é usado e desce. Um EKS, mais um
NAT Gateway, mais um RDS ligados 24 horas por dia custam na ordem de US$ 200
por mês. Um `destroy` total, porém, esbarra em recursos que não toleram o ciclo:

| Recurso | Por que não tolera |
|---|---|
| Identidade SES | destruir remove da conta, e recriar exige um humano clicando em link de verificação por e-mail |
| CloudFront | 15 a 20 min para criar, 15 a 25 para destruir; parada custa ~US$ 0; e o domínio é a base dos links de aprovação já enviados |
| API Gateway | US$ 0 parado, e é a *origin* do CloudFront: recriado, o domínio muda e a origin aponta para o vazio |
| ECR | destruir apaga as imagens, e o próximo bring-up subiria sem artefato |
| Secrets Manager | janela de exclusão de 7 a 30 dias, e recriar com o mesmo nome dentro da janela falha |

**Decisão.** Dois diretórios Terraform com states independentes, mais um
bootstrap aplicado uma vez por conta.

| Camada | Diretório | Custo | Conteúdo | Aplicação |
|---|---|---|---|---|
| Bootstrap | `bootstrap/` | centavos | bucket de state, tabela de lock | à mão, uma vez por conta |
| Persistente | `persistent/` | ~US$ 1/mês | OIDC e roles, ECR, identidades SES, S3, CloudFront, **API Gateway e stage**, Secrets Manager, parâmetros SSM estáveis | automática, em push para `hml` ou `main` |
| Efêmera | `ephemeral/` | ~US$ 0,30/h | VPC, NAT, EKS, ALB interno, RDS, Lambda, VPC Link, **rotas e integrações do gateway**, objetos Kubernetes | manual, por `bring-up.yml` e `tear-down.yml` |

O corte do API Gateway é o mais fino e o mais importante: **o API e o stage são
persistentes; as rotas, as integrações e o VPC Link são efêmeros**. Desligado,
o domínio existe e responde 404.

O `tear-down` remove os `TargetGroupBinding` **antes** do destroy, porque sem
isso o `aws-load-balancer-controller` recria targets em um ALB que o Terraform
está removendo. Ao final, verifica que nada da camada efêmera sobrou.

## Alternativas descartadas

| Opção | Motivo do descarte |
|---|---|
| State único com `-target` | desaconselhado pela HashiCorp para uso rotineiro, e deixa o state inconsistente quando há dependência cruzada |
| Workspaces | separam ambientes, não ciclos de vida: ortogonais ao problema |
| Deixar tudo de pé | resolveria por US$ 200/mês |
| Módulo único com `count = var.enabled` | manteria um state só, mas encheria cada recurso de condicional e o `plan` de ruído |

## Consequências

| Ganhos | Custos |
|---|---|
| Custo parado de ~US$ 1/mês por ambiente | **duas camadas para aplicar na ordem certa**: ambiente novo exige um `apply` humano da persistente antes de qualquer pipeline, porque as roles OIDC nascem ali |
| Domínio público estável entre ciclos: links de aprovação já enviados continuam válidos | dependências cruzadas passam pelo SSM em vez de referência direta ([ADR-0007](./0007-contrato-entre-repositorios-via-ssm.md)), e o Terraform não valida essa aresta |
| Nenhuma reverificação de e-mail no SES | o `lifecycle.ignore_changes` no stage do gateway é necessário para a persistente não reverter o que a efêmera criou: é sutil e fácil de quebrar |
| O `plan` da camada efêmera é pequeno e legível | 25 a 30 minutos do zero até um ambiente demonstrável |
