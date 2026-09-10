# ADR-0008 — OIDC para os pipelines, sem chaves estáticas

- **Estado:** Aceita
- **Data:** 2026-09-02
- **Relacionada:** [ADR-0007](0007-contrato-entre-repositorios-via-ssm.md), [RFC-0005](../rfc/0005-segregacao-em-repositorios.md)

## Contexto

Quatro repositórios fazem deploy em dois ambientes na mesma conta AWS. O caminho
usual — `AWS_ACCESS_KEY_ID` e `AWS_SECRET_ACCESS_KEY` como secrets — cria oito
pares de credenciais permanentes, que não expiram, que ninguém rotaciona e que
vazam por inteiro se um log imprimir a variável errada.

Há um risco adicional específico deste desenho: como homologação e produção
vivem na **mesma conta AWS**, separadas por prefixo de nome, uma credencial de
homologação com política frouxa alcançaria recursos de produção.

## Decisão

**Nenhuma chave estática de AWS existe. Os pipelines autenticam por OIDC**, com
um provider `token.actions.githubusercontent.com` e **quatro roles por ambiente**
— uma por repositório.

A trust policy de cada role restringe simultaneamente:

- o **repositório** de origem,
- o **ref**: a role de homologação só aceita `ref:refs/heads/hml`; a de produção,
  `refs/heads/main`,
- o **GitHub Environment**: `environment:homolog` ou `environment:production`.

Um push em `hml` não obtém credencial de produção nem trocando o ARN no secret —
a AWS recusa antes.

Do lado do GitHub, a mesma regra aparece duas vezes:

- `environment: ${{ github.ref_name == 'hml' && 'homolog' || 'production' }}` no
  job;
- um `case` explícito sobre `GITHUB_REF_NAME` que **falha alto** se alguém
  acrescentar uma branch ao gatilho e esquecer do mapa.

**A branch é a única fonte da verdade.** Nenhum workflow de aplicação tem input
de ambiente: o `ref` já carrega a informação, e um input separado poderia
contradizê-lo — fazendo deploy do código de uma branch no ambiente da outra.
`bring-up` e `tear-down` têm input porque são manuais, mas abortam se ele não
bater com o ref de onde foram disparados.

`AWS_DEPLOY_ROLE_ARN` é secret **do GitHub Environment**, não do repositório: os
dois ambientes usam o mesmo nome e só o escopo do Environment os separa.
Permissões do workflow: `contents: read` e `id-token: write` — nada além.

## Alternativas consideradas

**Chaves de acesso em secrets.** Descartada: credencial permanente, rotação
manual, e nada impediria a de homologação de agir em produção.

**Uma role para os quatro repositórios.** Menos IAM para manter, mas o pipeline
do frontend passaria a poder alterar o EKS. Cada role concede o mínimo do seu
repositório: o do monolito tem `eks:DescribeCluster` e push no ECR; o do
frontend, `s3:PutObject` no bucket e `cloudfront:CreateInvalidation`.

**Duas contas AWS.** Isolamento real, e foi seriamente considerada. Exigiria um
segundo bootstrap, um segundo provider OIDC e **reverificar o e-mail no SES da
conta nova** — o passo manual que a camada persistente existe para evitar. A
escolha foi isolamento por IAM + nomeação, com o custo registrado abaixo.

## Consequências

**Positivas**
- Zero credencial de longa duração. Nada a rotacionar, nada a vazar.
- Blast radius por repositório e por ambiente, imposto pela AWS.
- Acesso ao EKS via `aws_eks_access_entry`, sem editar `aws-auth` à mão.

**Negativas**
- **Ovo e galinha em ambiente novo.** A role que o CI assume nasce do primeiro
  `apply` da camada persistente — que precisa de credencial humana. Documentado
  no README como passo único.
- IAM mais verboso: 8 roles em vez de 1, cada uma com trust policy própria.
- **Isolamento por IAM, não por conta.** Um erro de política — um `Resource: "*"`
  onde deveria haver prefixo — atravessa ambientes. É o risco aceito ao usar uma
  conta só, e a policy IRSA do SES de fato usa `resources = ["*"]` por
  necessidade do serviço.
- Erro de configuração aparece como `AssumeRoleWithWebIdentity` negado, cuja
  mensagem não diz qual das três condições falhou.
