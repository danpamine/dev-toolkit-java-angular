#!/usr/bin/env bash
# install-hooks.sh — Aplica core.hooksPath em repositórios Java e Angular
#
# Uso:
#   bash install-hooks.sh <diretório-raiz>          # aplica hooks
#   bash install-hooks.sh <diretório-raiz> --dry-run # simula
#   bash install-hooks.sh <diretório-raiz> --remove  # remove hooks

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TOOLKIT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HOOKS_DIR="${TOOLKIT_ROOT}/hooks"

if [[ -t 1 ]]; then
    C_INFO=$'\033[0;36m' C_OK=$'\033[0;32m' C_WARN=$'\033[0;33m' C_ERR=$'\033[0;31m' C_DIM=$'\033[2m' C_RESET=$'\033[0m'
else
    C_INFO="" C_OK="" C_WARN="" C_ERR="" C_DIM="" C_RESET=""
fi

ROOT_DIR="${1:-.}"
ACTION="apply"
if [[ "${2:-}" == "--remove" ]]; then
    ACTION="remove"
elif [[ "${2:-}" == "--dry-run" ]]; then
    ACTION="dry-run"
fi

ROOT_DIR="$(cd "$ROOT_DIR" && pwd)"

if [[ ! -d "$ROOT_DIR" ]]; then
    printf "${C_ERR}Erro: diretório '%s' não existe${C_RESET}\n" "$ROOT_DIR"
    exit 1
fi

if [[ "$ACTION" == "apply" && ! -d "$HOOKS_DIR" ]]; then
    printf "${C_ERR}Erro: diretório de hooks '%s' não existe${C_RESET}\n" "$HOOKS_DIR"
    exit 1
fi

printf "${C_INFO}==================================================${C_RESET}\n"
printf "${C_INFO}  Instalação de Git Hooks — dev-toolkit${C_RESET}\n"
printf "${C_INFO}==================================================${C_RESET}\n"
printf "  Toolkit: %s\n" "$TOOLKIT_ROOT"
printf "  Hooks:   %s\n" "$HOOKS_DIR"
printf "  Busca:   %s\n" "$ROOT_DIR"
printf "  Mode:    %s\n" "$([[ "$ACTION" == "dry-run" ]] && echo "DRY-RUN" || echo "$ACTION")"
printf '%s\n' "${C_INFO:-}--------------------------------------------------${C_RESET:-}"

printf "Buscando projetos Java (pom.xml) e Angular (angular.json)...\n\n"
found_repos=()

# Busca pom.xml
while IFS= read -r pom_file; do
    [[ -z "$pom_file" ]] && continue
    pom_dir="$(dirname "$pom_file")"
    repo_name="$(basename "$pom_dir")"
    if git -C "$pom_dir" rev-parse --git-dir > /dev/null 2>&1; then
        found_repos+=("$pom_dir")
        printf "  ${C_OK}[JAVA]${C_RESET} %-40s\n" "$repo_name"
    else
        printf "  ${C_DIM}[NO-GIT]${C_RESET} %-40s\n" "$repo_name"
    fi
done < <(find "$ROOT_DIR" -iname "pom.xml" -not -path "*/target/*" -not -path "*/node_modules/*" 2>/dev/null)

# Busca angular.json
while IFS= read -r ng_file; do
    [[ -z "$ng_file" ]] && continue
    ng_dir="$(dirname "$ng_file")"
    repo_name="$(basename "$ng_dir")"
    if git -C "$ng_dir" rev-parse --git-dir > /dev/null 2>&1; then
        already_found=false
        for r in "${found_repos[@]}"; do
            if [[ "$r" == "$ng_dir" ]]; then
                already_found=true
                break
            fi
        done
        if [[ "$already_found" == false ]]; then
            found_repos+=("$ng_dir")
            printf "  ${C_OK}[ANGULAR]${C_RESET} %-40s\n" "$repo_name"
        fi
    else
        printf "  ${C_DIM}[NO-GIT]${C_RESET} %-40s\n" "$repo_name"
    fi
done < <(find "$ROOT_DIR" -iname "angular.json" -not -path "*/node_modules/*" 2>/dev/null)

printf "\nEncontrados ${C_OK}%d${C_RESET} repositório(s) Git.\n\n" "${#found_repos[@]}"

if [[ ${#found_repos[@]} -eq 0 ]]; then
    printf "${C_WARN}Nenhum repositório com pom.xml ou angular.json encontrado.${C_RESET}\n"
    exit 0
fi

success_count=0
fail_count=0
skip_count=0

for repo_dir in "${found_repos[@]}"; do
    repo_name="$(basename "$repo_dir")"
    if [[ "$ACTION" == "dry-run" ]]; then
        printf "  ${C_DIM}[DRY]${C_RESET}  %-40s → %s\n" "$repo_name" "$HOOKS_DIR"
        ((skip_count++))
        continue
    fi
    if [[ "$ACTION" == "remove" ]]; then
        if git -C "$repo_dir" config --unset core.hooksPath > /dev/null 2>&1; then
            printf "  ${C_OK}[OK]${C_RESET}  %-40s → removido\n" "$repo_name"
            ((success_count++))
        else
            printf "  ${C_DIM}[N/A]${C_RESET} %-40s (sem hooksPath)\n" "$repo_name"
            ((skip_count++))
        fi
        continue
    fi
    # apply
    current_path="$(git -C "$repo_dir" config core.hooksPath 2>/dev/null || echo "")"
    if [[ "$current_path" == "$HOOKS_DIR" ]]; then
        printf "  ${C_DIM}[N/A]${C_RESET} %-40s já configurado\n" "$repo_name"
        ((skip_count++))
        continue
    fi
    if git -C "$repo_dir" config core.hooksPath "$HOOKS_DIR" 2>/dev/null; then
        chmod +x "$HOOKS_DIR/pre-commit" "$HOOKS_DIR/pre-push" "$HOOKS_DIR/post-merge" 2>/dev/null
        chmod +x "$HOOKS_DIR/java/pre-commit" "$HOOKS_DIR/java/pre-push" "$HOOKS_DIR/java/verify" 2>/dev/null
        chmod +x "$HOOKS_DIR/angular/pre-commit" "$HOOKS_DIR/angular/pre-push" "$HOOKS_DIR/angular/verify" 2>/dev/null
        printf "  ${C_OK}[OK]${C_RESET}  %-40s → %s\n" "$repo_name" "$HOOKS_DIR"
        ((success_count++))
    else
        printf "  ${C_ERR}[ERR]${C_RESET} %-40s (git config falhou)\n" "$repo_name"
        ((fail_count++))
    fi
done

printf "\n${C_INFO}==================================================${C_RESET}\n"
if [[ "$ACTION" == "apply" ]]; then
    printf "  Aplicado: ${C_OK}%d${C_RESET}  Pulado: ${C_DIM}%d${C_RESET}  Falha: ${C_ERR}%d${C_RESET}\n" "$success_count" "$skip_count" "$fail_count"
elif [[ "$ACTION" == "dry-run" ]]; then
    printf "  Simulação: ${C_DIM}%d repositório(s) seriam configurados${C_RESET}\n" "$skip_count"
else
    printf "  Removido: ${C_OK}%d${C_RESET}  Sem config: ${C_DIM}%d${C_RESET}\n" "$success_count" "$skip_count"
fi
printf "${C_INFO}==================================================${C_RESET}\n"
exit 0
