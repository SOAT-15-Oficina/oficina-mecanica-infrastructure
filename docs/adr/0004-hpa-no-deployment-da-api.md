# ADR-0004 — HPA no Deployment da API

- **Estado:** Aceita
- **Data:** 2026-09-02
- **Relacionada:** [ADR-0005](0005-migrations-como-job-do-pipeline.md)

## Contexto

A fase exige um cluster Kubernetes **com escalabilidade**. Ter um cluster e
deixar a aplicação em réplica fixa cumpriria a letra e não o espírito: o cluster
existiria como hospedeiro caro de um processo único.

A carga da oficina é irregular por natureza — picos na abertura da manhã, na
entrega do fim da tarde, e rajadas quando um lote de orçamentos é enviado e os
clientes clicam nos links de aprovação quase ao mesmo tempo.

## Decisão

**`HorizontalPodAutoscaler` v2 no Deployment `api`, de 2 a 10 réplicas, guiado
por utilização de CPU com alvo de 70%**, e `metrics-server` instalado via Helm
como fonte das métricas.

Piso **2**, não 1: com uma réplica, todo rollout e toda evicção de nó geram
janela sem atendimento. Duas réplicas dão continuidade durante o `RollingUpdate`
e sobrevivem à perda de um nó.

Teto **10**: acima disso o gargalo deixa de ser CPU do pod e passa a ser
`max_connections` do RDS. Escalar além só trocaria "requisição lenta" por
"conexão recusada".

Cada pod declara `requests` de 100m/128Mi e `limits` de 500m/256Mi. `requests`
não é decorativo aqui: **é o denominador do cálculo do HPA**. Sem ele, não há
percentual de utilização e o autoscaler não funciona.

Probes: `liveness` e `readiness` apontam para `/ready`, que faz `Ping` no pool
do banco com timeout de 2s. Um pod que perdeu o banco sai do balanceamento em
vez de responder 500.

O Terraform declara o Deployment mas ignora dois campos:

```hcl
lifecycle {
  ignore_changes = [
    spec[0].template[0].spec[0].container[0].image,  # dono: pipeline do -monolith
    spec[0].replicas,                                # dono: o HPA
  ]
}
```

Sem `ignore_changes` em `replicas`, todo `terraform apply` devolveria a contagem
ao valor declarado, desfazendo a decisão do autoscaler.

## Alternativas consideradas

**Réplica fixa.** Mais simples, e o requisito de "cluster com escalabilidade"
seria defensável pelo node group. Descartada: o node group escala nós, não
aplicação — sem HPA, novos nós ficam ociosos.

**KEDA com métrica de fila.** Não há fila ([ADR-0002](0002-comunicacao-sincrona-http.md)).

**HPA por memória.** A aplicação é I/O bound com uso de memória estável; o
indicador que se move sob carga é CPU.

**Cluster Autoscaler / Karpenter.** O node group tem `min = desired` e
`max = desired + 2`, dando folga para o HPA crescer sem provisionar nós novos.
Autoscaler de nó seria a evolução, mas adiciona um controller a operar por um
ganho que o teto de 10 pods ainda não exige.

## Consequências

**Positivas**
- Absorve pico sem intervenção e volta a 2 réplicas depois, sem custo parado.
- Rollout sem downtime cai de graça junto com o piso 2.
- `metrics-server` também habilita `kubectl top`, útil para inspecionar consumo
  real de CPU e memória sem instrumentação extra.

**Negativas**
- **Réplicas ≥ 2 tornam migration no boot uma corrida de DDL.** Foi o que
  motivou a [ADR-0005](0005-migrations-como-job-do-pipeline.md).
- Mais pods, mais conexões ao RDS. O teto de 10 é o que segura isso; se subir,
  o próximo passo é RDS Proxy, não mais réplicas.
- `metrics-server` é dependência adicional: se ele cair, o HPA congela na
  contagem atual (falha segura, mas silenciosa sem alerta).
- Escala reativa. Um pico instantâneo pega 2 réplicas e leva ~1 min para
  estabilizar.
