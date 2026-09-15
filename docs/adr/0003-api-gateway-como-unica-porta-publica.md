# ADR-0003. API Gateway como única porta pública

**Aceita** · 2026-09-02 · Relacionada [ADR-0002](./0002-comunicacao-sincrona-http.md),
[RFC-0003](../rfc/0003-estrategia-de-autenticacao.md)

**Contexto.** O desafio exige um API Gateway para controle e roteamento. A
forma mais barata de atendê-lo seria colocar o gateway na frente de um EKS que
continuasse com Load Balancer público: o requisito estaria formalmente
cumprido, e o cluster seguiria alcançável por quem descobrisse o DNS do ALB.
Isso esvaziaria a função do gateway, porque throttling, log de acesso e
roteamento só valem se não houver caminho alternativo.

**Decisão.** Exatamente um endereço é alcançável da internet: o domínio do
CloudFront. Todo o resto vive em subnet privada.

| Recurso | Exposição |
|---|---|
| CloudFront | público, única entrada |
| S3 do painel | privado, só aceita o CloudFront via Origin Access Control |
| API Gateway HTTP API | público em DNS, mas só expõe `/auth/*` e o `$default` |
| ALB | **interno**, DNS que só resolve dentro da VPC |
| EKS, RDS, Lambda | subnets privadas, sem IP público |

A ponte do gateway para dentro é um **VPC Link**, que cria ENIs nas subnets
privadas. É unidirecional: o gateway alcança o ALB, e nada de fora alcança o
gateway por esse caminho. Uma **CloudFront Function** remove o prefixo `/api`
antes de repassar à origem, o que faz painel e API compartilharem a origem e
elimina CORS e URL de API no build do frontend.

| Rota do gateway | Destino |
|---|---|
| `POST /auth/login`, `POST /auth/register` | integração `AWS_PROXY` para a Lambda |
| `$default` | integração `HTTP_PROXY` via VPC Link, ALB interno, pods |

A rota específica vence a coringa, então `/auth/*` nunca chega ao monolito. O
stage aplica throttling de 100 rps com burst de 200 e grava access log JSON no
CloudWatch, com `requestId`, método, path, `routeKey`, status e erro de
integração.

## Alternativas descartadas

| Opção | Motivo do descarte |
|---|---|
| Ingress do Kubernetes com ALB público | o ALB passaria a ser um segundo caminho público, contornando o gateway. Na solução adotada, o ALB é criado pelo Terraform e ligado ao Service por `TargetGroupBinding`: o controller registra targets, mas não é dono do balanceador |
| API Gateway REST | usage plans, API keys e transformação de payload custam ~3,5 vezes mais por requisição e nada disso é usado |
| NLB com autorizador Lambda no gateway | exigiria que o autorizador conhecesse o segredo e adicionaria uma invocação por requisição. Fica como evolução se surgir um segundo consumidor da API |

## Consequências

| Ganhos | Custos |
|---|---|
| Superfície de ataque de um endereço só; vazar o DNS do ALB não dá acesso | **depurar exige túnel**: não há `curl` direto no pod, e o pipeline usa `kubectl port-forward` para o smoke check |
| Throttling e log de acesso valem para 100% do tráfego | o VPC Link adiciona ENIs e um salto de rede, na ordem de alguns milissegundos |
| Trocar o backend de `/auth/*` é mudar uma integração, sem tocar em cliente | o gateway vira ponto único de falha: é gerenciado e multi-AZ, mas a dependência é real |
| | rotas são efêmeras e o API é persistente: desligado, o domínio responde 404, o que surpreende quem não conhece a divisão em camadas ([ADR-0006](./0006-duas-camadas-de-terraform.md)) |
