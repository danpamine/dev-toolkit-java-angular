# Dev Toolkit

Automação inteligente de qualidade, segurança e governança de dependências para projetos **Java** e **Angular**, sem modificar uma única linha de código ou configuração nos repositórios da sua organização.

---

## Por que usar

O Dev Toolkit padroniza a entrega de software com alta qualidade e segurança de ponta a ponta, independentemente de os repositórios corporativos possuírem ou não esteiras locais configuradas. Em vez de depender de aprovações burocráticas para incluir plugins em dezenas de `pom.xml` ou `package.json`, o toolkit centraliza as verificações na máquina do desenvolvedor, atualiza ferramentas em background e valida o código antes mesmo da abertura do Pull Request.

---

## Dicionário de Siglas e Conceitos

Entender o propósito de cada mecanismo agiliza o diagnóstico quando a esteira apontar desvios:

* **SAST (Static Application Security Testing)**:
  * *O que é*: Análise estática de segurança aplicada diretamente no código-fonte (`.java`, `.ts`, `.js`).
  * *Por que validar*: Identifica falhas lógicas e brechas graves (como SQL Injection, Cross-Site Scripting (XSS), desserialização insegura, uso de métodos vulneráveis e credenciais expostas) sem compilar ou rodar o sistema.
* **SCA (Software Composition Analysis)**:
  * *O que é*: Varredura de segurança nas bibliotecas e dependências declaradas nos manifestos (`pom.xml`, `package-lock.json`).
  * *Por que validar*: Mais de 80% do ecossistema de uma aplicação moderna vem de código aberto. O SCA detecta se alguma dependência possui vulnerabilidades mapeadas e bloqueia apenas aquelas que já contam com correção (patch disponível).
* **SBOM (Software Bill of Materials)**:
  * *O que é*: A lista formal de componentes de software (CycloneDX / SPDX).
  * *Por que validar*: Garante rastreabilidade total. Em caso de vulnerabilidades de dia-zero no mercado, permite identificar imediatamente quais projetos contêm o artefato comprometido.
* **AST (Abstract Syntax Tree)**:
  * *O que é*: Árvore de sintaxe abstrata do código-fonte. O linter decompõe o código em sua representação sintática em vez de inspecioná-lo como mero texto ou Regex.
  * *Por que validar*: Ferramentas como o `ast-grep` executam em milissegundos e detectam com precisão cirúrgica comandos proibidos de depuração (`debugger;`, `console.log`, chamadas diretas a prints de sistema) e anti-patterns sem gerar falsos positivos.
* **CVE (Common Vulnerabilities and Exposures)**:
  * *O que é*: O identificador internacional de uma vulnerabilidade conhecida (ex: `CVE-2026-12345`).
  * *Por que validar*: Permite checar a severidade da falha e confirmar a versão que resolve o problema.
* **TTL (Time-To-Live)**:
  * *O que é*: Tempo de vida útil do cache local. No Dev Toolkit, o TTL é configurado estritamente para **3 horas** (10800 segundos).
  * *Por que usar*: Scanners de CVEs consultam bases externas dinâmicas. O cache evita reexecuções demoradas a cada commit consecutivo, expirando a cada 3 horas para garantir a detecção de vulnerabilidades catalogadas no dia.
* **DAG (Directed Acyclic Graph)**:
  * *O que é*: Grafo direcionado acíclico de dependências que orquestra a execução concorrente.
  * *Por que usar*: Dispara etapas independentes em paralelo (linters, checagens de versão e SAST semântico) e retém em espera apenas validações que dependem estritamente da compilação de binários.
* **SemVer & Strict Increment**:
  * *O que é*: Versionamento Semântico e regra estrita de incremento de versão.
  * *Por que validar*: Impede a abertura de Pull Requests com versões idênticas (`1.0.0 == 1.0.0`) ou regredidas (`0.9.0 < 1.0.0`) em relação à branch base remota (ex: `origin/develop`), garantindo que a esteira de CI/CD corporativa gere releases ordenadas.

---

## Princípios de Projeto

