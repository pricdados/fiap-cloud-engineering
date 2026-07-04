![Cloud Engineering — FIAP](img/capa.png)

# FIAP — Cloud Engineering

Repositório de laboratórios práticos da disciplina. Cada lab é um passo a passo autossuficiente que você executa dentro do **GitHub Codespaces** contra uma conta **AWS Academy**, provisionando infraestrutura real com **Terraform** e destruindo tudo ao final para não acumular custo.

> [!IMPORTANT]
> **Primeira vez aqui?** Comece pelo [**01 - Setup e configuração de ambiente**](./01-create-codespaces/README.md). Sem o setup completo (fork, Codespaces, credenciais AWS e bucket de estado), os comandos do primeiro lab já falham.
>
> **Voltando para mais uma aula?** Faça o ritual rápido de [**01.1 - Início de toda aula**](./01-create-codespaces/Inicio-de-aula.md) (sync do fork + renovar credenciais — leva 3-5 min) e siga para o lab do dia.

## Como usar este repositório

- **Faça fork** deste repositório para a sua conta antes de criar o Codespaces (o setup explica o passo a passo).
- Cada pasta numerada é um módulo; dentro dela, cada subpasta numerada é um lab com seu próprio `README.md`.
- Todo lab abre com um callout `> [!WARNING]` de **pré-requisitos** e um **mapa do lab** com tempo estimado por parte — leia antes de começar para saber se dá tempo de fazer agora.
- Os blocos `<details><summary>💡 Clique para entender</summary>` aprofundam o "porquê"; pule se estiver com pressa.

## Trilha dos laboratórios

| # | Módulo / Lab | O que você faz | Tempo |
|---|--------------|----------------|-------|
| 01 | [Setup e configuração de ambiente](./01-create-codespaces/README.md) | Fork, Codespaces, conta AWS Academy, bucket S3 de estado e credenciais. | ~30 min |
| 01.1 | [Ritual de início de aula](./01-create-codespaces/Inicio-de-aula.md) | Sincronizar fork e renovar credenciais (repita a cada aula). | ~3-5 min |
| 02.1 | [Storage — Network File System (EFS)](./02-Storage/01-Network-file-system/README.md) | Provisiona EFS + EC2 e mede IOPS, block size e paralelismo sob carga. | ~60 min |
| 03.1 | [Compute — x86 vs Graviton](./03-Compute/01-X86-Graviton/README.md) | Sobe duas EC2 (Intel e Graviton) e roda benchmarks lado a lado. | ~50 min |
| 03.2 | [Compute — Containers com ECS + Fargate](./03-Compute/02-ECS-Fargate/README.md) | Build/push de imagem no ECR e deploy de container no Fargate. | ~45 min |
| 03.3 | [Compute — Serverless: Lambda orientada a eventos](./03-Compute/03-Lambda/README.md) | Pipeline de ingestão de dados em 3 fases (Lambda+S3 → SQS → Kinesis) com observabilidade. | ~50-60 min |
| 04 | [**Trabalho Final** — Modernizando a ingestão (EFS → S3 → Lambda → API)](./04-Trabalho-Final/README.md) | Amarra as 4 demos numa jornada end-to-end: migra do EFS para o S3, processa com Lambda Graviton e serve por uma API. Você completa o miolo do código. | ~2 h |

> [!NOTE]
> Os tempos acima são de execução pura. Some o tempo de leitura, observação dos resultados e reflexão — na prática, um lab leva de 2 a 4 vezes o tempo listado.

## Ferramentas e ambiente

O ambiente é definido por um **dev container** versionado em [`.devcontainer/`](./.devcontainer/README.md) — Ubuntu com Python, AWS CLI, Terraform, Node LTS, Docker-in-Docker e Serverless Framework já instalados. Qualquer aluno, em qualquer máquina, abre um ambiente idêntico ao do professor em segundos.

> [!CAUTION]
> A conta AWS Academy tem crédito limitado e sessões de 4 horas. **Sempre rode o `terraform destroy` no final de cada lab** e **desligue o Codespaces** (`Stop Codespace`) ao terminar a aula. Recurso esquecido ligado consome o orçamento e o tempo gratuito do Codespaces.

---

<details>
<summary><b>💡 Como pedir ajuda se travou</b></summary>
<blockquote>

**Antes de abrir issue ou chamar o professor, colete:**

1. Em qual lab e em qual passo (número) travou.
2. A mensagem de erro **literal** (copie e cole, não resuma).
3. O que `aws sts get-caller-identity` retorna agora.
4. Em qual ambiente o erro apareceu (Codespaces ou sessão SSM da EC2).

**Canais, em ordem:**

1. [Issues deste repositório](https://github.com/vamperst/fiap-cloud-engineering/issues) — preferido, cria histórico pesquisável para os próximos alunos.
2. Email do professor com os 4 itens acima.
3. Na sala de aula, durante o laboratório.

</blockquote>
</details>
