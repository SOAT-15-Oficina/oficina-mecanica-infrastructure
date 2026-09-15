# ADR-0005. Migrations como Job do pipeline, não no boot da aplicação

**Aceita** · 2026-09-02 · Relacionada [ADR-0004](./0004-hpa-no-deployment-da-api.md)

**Contexto.** O binário do monolito rodava as migrations ao subir, o que
funcionava com uma réplica. Com o HPA de 2 a 10 réplicas
([ADR-0004](./0004-hpa-no-deployment-da-api.md)), N processos passam a executar o mesmo DDL durante um
rollout. O `goose` toma lock na tabela de versões, mas no melhor caso um pod
espera o outro e no pior um pod falha o boot, entra em `CrashLoopBackOff` e o
rollout trava. Há também um problema de ordem: com `RollingUpdate`, se a
migration for aplicada por um pod novo, os antigos passam a ver um schema que
não conhecem.

**Decisão.** Separar os dois modos no mesmo binário e rodar a migration como
`Job` do Kubernetes, antes do rollout.

```
techchallenge            sobe a API
techchallenge migrate    aplica as migrations e sai
```

O pipeline do `oficina-mecanica-monolith`, entre o push da imagem e o
`kubectl set image`:

1. Cria um `Job` `migrate-<sha[:12]>` com a **imagem nova**, `backoffLimit: 0`
   e `ttlSecondsAfterFinished: 600`.
2. Espera `--for=condition=complete`, com timeout de 300s.
3. Em caso de falha, imprime as últimas 200 linhas de log do Job e aborta. **O
   rollout não acontece.**
4. Só então executa `set image` e `rollout status`.

Duas restrições do Kubernetes moldaram a implementação. O `spec.template` de um
`Job` é imutável, então não dá para criar o Job e depois aplicar `patch` com as
variáveis de ambiente: o manifesto vai completo de uma vez, com `envFrom`
referenciando o mesmo `ConfigMap` e o mesmo `Secret` do Deployment. E o nome do
Job é imutável, o que faria reexecutar o mesmo commit colidir, daí o
`delete --ignore-not-found` antes do `apply`.

## Alternativas descartadas

| Opção | Motivo do descarte |
|---|---|
| Init container no Deployment | roda uma vez por pod: com 10 réplicas, dez execuções concorrentes |
| Helm hook `pre-upgrade` | é exatamente este padrão, mas exigiria adotar Helm para a aplicação. O Deployment é criado pelo Terraform ([ADR-0007](./0007-contrato-entre-repositorios-via-ssm.md)), e Helm criaria um terceiro dono do manifesto |
| Migration manual antes do deploy | passo humano em pipeline automatizado: esquecível e não auditável |
| Advisory lock no boot | continua misturando responsabilidades e não resolve a ordem de versões |

## Consequências

| Ganhos | Custos |
|---|---|
| Uma execução por deploy, com resultado explícito antes de qualquer pod novo receber tráfego | **migrations precisam ser compatíveis com a versão anterior do código**, porque o Job roda antes do rollout: na prática, migrations aditivas, e remover coluna exige dois deploys |
| Migration que falha aborta o deploy com log, em vez de `CrashLoopBackOff` silencioso | mais um passo no pipeline, com timeout próprio |
| Boot mais rápido e sem responsabilidade de schema | rodar `migrate` localmente passou a ser passo explícito (`go run ./cmd/api migrate`) |
