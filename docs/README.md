# Documentação da arquitetura

Documento de arquitetura do sistema de gestão de oficina mecânica mantido na
organização [SOAT-15-Oficina](https://github.com/SOAT-15-Oficina). Responde a
duas perguntas: **como** o sistema está montado e **por que** foi montado
assim.

O público é quem está tendo contato com o projeto agora. Os `README.md` dos
repositórios são operacionais (como rodar, como fazer deploy, quais variáveis
existem); aqui ficam o desenho, as decisões e o custo de cada uma.

Este diretório é a fonte da verdade. O PDF distribuído para leitura offline
é um instantâneo dele: em caso de divergência, vale o que está aqui.

## Índice

| Documento | Conteúdo |
|---|---|
| [Visão geral do sistema](visao-geral.md) | Domínio, atores, repositórios e tecnologias |
| [Diagrama de componentes](diagramas/componentes.md) | Visão de nuvem: borda, VPC, APIs, banco, e-mail, observabilidade |
| [Autenticação e autorização](diagramas/sequencia-autenticacao.md) | Login, emissão do JWT e consumo de rota protegida |
| [Ciclo de vida da ordem de serviço](diagramas/sequencia-ordem-de-servico.md) | Abertura da OS, orçamento, aprovação pelo cliente e execução |
| [Implantação e ciclo do ambiente](diagramas/implantacao.md) | Onde cada artefato roda, quem publica e as duas camadas de Terraform |
| [Modelo de dados](banco-de-dados.md) | Justificativa, diagrama ER, relacionamentos e ajustes no modelo |
| [Glossário e diagnóstico rápido](glossario.md) | Termos do projeto, onde olhar quando algo falha, comandos de inspeção |

## Roteiro de leitura

| Se você vai | Leia, nesta ordem |
|---|---|
| Entender o sistema em 15 minutos | Visão geral, Diagrama de componentes |
| Mexer na API de negócio (Go / Fiber) | Componentes, Ciclo da OS, Modelo de dados, [ADR-0005](adr/0005-migrations-como-job-do-pipeline.md), [ADR-0010](adr/0010-snapshot-de-precos-na-ordem-de-servico.md) |
| Mexer na autenticação | Autenticação, [RFC-0003](rfc/0003-estrategia-de-autenticacao.md), [ADR-0009](adr/0009-jwt-hs256-com-segredo-compartilhado.md) |
| Mexer em Terraform ou pipeline | Implantação, [RFC-0005](rfc/0005-segregacao-em-repositorios.md), [ADR-0006](adr/0006-duas-camadas-de-terraform.md), [ADR-0007](adr/0007-contrato-entre-repositorios-via-ssm.md), [ADR-0008](adr/0008-oidc-para-os-pipelines.md) |
| Mexer em observabilidade | [RFC-0004](rfc/0004-estrategia-de-observabilidade.md), [ADR-0011](adr/0011-logs-estruturados-com-correlacao.md) |
| Revisar o banco ou escrever migration | Modelo de dados, [RFC-0002](rfc/0002-escolha-do-banco-de-dados.md), [ADR-0005](adr/0005-migrations-como-job-do-pipeline.md), [ADR-0010](adr/0010-snapshot-de-precos-na-ordem-de-servico.md) |
| Avaliar um risco de segurança | Superfície pública, [RFC-0003](rfc/0003-estrategia-de-autenticacao.md), [ADR-0003](adr/0003-api-gateway-como-unica-porta-publica.md), [ADR-0008](adr/0008-oidc-para-os-pipelines.md), [ADR-0009](adr/0009-jwt-hs256-com-segredo-compartilhado.md) |

## Mapa de perguntas

| Pergunta | Resposta em |
|---|---|
| Por que quatro repositórios e não um? | [RFC-0005](rfc/0005-segregacao-em-repositorios.md) |
| Por que AWS, e não GCP ou Azure? | [RFC-0001](rfc/0001-escolha-da-nuvem.md) |
| Por que PostgreSQL e não DynamoDB? | [RFC-0002](rfc/0002-escolha-do-banco-de-dados.md) |
| Por que não existe fila nem broker? | [ADR-0002](adr/0002-comunicacao-sincrona-http.md) |
| Como uma requisição chega ao pod da API? | Componentes, [ADR-0003](adr/0003-api-gateway-como-unica-porta-publica.md) |
| Por que o ambiente responde 404 desligado? | [ADR-0006](adr/0006-duas-camadas-de-terraform.md) |
| Como um pipeline descobre o nome do cluster? | [ADR-0007](adr/0007-contrato-entre-repositorios-via-ssm.md) |
| Onde vive o segredo do JWT? | [RFC-0003](rfc/0003-estrategia-de-autenticacao.md), [ADR-0009](adr/0009-jwt-hs256-com-segredo-compartilhado.md) |
| Por que o cliente aprova por link, sem login? | [RFC-0003](rfc/0003-estrategia-de-autenticacao.md) |
| Por que o preço do item da OS é duplicado? | [ADR-0010](adr/0010-snapshot-de-precos-na-ordem-de-servico.md) |
| Por que a migration não roda no boot? | [ADR-0005](adr/0005-migrations-como-job-do-pipeline.md) |
| Por que o pipeline não usa chave de acesso AWS? | [ADR-0008](adr/0008-oidc-para-os-pipelines.md) |
| Como correlacionar erro do pod com log da borda? | [ADR-0011](adr/0011-logs-estruturados-com-correlacao.md) |
| Quanto custa o ambiente ligado? | [RFC-0001](rfc/0001-escolha-da-nuvem.md), [ADR-0006](adr/0006-duas-camadas-de-terraform.md) |

## Convenções

- **RFC** discute, **ADR** decide. Uma RFC pode originar várias ADRs.
- Numeração sequencial de quatro dígitos, nunca reaproveitada.
- Estados de ADR: `Proposta`, `Aceita`, `Substituída por ADR-XXXX`, `Revogada`.
- Uma ADR não é editada. Quando a decisão muda, a antiga é marcada como
  substituída e uma nova ocupa o lugar.
- Toda ADR nomeia as consequências negativas, e não apenas as positivas.
- Diagramas em [Mermaid](https://mermaid.js.org/), renderizados pelo GitHub.
  Diagrama em imagem binária não aparece em diff, e por isso não é usado.
- Valores em dólar são estimativas de lista de `sa-east-1` na data das RFCs,
  para comparação relativa.

## Estado das decisões

| RFC | Título | Estado | Origina |
|---|---|---|---|
| [RFC-0001](rfc/0001-escolha-da-nuvem.md) | Escolha da nuvem | Aceita | [ADR-0003](adr/0003-api-gateway-como-unica-porta-publica.md), 0006, 0008 |
| [RFC-0002](rfc/0002-escolha-do-banco-de-dados.md) | Escolha do banco de dados | Aceita | [ADR-0005](adr/0005-migrations-como-job-do-pipeline.md), 0010 |
| [RFC-0003](rfc/0003-estrategia-de-autenticacao.md) | Autenticação e autorização | Aceita | [ADR-0003](adr/0003-api-gateway-como-unica-porta-publica.md), 0009 |
| [RFC-0004](rfc/0004-estrategia-de-observabilidade.md) | Observabilidade | Aceita | [ADR-0011](adr/0011-logs-estruturados-com-correlacao.md) |
| [RFC-0005](rfc/0005-segregacao-em-repositorios.md) | Segregação em repositórios | Aceita | [ADR-0007](adr/0007-contrato-entre-repositorios-via-ssm.md), 0008 |

| ADR | Título | Estado | Impacta |
|---|---|---|---|
| [ADR-0001](adr/0001-registrar-decisoes-de-arquitetura.md) | Registrar decisões de arquitetura | Aceita | processo |
| [ADR-0002](adr/0002-comunicacao-sincrona-http.md) | Comunicação síncrona HTTP, sem broker | Aceita | aplicação |
| [ADR-0003](adr/0003-api-gateway-como-unica-porta-publica.md) | API Gateway como única porta pública | Aceita | rede, segurança |
| [ADR-0004](adr/0004-hpa-no-deployment-da-api.md) | HPA no Deployment da API | Aceita | Kubernetes |
| [ADR-0005](adr/0005-migrations-como-job-do-pipeline.md) | Migrations como Job do pipeline | Aceita | banco, pipeline |
| [ADR-0006](adr/0006-duas-camadas-de-terraform.md) | Duas camadas de Terraform | Aceita | infraestrutura, custo |
| [ADR-0007](adr/0007-contrato-entre-repositorios-via-ssm.md) | Contrato entre repositórios via SSM | Aceita | pipeline |
| [ADR-0008](adr/0008-oidc-para-os-pipelines.md) | OIDC para os pipelines | Aceita | segurança, CI/CD |
| [ADR-0009](adr/0009-jwt-hs256-com-segredo-compartilhado.md) | JWT HS256 com segredo compartilhado | Aceita | autenticação |
| [ADR-0010](adr/0010-snapshot-de-precos-na-ordem-de-servico.md) | Snapshot de preços na ordem de serviço | Aceita | banco, domínio |
| [ADR-0011](adr/0011-logs-estruturados-com-correlacao.md) | Logs estruturados com correlação | Proposta | observabilidade |

Para propor a substituição de uma ADR: leia a seção de alternativas da ADR em
vigor. Se a sua proposta já está listada ali, o argumento novo precisa atacar o
motivo registrado para o descarte.