* **Invasão Zero aos Projetos**: Nenhuma dependência, script npm ou arquivo de configuração (`.eslintrc`, `checkstyle.xml`, etc.) é commitado nos repositórios corporativos.
* **Isolamento Total entre Stacks**: Configurações, diretórios e branches de Java e Angular são desacoplados. Você pode habilitar apenas a stack que utiliza.
* **Operação em Espaço de Usuário**: Projetado para Windows corporativo restrito (Git Bash / MSYS2) sem exigir permissões de Administrador.
* **Execução Assíncrona & Buffer Isolado de Logs**: Todas as validações ocorrem em paralelo em background. Se múltiplos linters ou testes falharem ao mesmo tempo, os relatórios são organizados sequencialmente no final da execução, sem truncamento de tabelas ou poluição visual.
* **Auto-Atualização e Resiliência de Rede**: O Dev Toolkit se mantém sincronizado via Git e gerencia binários com fallback por web scraping (imune a Rate Limit da API do GitHub). Quando o toolkit é atualizado no início de uma execução, a validação é abortada imediatamente com instrução de reexecução: nunca se valida com código defasado. Além disso, as etapas Maven (compilação, SBOM, Checkstyle, SpotBugs, PMD, OpenAPI e testes) formam uma corrente serializada, evitando que ferramentas concorrentes interfiram no mesmo diretório `target/`.

---

## Pré-requisitos

* **Sistema Operacional**: Windows 10/11 ou Linux.
* **Terminal**: Git Bash (MSYS2).
* **Git**: CLI do `git` configurada e acessível no PATH.
* **Java** (se atuar na stack Java): JDK 17+ e Maven (`mvn`) no PATH.
* **Node.js** (se atuar na stack Angular): Opcional antes do setup (o instalador configura NVS + Node.js LTS + pnpm automaticamente).

---

## Instalação e Configuração Interativa

Abra o terminal **Git Bash** e execute:

    git clone https://github.com/danpamine/dev-toolkit.git "$HOME/dev-toolkit"
    cd "$HOME/dev-toolkit"
    bash scripts/setup-bashrc.sh
    source ~/.bashrc

Inicie o assistente de configuração interativo:

    dev init

O assistente guiará a configuração de ponta a ponta:

1. **Seleção de Stacks**: Escolha se você atua em **Java**, **Angular** ou **Ambos**. As perguntas das stacks não selecionadas são suprimidas.
2. **Diretórios de Ferramentas e Caches**: Você define os caminhos de destino (ex: diretório de binários locais, pasta do Python portátil, cache de validações e a pasta da store global do `pnpm-store`).
3. **Branch Base por Stack**: Configure a branch de destino dos PRs de forma independente (ex: `develop` para Java e `develop` ou `main` para Angular).
4. **Perfil de Feature Toggles**: Escolha entre o perfil **Completo**, **Rápido** (sem ferramentas de compilação profunda como SpotBugs e Trivy) ou **Personalizado** (selecionando ferramenta por ferramenta).
5. **Configuração Automática de Hooks**: O assistente varre o diretório informado e instala os Git Hooks em todos os repositórios encontrados.

---

## Fluxos de Validação Automatizados

```text
[git commit] --> Validação Incremental (Apenas arquivos alterados em Staging)
[git push]   --> Validação da Branch vs. Branch Base Remota (Strict Version Check + SAST + SCA + Build)
[git pull]   --> Integridade Pós-Merge (Gitleaks Full Scan em todo o repositório)
[dev verify] --> Validação Completa sob demanda (todos os testes, linters e scanners)
```

### 1. `git commit` (Pre-commit Incremental)
* Inspeciona **apenas** os arquivos em staging (`git diff --cached`). Código legado não modificado é ignorado.
* **Java**: Google Java Format incremental, Checkstyle e ast-grep.
* **Angular**: Prettier incremental, ESLint Security e ast-grep.
* **Gitleaks**: Varre commits em preparação contra vazamentos de tokens, senhas e chaves privadas.

### 2. `git push` (Pre-push Estrito)
* Inspeciona as diferenças entre a branch atual e a branch base remota (`merge-base`).
* **Version Check Estrito**: Bloqueia o push se a versão local for menor ou igual à versão da branch base remota.
* **SCA & SAST**: Trivy SCA, Google OSV-Scanner e Semgrep OSS (rodando estritamente nos arquivos alterados).
* **Testes & Qualidade**: Execução inteligente de testes unitários (Maven / Angular) e validação de contratos OpenAPI.

