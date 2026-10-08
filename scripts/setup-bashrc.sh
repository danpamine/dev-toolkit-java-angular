#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLKIT_HOME="$(dirname "$SCRIPT_DIR")"
TOOLKIT_PATH=$(cygpath -u "$TOOLKIT_HOME" 2>/dev/null || echo "$TOOLKIT_HOME")
BASHRC="${HOME}/.bashrc"
MARKER="# >>> dev-toolkit >>>"
END_MARKER="# <<< dev-toolkit <<<"

GITIGNORE_GLOBAL="${HOME}/.gitignore_global"
touch "$GITIGNORE_GLOBAL"
for pattern in "pnpm-lock.yaml" "pnpm-workspace.yaml" "pnpm-*.yaml" "pnpm-debug.log*" ".pnpm-store" ".pnpm-node-linker" ".env.local" ".env.user"; do
    if ! grep -qxF "$pattern" "$GITIGNORE_GLOBAL" 2>/dev/null; then
        echo "$pattern" >> "$GITIGNORE_GLOBAL"
    fi
done
git config --global core.excludesfile "$GITIGNORE_GLOBAL" 2>/dev/null || true

echo ""
echo "  Setup: dev() no .bashrc"
echo ""

if grep -q "$MARKER" "$BASHRC" 2>/dev/null; then
    sed -i "/$MARKER/,/$END_MARKER/d" "$BASHRC"
fi

if grep -q '^dev() {' "$BASHRC" 2>/dev/null; then
    awk '
        /^dev\(\) \{/ { in_dev = 1; next }
        in_dev && /^\}/ { in_dev = 0; next }
        in_dev { next }
        { print }
    ' "$BASHRC" > "${BASHRC}.tmp" && mv "${BASHRC}.tmp" "$BASHRC"
fi

