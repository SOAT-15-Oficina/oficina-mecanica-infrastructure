# ADR-0001 — Registrar decisões de arquitetura

- **Estado:** Aceita
- **Data:** 2026-09-02
- **Contexto:** todos os repositórios

## Contexto

O sistema é mantido por quatro pessoas em quatro repositórios. Boa parte do
racional arquitetural existia apenas em comentário de código e em prosa dentro
dos READMEs — bom para quem lê aquele arquivo, invisível para quem chega
depois e pergunta "por que não fizeram do jeito óbvio?".

Sem registro, três coisas acontecem: a decisão é reaberta a cada onboarding, o
custo já pago para chegar nela é perdido, e alguém a reverte sem saber qual
problema ela resolvia.

## Decisão

Manter dois tipos de documento em `docs/` do
`oficina-mecanica-infrastructure` — o repositório que já se declara dono da
visão de sistema:

- **RFC** (`docs/rfc/`) — *discute*. Escrita antes de decidir: problema,
  alternativas com prós e contras, recomendação. Pode gerar várias ADRs.
- **ADR** (`docs/adr/`) — *decide*. Uma decisão por arquivo, no formato
  contexto / decisão / consequências.

Regras:

1. Numeração sequencial de quatro dígitos, nunca reaproveitada.
2. **ADR não se edita.** Quando a decisão muda, marca-se a antiga como
   `Substituída por ADR-XXXX` e escreve-se a nova. O registro do que se pensava
   antes tem valor.
3. Estados: `Proposta` → `Aceita` → `Substituída` / `Revogada`.
4. Toda ADR nomeia as consequências negativas. ADR sem custo listado é
   propaganda, não decisão.
5. O pipeline ignora mudanças em `**/*.md` e `docs/adr/**` — documentar não
   dispara deploy.

## Consequências

**Positivas**
- O "porquê" fica versionado ao lado do "o quê", revisável em Pull Request.
- Reabrir uma decisão passa a exigir argumento novo, não só opinião nova.
- Atende ao requisito formal de RFCs e ADRs da fase.

**Negativas**
- Documento a mais para manter. Mitigado por ADRs curtas e pelo fato de que
  decisão que não vale uma página não vale uma ADR.
- Risco de ADR desatualizada. Mitigado pela regra 2: ADR errada não se corrige,
  se substitui.
