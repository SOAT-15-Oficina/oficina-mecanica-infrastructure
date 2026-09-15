# ADR-0001. Registrar decisões de arquitetura

**Aceita** · 2026-09-02 · Contexto: todos os repositórios

**Contexto.** O sistema é mantido por quatro pessoas em quatro repositórios.
Boa parte do racional arquitetural existia apenas em comentário de código e em
prosa dentro dos READMEs, o que serve a quem lê aquele arquivo e é invisível
para quem chega depois. Sem registro, a decisão é reaberta a cada onboarding, o
custo já pago para chegar nela é perdido, e alguém a reverte sem saber qual
problema ela resolvia.

**Decisão.** Manter dois tipos de documento em `docs/` do
`oficina-mecanica-infrastructure`, que é o repositório dono da visão de
sistema: **RFC** (`docs/rfc/`) discute, escrita antes de decidir, com problema,
alternativas e recomendação; **ADR** (`docs/adr/`) decide, uma por arquivo, no
formato contexto, decisão e consequências.

Regras: numeração sequencial de quatro dígitos, nunca reaproveitada; **ADR não
se edita**, e quando a decisão muda a antiga é marcada como `Substituída por
ADR-XXXX` e a nova é escrita ao lado; estados `Proposta`, `Aceita`,
`Substituída`, `Revogada`; toda ADR nomeia as consequências negativas; o
pipeline ignora mudanças em `**/*.md` e `docs/adr/**`, porque documentar não
dispara deploy.

**Consequências.** O motivo fica versionado ao lado da implementação e
revisável em Pull Request, e reabrir uma decisão passa a exigir argumento novo.
O custo é um documento a mais para manter, mitigado por ADRs curtas e pelo
critério de que decisão que não preenche uma página não precisa de ADR; e o
risco de ADR desatualizada, mitigado pela regra de substituir em vez de
corrigir.
