# Documentação da arquitetura

Este diretório é a documentação arquitetural do sistema de gestão de oficina
mecânica — os quatro repositórios vistos como um só. Os READMEs dos repositórios
são **operacionais** (como rodar, como fazer deploy, quais variáveis existem);
aqui ficam as **decisões** e os **diagramas**.

## Índice

### Diagramas

| Documento | Conteúdo |
|---|---|
| [Componentes](diagramas/componentes.md) | Visão de nuvem: borda, VPC, APIs, banco, e-mail, observabilidade |
| [Sequência — autenticação](diagramas/sequencia-autenticacao.md) | Login, emissão do JWT e consumo de rota protegida |
| [Sequência — ordem de serviço](diagramas/sequencia-ordem-de-servico.md) | Abertura da OS, orçamento, aprovação pelo cliente e execução |
| [Implantação](diagramas/implantacao.md) | Onde cada artefato roda e quem faz o deploy dele |

### Banco de dados

| Documento | Conteúdo |
|---|---|
| [Modelo de dados](banco-de-dados.md) | Justificativa da escolha, diagrama ER, relacionamentos e ajustes no modelo |

### RFCs — propostas técnicas

Discussões abertas antes de uma decisão. Descrevem o problema, as alternativas
consideradas e a recomendação.

| RFC | Título | Estado |
|---|---|---|
| [RFC-0001](rfc/0001-escolha-da-nuvem.md) | Escolha da nuvem | Aceita |
| [RFC-0002](rfc/0002-escolha-do-banco-de-dados.md) | Escolha do banco de dados | Aceita |
| [RFC-0003](rfc/0003-estrategia-de-autenticacao.md) | Estratégia de autenticação e autorização | Aceita |
| [RFC-0004](rfc/0004-estrategia-de-observabilidade.md) | Estratégia de observabilidade | Aceita |
| [RFC-0005](rfc/0005-segregacao-em-repositorios.md) | Segregação em repositórios e estratégia de branches | Aceita |

### ADRs — decisões arquiteturais

Decisões tomadas e em vigor. Uma ADR não se edita: quando a decisão muda, ela é
marcada como *substituída* e uma nova ADR toma o lugar.

| ADR | Título | Estado |
|---|---|---|
| [ADR-0001](adr/0001-registrar-decisoes-de-arquitetura.md) | Registrar decisões de arquitetura | Aceita |
| [ADR-0002](adr/0002-comunicacao-sincrona-http.md) | Comunicação síncrona HTTP, sem broker | Aceita |
| [ADR-0003](adr/0003-api-gateway-como-unica-porta-publica.md) | API Gateway como única porta pública | Aceita |
| [ADR-0004](adr/0004-hpa-no-deployment-da-api.md) | HPA no Deployment da API | Aceita |
| [ADR-0005](adr/0005-migrations-como-job-do-pipeline.md) | Migrations como Job do pipeline | Aceita |
| [ADR-0006](adr/0006-duas-camadas-de-terraform.md) | Duas camadas de Terraform | Aceita |
| [ADR-0007](adr/0007-contrato-entre-repositorios-via-ssm.md) | Contrato entre repositórios via SSM | Aceita |
| [ADR-0008](adr/0008-oidc-para-os-pipelines.md) | OIDC para os pipelines, sem chaves estáticas | Aceita |
| [ADR-0009](adr/0009-jwt-hs256-com-segredo-compartilhado.md) | JWT HS256 com segredo compartilhado | Aceita |
| [ADR-0010](adr/0010-snapshot-de-precos-na-ordem-de-servico.md) | Snapshot de preços na ordem de serviço | Aceita |
| [ADR-0011](adr/0011-logs-estruturados-com-correlacao.md) | Logs estruturados com correlação de requisições | Proposta |

## Convenções

- **RFC** discute; **ADR** decide. Uma RFC pode gerar várias ADRs.
- Numeração sequencial, nunca reaproveitada.
- Estados de ADR: `Proposta` → `Aceita` → `Substituída por ADR-XXXX` / `Revogada`.
- Diagramas em [Mermaid](https://mermaid.js.org/), renderizados pelo próprio
  GitHub. Nada de imagem binária: diagrama que não dá para revisar em diff
  envelhece sem ninguém perceber.