### 3. Convenção Visual do Terminal
O Dev Toolkit padroniza as respostas no console e no sumário executivo:
* `[ OK ]` (Verde): Validação aprovada. Se aprovada com reaproveitamento de hash, exibe `(Cache)` em verde brilhante.
* `[FALHA]` (Vermelho): Reprovação imediata. O motivo e o relatório detalhado de erros são exibidos no rodapé.
* `[PULADO]` (Amarelo): Etapa desativada via Feature Toggle ou desnecessária (ex: repositório sem testes físicos).
* `[BLOQUEADO]` (Púrpura/Magenta): Etapa cancelada preventivamente por falha em uma etapa predecessora da qual dependia (ex: compilação Maven bloqueada por reprovação no SpotBugs).

---

## Utilitário CLI `dev`

O comando `dev` fica disponível globalmente no seu terminal:

    dev init           Inicia o assistente de configuração interativa de stacks e caminhos
    dev verify         Executa a validação completa assíncrona do repositório atual
    dev base <branch>  Define ou altera a branch base para o projeto atual (ex: dev base develop)
    dev install        Instala dependências do projeto (mvn install | pnpm install)
    dev run            Executa a aplicação com os perfis locais configurados (mvn | pnpm start)
    dev test           Executa a suíte de testes unitários de forma autônoma
    dev lint           Roda manualmente as verificações de pre-commit
    dev format         Aplica formatação no código alterado (Google Java Format / Prettier)
    dev build          Compila o projeto (mvn test-compile | ng build)
    dev hooks-install  Instala os Git Hooks em um diretório ou projeto
    dev hooks-remove   Remove os Git Hooks configurados
    dev clean          Limpa caches locais e logs temporários (preserva a base local do OSV)
    dev setup-node     Instala ou atualiza NVS, Node LTS e PNPM corporativo

---

## Resolução Inteligente de Testes

Para evitar quebras em microfrontends, bibliotecas ou serviços sem suíte de testes:
* **Java**: O ciclo de testes (`mvn test jacoco:report`) só é acionado se existirem arquivos físicos `.java` dentro do diretório `src/test/java`. Se o diretório não existir ou estiver vazio, a etapa encerra imediatamente como `[ OK ] (Sem testes no projeto)`.
* **Angular**: A etapa só é executada se houver um script de teste configurado no `package.json`, target `test` declarado no `angular.json` **e** arquivos físicos de teste (`*.spec.ts`, `*.test.ts`) no projeto.

---

## Arquitetura de Configurações e Feature Toggles

Nenhuma alteração do desenvolvedor é versionada no repositório do toolkit ou nos projetos corporativos. As variáveis seguem uma hierarquia estrita:

```text
1. Defaults Versionados (env/<stack>/global.env)
       ↓
2. Preferências Globais de Diretórios (env/.env.user)
       ↓
3. Preferências por Stack do Dev (env/<stack>/.env.user)
       ↓
4. Overrides Pontuais do Repositório Atual (.env.local)
```

### Arquivos Gerados (Protegidos no `.gitignore`):
* `env/.env.user`: Contém `LOCAL_BIN`, `DEV_TOOLKIT_PYTHON_DIR` e `DEV_TOOLKIT_CACHE_DIR`.
* `env/java/.env.user`: Contém `BASE_BRANCH` e toggles `FEATURE_*` para Java.
* `env/angular/.env.user`: Contém `BASE_BRANCH`, `DEV_TOOLKIT_STORE_DIR` e toggles `FEATURE_*` para Angular.
* `.env.local`: Configuração criada na raiz de um projeto específico ao executar `dev base <branch>`.
* `env/vuln-exceptions/global.list` e `env/vuln-exceptions/<REPO_NAME>.list`: Exceções de vulnerabilidades (opcionais, criadas por você, veja a seção dedicada).

