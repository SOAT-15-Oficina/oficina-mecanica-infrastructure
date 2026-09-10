# ADR-0006 — Duas camadas de Terraform: persistente e efêmera

- **Estado:** Aceita
- **Data:** 2026-09-02

## Contexto

O ambiente é sob demanda: sobe, é usado, desce. Um EKS mais um NAT
Gateway mais um RDS ligados 24×7 custam ordem de US$ 200/mês — inviável para um
projeto acadêmico.

Um `destroy` total, porém, esbarra em recursos que não toleram o ciclo:

- **Identidade SES.** Destruir remove-a da conta; recriar exige que um humano
  clique num link de verificação recebido por e-mail. Passo manual antes de cada
  bring-up.
- **CloudFront.** ~15-20 min para criar, ~15-25 para destruir (precisa ser
  desabilitada antes). Parada custa ~US$ 0. E o domínio dela é a base dos links
  de aprovação enviados aos clientes por e-mail — se mudar, links antigos
  quebram.
- **API Gateway.** Custa US$ 0 parado e é a *origin* do CloudFront. Recriado, o
  domínio `{id}.execute-api...` muda e a origin aponta para o vazio.
- **ECR.** Destruir apaga as imagens; o próximo bring-up subiria sem artefato.
- **Secrets Manager.** Segredos têm janela de exclusão de 7 a 30 dias; recriar
  com o mesmo nome dentro da janela falha.

## Decisão

**Dois diretórios Terraform com states independentes**, mais um bootstrap
aplicado uma vez por conta.

| Camada | Diretório | Custo | Conteúdo |
|---|---|---|---|
| **Bootstrap** | `bootstrap/` | centavos | bucket de state, tabela de lock. Aplicado à mão, uma vez por conta |
| **Persistente** | `persistent/` | ~US$ 1/mês | OIDC + roles, ECR, identidades SES, S3, CloudFront, **API Gateway + stage**, Secrets Manager, parâmetros SSM estáveis |
| **Efêmera** | `ephemeral/` | ~US$ 0,30/hora | VPC, NAT, EKS, ALB interno, RDS, Lambda, VPC Link, **rotas e integrações do gateway**, todos os objetos Kubernetes |

O corte do API Gateway é o mais fino e o mais importante: **o API e o stage são
persistentes; as rotas, integrações e o VPC Link são efêmeros**. Com o ambiente
desligado, o domínio existe e responde 404 — que é o comportamento correto.

Gatilhos:

| Camada | Como é aplicada |
|---|---|
| Persistente | automática, em push para `hml` ou `main` |
| Efêmera | manual, pelos workflows `bring-up.yml` e `tear-down.yml` |

O `tear-down` remove os `TargetGroupBinding` **antes** do destroy — senão o
`aws-load-balancer-controller` recria targets num ALB que o Terraform está
removendo — e ao final verifica que nada da camada efêmera sobrou.

## Alternativas consideradas

**State único com `-target`.** `terraform destroy -target=...` é explicitamente
desaconselhado pela HashiCorp para uso rotineiro e deixa o state inconsistente
quando há dependência cruzada.

**Workspaces.** Separam ambientes, não ciclos de vida. Ortogonal ao problema.

**Deixar tudo de pé.** Resolveria por US$ 200/mês.

**Módulo único com `count = var.enabled`.** Manteria um state só, mas encheria
cada recurso de condicional e o `plan` de ruído.

## Consequências

**Positivas**
- Custo parado de ~US$ 1/mês por ambiente.
- Domínio público estável entre ciclos: links de aprovação já enviados
  continuam válidos.
- Nenhuma reverificação de e-mail no SES.
- O `plan` da camada efêmera é pequeno e legível.

**Negativas**
- **Duas camadas para aplicar na ordem certa.** Ambiente novo exige um `apply`
  humano da persistente antes de qualquer pipeline funcionar — as roles OIDC que
  o CI assume nascem ali (ovo e galinha, documentado no README).
- Dependências cruzadas passam pelo SSM em vez de referência direta de recurso
  ([ADR-0007](0007-contrato-entre-repositorios-via-ssm.md)) — o Terraform não
  valida essa aresta.
- O `lifecycle.ignore_changes` no stage do gateway é necessário para que o apply
  da persistente não reverta o que a efêmera criou. É sutil e fácil de quebrar.
- ~25-30 min do zero até um ambiente demonstrável.
