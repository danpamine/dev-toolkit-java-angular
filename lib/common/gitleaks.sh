#!/usr/bin/env bash
# ==============================================================================
# gitleaks.sh - Varredura de Segredos com Gitleaks (Staged, Pull e Full Codebase)
# ==============================================================================

_gitleaks_bin() {
    local bin="gitleaks"
    [[ -f "$LOCAL_BIN/gitleaks.exe" ]] && bin="$LOCAL_BIN/gitleaks.exe"
    printf '%s' "$bin"
}

_gitleaks_pulado_ausente() {
    local label="$1"
    local desc="$2"
    log_step "$label" "$desc" "PULADO" "Gitleaks ausente"
    summary_add "$desc" "SKIP" "Gitleaks não instalado"
}

_gitleaks_pull_scope() {
    if ! git rev-parse --verify -q ORIG_HEAD >/dev/null 2>&1; then
        printf 'full'
        return 0
    fi
    local orig head
    orig="$(git rev-parse ORIG_HEAD 2>/dev/null)"
    head="$(git rev-parse HEAD 2>/dev/null)"
    if [[ -z "$orig" || -z "$head" ]]; then
        printf 'full'
    elif [[ "$orig" == "$head" ]]; then
        printf 'empty'
    else
        printf 'range'
    fi
}

_gitleaks_run_dir_scan() {
    local label="$1"
    local desc="$2"
    local gitleaks_bin
    gitleaks_bin="$(_gitleaks_bin)"

    log_step_header "$label" "$desc"
    log_substep "Varrendo código da aplicação (Filesystem Scan)" "$gitleaks_bin" dir . --verbose
    local exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
        log_step "$label" "$desc" "OK"
        summary_add "$desc" "OK"
    else
        log_step "$label" "$desc" "FAIL"
        summary_add "$desc" "FAIL" "Credenciais ativas encontradas no código da aplicação"
        log_show_last
    fi
    return $exit_code
}

step_gitleaks_commit() {
    local label="$1"
    local desc="$2"
    local gitleaks_bin
    gitleaks_bin="$(_gitleaks_bin)"

    if ! command -v "$gitleaks_bin" &>/dev/null; then
        _gitleaks_pulado_ausente "$label" "$desc"
        return 0
    fi

    local hash
    hash="$(git diff --cached 2>/dev/null | sha256sum | awk '{print $1}')"
    [[ -z "$hash" ]] && hash="$(git rev-parse HEAD 2>/dev/null | sha256sum | awk '{print $1}')"

    if cache_is_valid "gitleaks" "$hash"; then
        log_step "$label" "$desc" "OK" "Cache"
        summary_add "$desc" "OK" "Cache"
        return 0
    fi

    log_step_header "$label" "$desc"
    log_substep "Analisando credenciais staged" "$gitleaks_bin" git --pre-commit --verbose
    local exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
        cache_save "gitleaks" "$hash"
        log_step "$label" "$desc" "OK"
        summary_add "$desc" "OK"
    else
        log_step "$label" "$desc" "FAIL"
        summary_add "$desc" "FAIL" "Remova credenciais expostas identificadas pelo Gitleaks"
        log_show_last
    fi
    return $exit_code
}

step_gitleaks_full() {
    local label="$1"
    local desc="$2"
    local gitleaks_bin
    gitleaks_bin="$(_gitleaks_bin)"

    if ! command -v "$gitleaks_bin" &>/dev/null; then
        _gitleaks_pulado_ausente "$label" "$desc"
        return 0
    fi

    _gitleaks_run_dir_scan "$label" "$desc"
}

step_gitleaks_pull() {
    local label="$1"
    local desc="$2"
    local gitleaks_bin
    gitleaks_bin="$(_gitleaks_bin)"

    if ! command -v "$gitleaks_bin" &>/dev/null; then
        _gitleaks_pulado_ausente "$label" "$desc"
        return 0
    fi

    local scope
    scope="$(_gitleaks_pull_scope)"

    local hash
    if [[ "$scope" == "full" ]]; then
        hash="$(git rev-parse HEAD 2>/dev/null | sha256sum | awk '{print $1}')"
    else
        hash="$((git rev-parse ORIG_HEAD 2>/dev/null; git rev-parse HEAD 2>/dev/null) | sha256sum | awk '{print $1}')"
    fi

    if cache_is_valid "gitleaks-pull" "$hash"; then
        log_step "$label" "$desc" "OK" "Cache"
        summary_add "$desc" "OK" "Cache"
        return 0
    fi

    if [[ "$scope" == "empty" ]]; then
        cache_save "gitleaks-pull" "$hash"
        log_step "$label" "$desc" "OK" "Nenhuma alteração recebida"
        summary_add "$desc" "OK" "Nenhuma alteração recebida"
        return 0
    fi

    if [[ "$scope" == "full" ]]; then
        _gitleaks_run_dir_scan "$label" "$desc"
        local fallback_code=$?
        [[ $fallback_code -eq 0 ]] && cache_save "gitleaks-pull" "$hash"
        return $fallback_code
    fi

    log_step_header "$label" "$desc"
    log_substep "Varrendo alterações recebidas (ORIG_HEAD..HEAD)" "$gitleaks_bin" git --log-opts="ORIG_HEAD..HEAD" --verbose
    local exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
        cache_save "gitleaks-pull" "$hash"
        log_step "$label" "$desc" "OK"
        summary_add "$desc" "OK"
    else
        log_step "$label" "$desc" "FAIL"
        summary_add "$desc" "FAIL" "Segredos detectados nas alterações recebidas pelo pull"
        log_show_last
    fi
    return $exit_code
}