### Chaves de Toggles Disponíveis:
* `FEATURE_VERSION_CHECK`: Validação semântica de versão em `pom.xml` ou `package.json`.
* `FEATURE_GITLEAKS`: Varredura de credenciais e segredos em staging.
* `FEATURE_SEMGREP`: Análise estática semântica SAST via Semgrep OSS nativo.
* `FEATURE_SEMGREP_REQUIRED`: Falha a execução (em vez de pular) quando o Semgrep não puder ser instalado.
* `FEATURE_AST_GREP`: Linter estrutural de AST via ast-grep.
* `FEATURE_OSV`: Varredura de vulnerabilidades de dependências via Google OSV-Scanner.
* `FEATURE_SCA`: Análise profunda de componentes via Trivy SCA.
* `FEATURE_SPOTBUGS`: Análise de bytecode Java com SpotBugs e FindSecBugs.
* `FEATURE_PMD`: Análise de qualidade e boas práticas de código Java.
* `FEATURE_CHECKSTYLE`: Verificação de regras de estilo em código Java.
* `FEATURE_JAVA_FORMAT`: Auto-formatação com Google Java Format.
* `FEATURE_OPENAPI`: Validação de contratos Swagger/OpenAPI.
* `FEATURE_MAVEN_VERIFY`: Execução de testes unitários e cobertura JaCoCo no Java.
* `FEATURE_ESLINT`: Linter de código e regras de segurança para Angular.
* `FEATURE_PRETTIER`: Auto-formatação de código Angular via Prettier.
* `FEATURE_LOCKFILE`: Sincronização e integridade do lockfile.
* `FEATURE_BUILD`: Compilação de produção do Angular (`ng build`).
* `FEATURE_TEST`: Execução de testes unitários Angular via `package.json`.

---

## Exceções de Vulnerabilidades (Configuração Opcional)

Quando uma dependência só tem correção via upgrade major incompatível com o roadmap, o toolkit permite registrar a exceção de risco **dentro do próprio toolkit**, jamais nos projetos corporativos (Invasão Zero). Os arquivos não existem por padrão e não são versionados: você os cria apenas quando houver decisão a registrar. O mecanismo é útil tanto para o dev individual quanto para times que adotam o toolkit coletivamente.

### Arquivos (criados por você, protegidos no `.gitignore`)

```text
env/vuln-exceptions/global.list        -> Aplica a todas as análises de todas as stacks
env/vuln-exceptions/<REPO_NAME>.list   -> Aplica apenas ao projeto de mesmo nome
```

### Formato (uma exceção por linha)

```text
ID1[,ID2,...] | DATA_DE_EXPIRACAO (YYYY-MM-DD) | motivo
```

* **IDs**: `CVE-...` e/ou `GHSA-...`. Aliases da **mesma** vulnerabilidade na mesma linha (Trivy reporta `CVE`, OSV-Scanner reporta `GHSA`); o grupo casa em qualquer uma das ferramentas.
* **Expiração**: vencida, a vulnerabilidade volta a bloquear automaticamente. A data força a reavaliação da decisão mesmo quando nenhuma correção surge no período, impedindo que a exceção se torne uma aceitação de risco perpétua e esquecida.
* **Motivo**: obrigatório. É o registro auditável da decisão.

### Exemplo de arquivo

```text
# ==============================================================================
# dev-toolkit - Exceções de Vulnerabilidade (Trivy + OSV-Scanner)
# ==============================================================================
# Formato: ID1[,ID2,...] | DATA_DE_EXPIRACAO (YYYY-MM-DD) | motivo
# ==============================================================================
CVE-2026-47884,GHSA-j9f9-w8pj-32f8|2027-03-31|Fix requer Spring Boot 4; refactor programado para H2/2027
```

### Semântica garantida

* Vulnerabilidade coberta por exceção válida -> etapa aprovada, exibindo `N exceção(ões) aplicada(s)` no resumo.
* Vulnerabilidade **fora** de exceção -> reprovação, com relatório completo da ferramenta.
* Upgrade aplicado e vulnerabilidade que deixou de ser reportada -> exceção fica **órfã** e o resumo sinaliza `exceção(ões) órfã(s) - remova do arquivo`.
* Edição nos arquivos de exceção invalida o cache de Trivy/OSV na execução seguinte (digest incluído no hash de cache).

---

## Cache e Logs de Execução

* **Validação por Hashes**: As etapas geram assinaturas SHA-256 baseadas no conteúdo dos arquivos relevantes.
* **Expiração Determinística**: Scanners de vulnerabilidades (Trivy e OSV) invalidam o cache após **3 horas** (10800s). Para forçar a execução sem cache manualmente:

      DEV_TOOLKIT_NO_CACHE=1 dev verify

* **Relatório Consolidado**: Quando ocorre qualquer reprovação, uma seção destacada no rodapé exibe o log completo da ferramenta ofensora, preservando as cores ANSI e detalhando a causa raiz sem truncamento de tabelas.
