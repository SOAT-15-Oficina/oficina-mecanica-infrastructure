# bootstrap

Aplicado **uma única vez**, com credencial humana, antes de qualquer outra
coisa. Resolve o ovo-e-galinha das outras duas camadas:

- o backend remoto precisa de um bucket S3 que ainda não existe;
- os pipelines autenticam por OIDC assumindo roles que ainda não existem.

Guarda o state **localmente** (`terraform.tfstate`, versionado neste
repositório por ser o único jeito de o time compartilhá-lo sem um bucket).
Não contém segredo algum — só um bucket e uma tabela de lock.

```bash
cd bootstrap
terraform init
terraform apply
```

Depois disso, `persistent/` e `ephemeral/` usam o backend remoto normalmente.