cat >> "$BASHRC" << 'BASHRC_EOF'
# >>> dev-toolkit >>>
export DEV_TOOLKIT_HOME="__TOOLKIT_PATH__"
export PATH="$DEV_TOOLKIT_HOME/bin:$PATH"
dev() {
    if [ -z "$DEV_TOOLKIT_HOME" ]; then
        echo "[ERRO] DEV_TOOLKIT_HOME não definido. Execute setup-bashrc.sh."
        return 1
    fi
    case "${1:-help}" in
        init|setup)
            bash "$DEV_TOOLKIT_HOME/scripts/setup-interactive.sh"
            ;;
        install)
            if [ -f "$DEV_TOOLKIT_HOME/lib/common/env.sh" ]; then
                TOOLKIT_ROOT="$DEV_TOOLKIT_HOME"
                source "$DEV_TOOLKIT_HOME/lib/common/env.sh"
                env_load
            fi
            if [ -f "pom.xml" ]; then
                echo "[INFO] Java: mvn install"
                mvn install -DskipTests
            elif [ -f "angular.json" ]; then
                local npmrc_path="$DEV_TOOLKIT_HOME/config/angular/.npmrc"
                local store_path="${DEV_TOOLKIT_STORE_DIR:-$DEV_TOOLKIT_HOME/dependencies/pnpm-store}"
                local toolkit_workspace="$DEV_TOOLKIT_HOME/config/angular/pnpm-workspace.yaml"
                export NPM_CONFIG_USERCONFIG="$npmrc_path"
                export pnpm_config_userconfig="$npmrc_path"
                export pnpm_config_store_dir="$store_path"
                if command -v pnpm &>/dev/null; then
                    echo "[INFO] Angular: pnpm install (store: $store_path)"
                    local _pw_cleanup=false
                    if [[ -f "pnpm-workspace.yaml" ]]; then
                        if grep -q "set this to" "pnpm-workspace.yaml" 2>/dev/null; then
                            rm -f "pnpm-workspace.yaml"
                        fi
                    fi
                    if [[ ! -f "pnpm-workspace.yaml" ]] && [[ -f "$toolkit_workspace" ]]; then
                        cp "$toolkit_workspace" "pnpm-workspace.yaml"
                        _pw_cleanup=true
                    fi
                    pnpm install
                    local _pnpm_exit=$?
                    if [[ "$_pw_cleanup" == true ]] && [[ -f "pnpm-workspace.yaml" ]]; then
                        rm -f "pnpm-workspace.yaml"
                    fi
                    return $_pnpm_exit
                else
                    echo "[INFO] Angular: npm install"
                    npm install
                fi
            else
                echo "[ERRO] Tipo de projeto não reconhecido"
                return 1
            fi
            ;;
        run)
            if [ -f "$DEV_TOOLKIT_HOME/lib/common/env.sh" ]; then
                TOOLKIT_ROOT="$DEV_TOOLKIT_HOME"
                source "$DEV_TOOLKIT_HOME/lib/common/env.sh"
                env_load
            fi
            if [ -f "pom.xml" ]; then
                echo "[INFO] Java: Executando Spring Boot com suporte a ENVs..."
                local active_profile="${SPRING_PROFILES_ACTIVE:-${PROFILE:-local}}"
                local jvm_args="${JAVA_OPTS:-}${JVM_FLAGS:+ $JVM_FLAGS}"
                jvm_args="-Dspring.profiles.active=${active_profile} ${jvm_args}"
                mvn spring-boot:run -Dspring-boot.run.jvmArguments="$jvm_args"
            elif [ -f "angular.json" ]; then
                echo "[INFO] Angular: Executando servidor..."
                local ng_port="${PORT:-4200}"
                local ng_host="${HOST:-localhost}"
                local ng_extra="${NG_ARGS:-}"
                if command -v pnpm &>/dev/null; then
                    pnpm start --port "$ng_port" --host "$ng_host" $ng_extra
                else
                    npm start -- --port "$ng_port" --host "$ng_host" $ng_extra
                fi
            else
                echo "[ERRO] Tipo de projeto não reconhecido"
                return 1
            fi
            ;;
        test)
            if [ -f "$DEV_TOOLKIT_HOME/lib/common/commands.sh" ]; then
                source "$DEV_TOOLKIT_HOME/lib/common/commands.sh"
            fi
            if [ -f "pom.xml" ]; then
                echo "[INFO] Java: mvn test"
                run_java_verify
            elif [ -f "angular.json" ]; then
                echo "[INFO] Angular: Executando testes unitários..."
                run_angular_test
            else
                echo "[ERRO] Tipo de projeto não reconhecido"
                return 1
            fi
            ;;
        lint)
            if [ -f "pom.xml" ]; then
                bash "$DEV_TOOLKIT_HOME/hooks/java/pre-commit"
            elif [ -f "angular.json" ]; then
                bash "$DEV_TOOLKIT_HOME/hooks/angular/pre-commit"
            else
                echo "[ERRO] Tipo de projeto não reconhecido"
                return 1
            fi
            ;;
        format)
            if [ -f "pom.xml" ]; then
                echo "[INFO] Java: Google Java Format"
                local gjf_jar="$HOME/.local/bin/google-java-format.jar"
                if [ -f "$gjf_jar" ]; then
                    find src -name "*.java" -exec java -jar "$gjf_jar" --replace {} +
                else
                    echo "[ERRO] google-java-format.jar não encontrado"
                    return 1
                fi
            elif [ -f "angular.json" ]; then
                echo "[INFO] Angular: Prettier"
                local prettier_cfg="$DEV_TOOLKIT_HOME/config/angular/.prettierrc.json"
                npx --yes prettier --write --config "$prettier_cfg" "src/**/*.{ts,js,html,scss,css}"
            else
                echo "[ERRO] Tipo de projeto não reconhecido"
                return 1
            fi
            ;;
        build)
            if [ -f "$DEV_TOOLKIT_HOME/lib/common/commands.sh" ]; then
                source "$DEV_TOOLKIT_HOME/lib/common/commands.sh"
            fi
            if [ -f "pom.xml" ]; then
                echo "[INFO] Java: Compilação do projeto"
                run_java_build
            elif [ -f "angular.json" ]; then
                echo "[INFO] Angular: ng build"
                run_angular_build
            else
                echo "[ERRO] Tipo de projeto não reconhecido"
                return 1
            fi
            ;;
        verify|validate)
            if [ -f "pom.xml" ]; then
                bash "$DEV_TOOLKIT_HOME/hooks/java/verify"
            elif [ -f "angular.json" ]; then
                bash "$DEV_TOOLKIT_HOME/hooks/angular/verify"
            else
                echo "[ERRO] Tipo de projeto não reconhecido"
                return 1
            fi
            ;;
        base)
            if [ -z "${2:-}" ]; then
                echo "Branch base atual: ${BASE_BRANCH:-develop}"
                echo "Uso: dev base <nome-da-branch> (ex: dev base develop)"
                return 0
            fi
            export BASE_BRANCH="$2"
            echo "BASE_BRANCH=$2" > ".env.local"
            echo "[OK] Branch base definida: $2 (salvo em .env.local)"
            ;;
        hooks-install)
            bash "$DEV_TOOLKIT_HOME/scripts/install-hooks.sh" "${2:-.}"
            ;;
        hooks-remove)
            bash "$DEV_TOOLKIT_HOME/scripts/install-hooks.sh" "${2:-.}" --remove
            ;;
        clean)
            find "${DEV_TOOLKIT_CACHE_DIR:-/tmp/cicd_cache}" -mindepth 1 -maxdepth 1 ! -name osv-db -exec rm -rf {} + 2>/dev/null || true
            echo "[OK] Cache de validações limpo (base local do OSV preservada)"
            ;;
        setup-node)
            bash "$DEV_TOOLKIT_HOME/scripts/setup-node.sh"
            ;;
        help|*)
            echo "dev-toolkit — Comandos disponíveis:"
            echo ""
            echo "  dev init           Assistente interativo de configuração"
            echo "  dev verify         Validação completa e assíncrona do projeto"
            echo "  dev base <branch>  Altera a branch base de comparação (ex: dev base develop)"
            echo "  dev install        Instala dependências (mvn install | pnpm install)"
            echo "  dev run            Executa a aplicação com ENVs (mvn | pnpm start)"
            echo "  dev test           Executa testes (mvn test | npm/pnpm test)"
            echo "  dev lint           Executa linting (pre-commit hook)"
            echo "  dev format         Formata código (google-java-format | prettier)"
            echo "  dev build          Compila o projeto (mvn package | ng build)"
            echo "  dev hooks-install  Instala Git Hooks nos repositórios"
            echo "  dev hooks-remove   Remove Git Hooks"
            echo "  dev clean          Limpa cache local (preserva a base local do OSV)"
            echo "  dev setup-node     Instala NVS + Node.js LTS + pnpm"
            ;;
    esac
}
# <<< dev-toolkit <<<
BASHRC_EOF

sed -i "s|__TOOLKIT_PATH__|$TOOLKIT_PATH|g" "$BASHRC"

echo "[OK] Configuração adicionada a $BASHRC"
echo "[OK] Git ignore global configurado em $GITIGNORE_GLOBAL"
echo ""
echo "Toolkit path: $TOOLKIT_PATH"
echo ""
echo "Reinicie o terminal ou execute: source ~/.bashrc"
