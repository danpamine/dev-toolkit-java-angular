#!/usr/bin/env bash
# =============================================================================
# env.sh — Carregamento Hierárquico e Dinâmico de Variáveis do Toolkit
# =============================================================================

_TOOLKIT_ROOT="${TOOLKIT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"

# -----------------------------------------------------------------------------
# env_load
# Carrega as variáveis globais da tecnologia e sobrescreve com as variáveis
# específicas do projeto se o arquivo env/<tech>/<REPO_NAME>.env existir.
# -----------------------------------------------------------------------------
env_load() {
    local repo_dir="$(pwd)"
    local repo_name="$(basename "$repo_dir")"

    local tech=""
    if [[ -f "$repo_dir/pom.xml" ]]; then
        tech="java"
    elif [[ -f "$repo_dir/angular.json" ]]; then
        tech="angular"
    fi

    # Ativa a exportação automática de todas as variáveis lidas a partir daqui
    set -a

    # 1. Carrega preferências globais do usuário
    [[ -f "${_TOOLKIT_ROOT}/env/.env.user" ]] && . "${_TOOLKIT_ROOT}/env/.env.user"

    # 2. Carrega variáveis da tecnologia e do repositório específico
    if [[ -n "$tech" ]]; then
        [[ -f "${_TOOLKIT_ROOT}/env/${tech}/global.env" ]] && . "${_TOOLKIT_ROOT}/env/${tech}/global.env"
        [[ -f "${_TOOLKIT_ROOT}/env/${tech}/.env.user" ]] && . "${_TOOLKIT_ROOT}/env/${tech}/.env.user"
        [[ -f "${_TOOLKIT_ROOT}/env/${tech}/${repo_name}.env" ]] && . "${_TOOLKIT_ROOT}/env/${tech}/${repo_name}.env"
    fi

    # 3. Overrides locais do repositório atual
    [[ -f "$repo_dir/.env.local" ]] && . "$repo_dir/.env.local"

    # Desativa a exportação automática
    set +a

    # Garante o diretório de binários no PATH
    export LOCAL_BIN="${LOCAL_BIN:-$HOME/.local/bin}"
    export PATH="$LOCAL_BIN:$PATH"
}
