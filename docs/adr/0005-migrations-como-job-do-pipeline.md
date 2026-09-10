# ADR-0005 — Migrations como Job do pipeline, não no boot da aplicação

- **Estado:** Aceita
- **Data:** 2026-09-02
- **Relacionada:** [ADR-0004](0004-hpa-no-deployment-da-api.md)

## Contexto

O binário do monolito rodava as migrations ao subir. Funcionava com uma réplica.

Com o HPA de 2 a 10 réplicas ([ADR-0004](0004-hpa-no-deployment-da-api.md)), N
processos passam a executar o mesmo DDL simultaneamente durante um rollout. O
`goose` toma lock na tabela de versões, mas o resultado no melhor caso é um pod
esperando o outro; no pior, um pod falha o boot, entra em `CrashLoopBackOff` e o
rollout trava.

Havia também um problema de ordem: com `RollingUpdate`, pods da versão nova
sobem enquanto os da versão antiga ainda servem. Se a migration for aplicada por
um pod novo, os antigos passam a ver um schema que não conhecem.

## Decisão

**Separar os dois modos no mesmo binário e rodar a migration como `Job` do
Kubernetes, antes do rollout.**

```
techchallenge            sobe a API
techchallenge migrate    aplica as migrations e sai
```

O pipeline do `oficina-mecanica-monolith`, entre o push da imagem e o
`kubectl set image`:

1. Cria um `Job` `migrate-<sha[:12]>` com a **imagem nova**, `backoffLimit: 0` e
   `ttlSecondsAfterFinished: 600`.
2. Espera `--for=condition=complete` com timeout de 300s.
3. Em falha, imprime as últimas 200 linhas de log do Job e aborta — **o rollout
   não acontece**.
4. Só então faz `set image` e `rollout status`.

Duas restrições do Kubernetes moldaram a implementação:

- **`spec.template` de um `Job` é imutável.** Não dá para criar o Job e depois
  aplicar `patch` com as variáveis de ambiente: o patch falha com
  `field is immutable`, e o Job já terá sido criado sem as variáveis. Por isso o
  manifesto vai completo de uma vez, com `envFrom` referenciando o mesmo
  `ConfigMap` e o mesmo `Secret` do Deployment.
- **Nome do Job é imutável.** Reexecutar o mesmo commit colidiria; daí o
  `delete --ignore-not-found` antes do `apply`.

## Alternativas consideradas

**Init container no Deployment.** Roda uma vez por pod — com 10 réplicas, dez
execuções concorrentes. Não resolve nada.

**Helm hook `pre-upgrade`.** É exatamente este padrão, mas exigiria adotar Helm
para a aplicação. O Deployment é criado pelo Terraform
([ADR-0007](0007-contrato-entre-repositorios-via-ssm.md)); introduzir Helm criaria
um terceiro dono do manifesto.

**Migration manual antes do deploy.** Passo humano em pipeline automatizado —
esquecível e não auditável.

**Lock distribuído no boot (advisory lock).** Um pod aplica, os outros esperam.
Continua misturando responsabilidades e não resolve a ordem de versões.

## Consequências

**Positivas**
- Uma execução por deploy, com resultado explícito antes de qualquer pod novo
  receber tráfego.
- Migration que falha aborta o deploy com log — em vez de `CrashLoopBackOff`
  silencioso.
- O boot da aplicação fica mais rápido e sem responsabilidade de schema.

**Negativas**
- **Migrations precisam ser compatíveis com a versão anterior do código**, pois
  o Job roda antes do rollout: durante alguns segundos, o código antigo fala com
  o schema novo. Na prática isso significa migrations aditivas — remoção de
  coluna exige dois deploys.
- Mais um passo no pipeline, com timeout próprio.
- Rodar `migrate` localmente virou passo explícito (`go run ./cmd/api migrate`).
