# RFC-0001. Escolha da nuvem

**Aceita** · 2026-09-02 · Origina [ADR-0003](../adr/0003-api-gateway-como-unica-porta-publica.md),
[ADR-0006](../adr/0006-duas-camadas-de-terraform.md), [ADR-0008](../adr/0008-oidc-para-os-pipelines.md)

**Problema.** O desafio deixa a nuvem em aberto, mas fixa os componentes: API
Gateway, function serverless, banco gerenciado, cluster Kubernetes com
escalabilidade e Terraform. As três grandes atendem a essa lista, então a
decisão sai de critérios que diferenciam neste contexto. Duas restrições
pesam: orçamento próximo de zero, com o ambiente subindo sob demanda; e prazo
curto com equipe de quatro pessoas.

**Critérios, por peso.** Alto: custo com o ambiente desligado, que é o estado
padrão; maturidade do provider Terraform e volume de exemplos públicos;
federação OIDC com GitHub Actions sem chave estática. Médio: tempo de criação e
destruição do cluster; runtime Go de primeira classe na function; integração
nativa entre gateway, function e balanceador. Baixo: preço por hora ligado,
equivalente nas três.

## Alternativas

| Opção | A favor | Contra |
|---|---|---|
| **AWS** (EKS, Lambda, API Gateway HTTP API, RDS) | provider `hashicorp/aws` é o mais maduro e com mais exemplos; OIDC nativo via `aws-actions/configure-aws-credentials`; runtime `provided.al2023` para binário Go com cold start baixo; HTTP API custa ~1/3,5 do REST, com 1M req/mês no free tier; camada persistente parada custa ~US$ 1/mês; `VPC Link` para ALB interno mantém o cluster privado | control plane do EKS cobra US$ 0,10/h ligado ou não; NAT Gateway caro (~US$ 0,045/h + tráfego); IAM é o mais verboso dos três; CloudFront leva 15 a 25 min para criar ou destruir |
| **GCP** (GKE, Cloud Run, API Gateway, Cloud SQL) | control plane do GKE gratuito no primeiro cluster; Autopilot cobra por pod; Cloud Run mais direto que Lambda para HTTP; créditos iniciais; rede mais simples | API Gateway é o produto mais fraco dos três, com documentação escassa e ecossistema Terraform menor; Cloud SQL parado ainda cobra armazenamento e, dependendo da configuração, a instância |
| **Azure** (AKS, Functions, API Management, PostgreSQL) | control plane do AKS gratuito no tier Free; OIDC bem suportado | API Management é caro e lento: tier Developer ~US$ 50/mês e 30 a 45 min para provisionar, inviável no ciclo de bring-up e tear-down |

## Comparação no critério de maior peso

Custo mensal com o ambiente **desligado**, mantendo só o que sobrevive entre
ciclos:

| | AWS | GCP | Azure |
|---|---|---|---|
| Registro de imagem | ECR, centavos | Artifact Registry, centavos | ACR Basic ~US$ 5 |
| Gateway parado | US$ 0 | US$ 0 | APIM Developer ~US$ 50 |
| CDN e storage estático | ~US$ 0 | ~US$ 0 | ~US$ 0 |
| Segredos | ~US$ 0,40 | ~US$ 0,06 | ~US$ 0 |
| **Total** | **~US$ 1** | **~US$ 1** | **~US$ 55** |

AWS e GCP empatam. O desempate veio do API Gateway (maduro na AWS, fraco no
GCP), da maturidade do provider Terraform e da familiaridade prévia com a
plataforma, que encurta o tempo de implementação.

**Recomendação.** AWS, com EKS e HPA ([ADR-0004](../adr/0004-hpa-no-deployment-da-api.md)), Lambda
(`provided.al2023`, Go), API Gateway HTTP API como única porta pública
([ADR-0003](../adr/0003-api-gateway-como-unica-porta-publica.md)), RDS PostgreSQL ([RFC-0002](./0002-escolha-do-banco-de-dados.md)), Terraform em
duas camadas ([ADR-0006](../adr/0006-duas-camadas-de-terraform.md)) e região `sa-east-1` por latência para
usuários no Brasil.

O control plane do EKS, cerca de US$ 72/mês se ligado o tempo todo, é o preço
explícito desta escolha, e é o que motivou a separação em camadas: **o EKS só
existe enquanto o ambiente está no ar.**

## Riscos aceitos

| Risco | Mitigação |
|---|---|
| EKS cobra por hora ligado | camada efêmera; o `tear-down` verifica que nada sobrou |
| NAT Gateway é caro | um por ambiente, ligado só com a camada efêmera |
| Ambiente esquecido ligado gasta ~US$ 0,30/h | `tear-down.yml` com confirmação explícita; custo no README |
| Dependência de fornecedor único | Terraform e Go reduzem o custo de saída, não o eliminam |
