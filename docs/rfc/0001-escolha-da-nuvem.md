# RFC-0001 — Escolha da nuvem

- **Estado:** Aceita
- **Data:** 2026-09-02
- **Decisões derivadas:** [ADR-0003](../adr/0003-api-gateway-como-unica-porta-publica.md), [ADR-0006](../adr/0006-duas-camadas-de-terraform.md), [ADR-0008](../adr/0008-oidc-para-os-pipelines.md)

## Problema

A fase deixa a nuvem em aberto, mas fixa os componentes: API Gateway, function
serverless, banco gerenciado, cluster Kubernetes com escalabilidade e Terraform.

As três grandes atendem a essa lista. A decisão precisa ser tomada por critérios
que realmente diferenciam neste contexto — e o contexto tem duas restrições
fortes que um projeto corporativo não tem:

- **Orçamento próximo de zero.** Sem contrato, sem crédito corporativo. O
  ambiente sobe sob demanda e desce quando não está em uso.
- **Prazo curto, equipe de quatro.** Tempo gasto lutando com a nuvem é tempo não
  gasto no sistema.

## Critérios

| Peso | Critério |
|---|---|
| Alto | Custo com o ambiente **desligado** — é o estado padrão |
| Alto | Maturidade do provider Terraform e volume de exemplos públicos |
| Alto | Federação OIDC com GitHub Actions sem chave estática |
| Médio | Tempo de criação e destruição do cluster gerenciado |
| Médio | Function serverless com runtime Go de primeira classe |
| Médio | Integração nativa entre gateway, function e o balanceador do cluster |
| Baixo | Preço por hora com o ambiente ligado (as três são equivalentes) |

## Alternativas

### AWS — EKS, Lambda, API Gateway HTTP API, RDS

**A favor.** Provider `hashicorp/aws` é o mais maduro do ecossistema, e a
proporção de exemplos e respostas públicas em relação às outras nuvens é
grande — o que importa com prazo curto. OIDC com GitHub Actions é documentado e
suportado nativamente (`aws-actions/configure-aws-credentials`). Lambda tem
runtime `provided.al2023` para binário Go compilado, com cold start baixo.
API Gateway HTTP API custa ~1/3,5 do REST e tem 1M de requisições/mês no free
tier. **Com o ambiente desligado, a camada persistente custa ~US$ 1/mês** —
CloudFront, S3, ECR e API Gateway parados são praticamente gratuitos. Integração
`VPC Link` → ALB interno permite manter todo o cluster privado
([ADR-0003](../adr/0003-api-gateway-como-unica-porta-publica.md)).

**Contra.** EKS cobra **US$ 0,10/hora pelo control plane**, ligado ou não —
diferente do GKE Autopilot e do AKS, cujo control plane é gratuito. NAT Gateway
é caro (~US$ 0,045/h + tráfego). A experiência inicial de IAM é a mais verbosa
das três. Criar e destruir uma distribuição CloudFront leva 15-25 minutos.

### GCP — GKE, Cloud Functions/Run, API Gateway, Cloud SQL

**A favor.** Control plane do GKE gratuito no primeiro cluster por conta;
Autopilot cobra por pod, não por nó. Cloud Run é mais agradável que Lambda para
serviço HTTP. Créditos iniciais generosos. Rede mais simples que a da AWS.

**Contra.** O API Gateway do GCP é o produto mais fraco dos três: menos
recursos, documentação escassa e ecossistema Terraform correspondente menor.
Cloud SQL parado ainda cobra armazenamento e, dependendo da configuração, a
instância. A equipe tinha menos familiaridade, e o provider `google` tem menos
exemplos para o recorte exato desta fase.

### Azure — AKS, Functions, API Management, Azure Database for PostgreSQL

**A favor.** Control plane do AKS gratuito no tier Free. Integração forte com
GitHub Actions (mesma empresa) e OIDC bem suportado.

**Contra.** **API Management é caro e lento**: o tier Developer custa ~US$
50/mês e leva 30-45 minutos para provisionar — inviável para um ciclo de
bring-up/tear-down. O tier Consumption é mais barato, mas com limitações
relevantes. Menor familiaridade da equipe.

## Comparação no critério que mais pesou

Custo mensal com o ambiente **desligado**, mantendo apenas o que precisa
sobreviver entre ciclos:

| | AWS | GCP | Azure |
|---|---|---|---|
| Registro de imagem | ECR, centavos | Artifact Registry, centavos | ACR Basic ~US$ 5 |
| Gateway parado | US$ 0 | US$ 0 | APIM Developer ~US$ 50 |
| CDN + storage estático | ~US$ 0 | ~US$ 0 | ~US$ 0 |
| Segredos | ~US$ 0,40 | ~US$ 0,06 | ~US$ 0 |
| **Total aproximado** | **~US$ 1** | **~US$ 1** | **~US$ 55** |

AWS e GCP empatam no critério de maior peso. O desempate veio do API Gateway
(produto maduro na AWS, fraco no GCP), da maturidade do provider Terraform e da
familiaridade da equipe — que, com prazo curto, é um fator técnico legítimo.

## Recomendação

**AWS**, com:

- **EKS** para o cluster, com HPA ([ADR-0004](../adr/0004-hpa-no-deployment-da-api.md));
- **Lambda** (`provided.al2023`, Go) para a function de autenticação;
- **API Gateway HTTP API** como única porta pública ([ADR-0003](../adr/0003-api-gateway-como-unica-porta-publica.md));
- **RDS PostgreSQL** ([RFC-0002](0002-escolha-do-banco-de-dados.md));
- **Terraform** em duas camadas ([ADR-0006](../adr/0006-duas-camadas-de-terraform.md));
- Região **sa-east-1**, por latência para usuários no Brasil.

O custo do control plane do EKS (~US$ 72/mês se ligado o tempo todo) é o preço
explícito desta escolha, e foi o que motivou a separação em camadas: **o EKS só
existe enquanto o ambiente está no ar.**

## Riscos aceitos

| Risco | Mitigação |
|---|---|
| EKS cobra por hora ligado | camada efêmera; `tear-down` verifica que nada sobrou |
| NAT Gateway é caro | um por ambiente, ligado só com a camada efêmera |
| Um ambiente esquecido ligado gasta ~US$ 0,30/h | `tear-down.yml` com confirmação explícita; custo documentado no README |
| Dependência de fornecedor único | Terraform e Go reduzem, mas não eliminam. Aceito |
