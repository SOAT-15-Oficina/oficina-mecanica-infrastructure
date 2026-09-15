# ADR-0004. HPA no Deployment da API

**Aceita** · 2026-09-02 · Relacionada [ADR-0005](./0005-migrations-como-job-do-pipeline.md)

**Contexto.** O desafio exige um cluster Kubernetes **com escalabilidade**.
Réplica fixa atenderia à letra do requisito, mas o cluster existiria apenas
como hospedeiro caro de um processo único. A carga da oficina é irregular:
picos na abertura da manhã, na entrega do fim da tarde, e rajadas quando um
lote de orçamentos é enviado e os clientes clicam nos links quase ao mesmo
tempo.

**Decisão.** `HorizontalPodAutoscaler` v2 no Deployment `api`, de 2 a 10
réplicas, guiado por utilização de CPU com alvo de 70%, e `metrics-server`
instalado via Helm como fonte das métricas.

- **Piso 2**, não 1: com uma réplica, todo rollout e toda evicção de nó geram
  janela sem atendimento.
- **Teto 10**: acima disso o gargalo deixa de ser CPU do pod e passa a ser
  `max_connections` do RDS, trocando requisição lenta por conexão recusada.
- `requests` de 100m e 128Mi, `limits` de 500m e 256Mi. `requests` é o
  **denominador do cálculo do HPA**: sem ele não há percentual de utilização e
  o autoscaler não funciona.
- `liveness` e `readiness` apontam para `/ready`, que faz `Ping` no pool do
  banco com timeout de 2s, para que um pod sem banco saia do balanceamento em
  vez de responder 500.

```hcl
lifecycle {
  ignore_changes = [
    spec[0].template[0].spec[0].container[0].image,  # dono: pipeline do -monolith
    spec[0].replicas,                                # dono: o HPA
  ]
}
```

Sem `ignore_changes` em `replicas`, todo `terraform apply` devolveria a
contagem ao valor declarado, desfazendo a decisão do autoscaler.

## Alternativas descartadas

| Opção | Motivo do descarte |
|---|---|
| Réplica fixa | o node group escala nós, não aplicação: sem HPA, novos nós ficam ociosos |
| KEDA com métrica de fila | não há fila ([ADR-0002](./0002-comunicacao-sincrona-http.md)) |
| HPA por memória | a aplicação é I/O bound com memória estável; o indicador que se move sob carga é CPU |
| Cluster Autoscaler ou Karpenter | o node group tem `min = desired` e `max = desired + 2`, o que dá folga para o HPA crescer. Autoscaler de nó adiciona um controller a operar por um ganho que o teto de 10 pods não exige |

## Consequências

| Ganhos | Custos |
|---|---|
| Absorve pico sem intervenção e volta a 2 réplicas, sem custo parado | **réplicas de 2 ou mais tornam migration no boot uma corrida de DDL**, o que motivou a [ADR-0005](./0005-migrations-como-job-do-pipeline.md) |
| Rollout sem downtime vem junto com o piso 2 | mais pods, mais conexões ao RDS; se o teto subir, o próximo passo é RDS Proxy |
| `metrics-server` habilita `kubectl top` sem instrumentação extra | se o `metrics-server` cair, o HPA congela na contagem atual: falha segura, mas silenciosa sem alerta |
| | escala reativa: um pico instantâneo pega 2 réplicas e leva cerca de 1 minuto para estabilizar |
