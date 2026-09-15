# Glossário e diagnóstico rápido

## Glossário

Termos que aparecem no documento e no código, com o significado que têm neste
projeto.

| Termo | Significado aqui |
|---|---|
| **OS** | ordem de serviço, o agregado central do domínio. Tabela `work_orders` |
| **Item da OS** | uma linha de `work_order_services`: um serviço do catálogo aplicado a uma OS, com preço congelado |
| **Snapshot** | cópia de título, preço e tempo do catálogo para dentro do item da OS, no momento da inclusão ([ADR-0010](./adr/0010-snapshot-de-precos-na-ordem-de-servico.md)) |
| **Catálogo** | as tabelas `services` e `supplies`, compartilhadas entre todas as OSs |
| **Operador** | usuário interno: atendente, mecânico ou administrador |
| **Camada persistente** | o Terraform em `persistent/`, que vive entre ciclos e custa ~US$ 1/mês ([ADR-0006](./adr/0006-duas-camadas-de-terraform.md)) |
| **Camada efêmera** | o Terraform em `ephemeral/`, criado pelo `bring-up` e destruído pelo `tear-down` |
| **Bring-up** | execução de `bring-up.yml`: cria a camada efêmera e dispara os pipelines de aplicação |
| **Tear-down** | execução de `tear-down.yml`: destrói a camada efêmera e verifica que nada sobrou |
| **Contrato entre repositórios** | os parâmetros no SSM que os pipelines leem para descobrir nomes de recurso ([ADR-0007](./adr/0007-contrato-entre-repositorios-via-ssm.md)) |
| **Forma e conteúdo** | o Terraform cria a forma do recurso de aplicação; o pipeline de código publica o conteúdo, que é a imagem ou o zip |
| **VPC Link** | recurso do API Gateway que cria ENIs em subnets privadas, permitindo alcançar o ALB interno |
| **TargetGroupBinding** | CRD do `aws-load-balancer-controller` que liga um Service a um target group criado fora do cluster |
| **IRSA** | IAM Roles for Service Accounts: dá permissão AWS a um pod sem chave estática |
| **`request_id`** | identificador de correlação que nasce no API Gateway e atravessa a aplicação ([ADR-0011](./adr/0011-logs-estruturados-com-correlacao.md)) |
| **Evento de domínio** | valor do campo `event` em uma linha de log, consultado por métricas e alertas |
| **Métrica de log** | contador que o backend de observabilidade calcula na ingestão e guarda como métrica |

## Onde procurar quando algo falha

| Sintoma | Primeiro lugar a olhar |
|---|---|
| Domínio público responde 404 em tudo | a camada efêmera está desligada ([ADR-0006](./adr/0006-duas-camadas-de-terraform.md)) |
| 502 ou 503 no domínio público | o ALB não tem target saudável: pods não-Ready, ou Deployment ainda com a imagem `pause` |
| 401 em rota que deveria funcionar | expiração do token, ou divergência de segredo entre Lambda e pod |
| 403 com `insufficient permissions` | o papel do token não cobre a rota |
| Deploy do monolito parou antes do rollout | o `Job` de migration falhou; as últimas 200 linhas de log estão na saída do pipeline |
| `AssumeRoleWithWebIdentity` negado | branch, repositório ou GitHub Environment não batem com a trust policy ([ADR-0008](./adr/0008-oidc-para-os-pipelines.md)) |
| Pipeline reclama de variável vazia | um `get` do SSM voltou vazio: parâmetro renomeado ou camada não aplicada ([ADR-0007](./adr/0007-contrato-entre-repositorios-via-ssm.md)) |
| Painel do Datadog em zero | esperado até a fase 1 da [RFC-0004](./rfc/0004-estrategia-de-observabilidade.md) chegar ao ambiente |

## Comandos de inspeção

```bash
# contrato publicado para o ambiente
aws ssm get-parameters-by-path --path /oficina-mecanica/homolog --recursive

# o RDS não é alcançável de fora da VPC: entre por um pod
kubectl -n "$KUBE_NAMESPACE" exec -it deploy/api -- sh

# réplicas mantidas pelo HPA, e consumo real por pod
kubectl -n "$KUBE_NAMESPACE" get hpa,deploy,pods
kubectl -n "$KUBE_NAMESPACE" top pods
```

Para investigar uma requisição específica, o `request_id` cobre o rastro
inteiro em uma consulta (`@request_id:"<id>"`). O mesmo valor aparece no access
log do API Gateway, no header de resposta da API e em toda linha de log daquela
requisição ([ADR-0011](./adr/0011-logs-estruturados-com-correlacao.md)).

## Primeiros passos no projeto

1. Clone os quatro repositórios e leia o `README.md` de cada um.
2. Suba o monolito localmente com `docker compose up -d` e aplique as
   migrations com `go run ./cmd/api migrate`.
3. Leia os diagramas e o modelo de dados com o banco local à frente,
   comparando o diagrama ER com as tabelas reais.
4. Só então peça acesso à AWS: quase nada do que é preciso entender no início
   exige ambiente em nuvem.
