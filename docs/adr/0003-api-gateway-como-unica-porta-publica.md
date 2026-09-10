# ADR-0003 — API Gateway como única porta pública

- **Estado:** Aceita
- **Data:** 2026-09-02
- **Relacionada:** [ADR-0002](0002-comunicacao-sincrona-http.md), [RFC-0003](../rfc/0003-estrategia-de-autenticacao.md)

## Contexto

A fase exige um API Gateway para controle e roteamento. A forma mais barata de
atendê-lo seria colocar o gateway na frente de um EKS que continuasse com Load
Balancer público — o requisito estaria formalmente cumprido e o cluster seguiria
alcançável por quem descobrisse o DNS do ALB.

Isso esvaziaria o gateway: throttling, log de acesso e roteamento só valem se
não houver caminho alternativo.

## Decisão

**Exatamente um endereço é alcançável da internet: o domínio do CloudFront.**
Todo o resto vive em subnet privada.

| Recurso | Exposição |
|---|---|
| CloudFront | público — única entrada |
| S3 do painel | privado, só aceita o CloudFront via Origin Access Control |
| API Gateway HTTP API | público em DNS, mas só expõe `/auth/*` e o `$default` |
| ALB | **interno** — DNS que só resolve dentro da VPC |
| EKS, RDS, Lambda | subnets privadas, sem IP público |

A ponte do gateway para dentro é um **VPC Link**, que cria ENIs nas subnets
privadas. É unidirecional: o gateway alcança o ALB, nada de fora alcança o
gateway por esse caminho.

Uma **CloudFront Function** remove o prefixo `/api` antes de repassar à origem.
Painel e API compartilham origem — logo, sem CORS e sem URL de API embutida no
build do frontend.

Roteamento no gateway:

| Rota | Destino |
|---|---|
| `POST /auth/login`, `POST /auth/register` | integração `AWS_PROXY` → Lambda |
| `$default` | integração `HTTP_PROXY` via VPC Link → ALB interno → pods |

A rota específica vence a coringa, então `/auth/*` nunca chega ao monolito.

O stage aplica throttling de 100 rps com burst de 200 e grava access log em JSON
no CloudWatch com `requestId`, método, path, `routeKey`, status e mensagem de
erro de integração.

## Alternativas consideradas

**Ingress do Kubernetes com ALB público.** Mais idiomático em EKS, e o
`aws-load-balancer-controller` já está instalado. Descartada porque o ALB
passaria a ser um segundo caminho público, contornando o gateway. Aqui o ALB é
criado pelo Terraform e ligado ao Service por `TargetGroupBinding` — o
controller registra targets, mas não é dono do balanceador.

**API Gateway REST em vez de HTTP API.** Traz usage plans, API keys e
transformação de payload. Custa ~3,5× mais por requisição e nada disso é usado.

**NLB + autorizador Lambda no gateway.** Um autorizador no gateway centralizaria
a validação do JWT. Descartada por ora: exigiria que o autorizador conhecesse o
segredo e adicionaria uma invocação por requisição. A validação no middleware do
monolito custa zero e usa a mesma biblioteca que emitiu o token. Fica como
evolução natural se surgir um segundo consumidor da API.

## Consequências

**Positivas**
- Superfície de ataque de um endereço só. Vazar o DNS do ALB não dá acesso.
- Throttling e log de acesso valem para 100% do tráfego.
- Trocar o backend de `/auth/*` é mudar uma integração, sem tocar em cliente.

**Negativas**
- **Depurar exige túnel.** Não há `curl` direto no pod; o pipeline usa
  `kubectl port-forward` para o smoke check.
- O VPC Link adiciona ENIs e um salto de rede — alguns milissegundos por
  requisição.
- O gateway vira ponto único de falha. É gerenciado e multi-AZ por natureza, mas
  a dependência é real.
- Rotas do gateway são efêmeras e o API é persistente: com o ambiente desligado,
  o domínio responde 404. É o comportamento correto, mas surpreende quem não
  conhece a divisão em camadas ([ADR-0006](0006-duas-camadas-de-terraform.md)).
