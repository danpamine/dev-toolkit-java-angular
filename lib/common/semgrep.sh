#!/usr/bin/env bash
# ==============================================================================
# semgrep.sh - SAST Semântico com Reparo de Runtime do Python
# ==============================================================================

_SEMGREP_PY_FAIL_PATTERNS='Traceback|ModuleNotFoundError|ImportError|Fatal Python error|unsupported Python|incompatible with this Python'

_semgrep_is_portable() {
    local py_dir="${DEV_TOOLKIT_PYTHON_DIR:-${TOOLKIT_ROOT}/dependencies/python}"
    [[ "$1" == "${py_dir}/"* ]]
}

step_semgrep_sast() {
    local label="$1"
    local desc="$2"
    local py_dir="${DEV_TOOLKIT_PYTHON_DIR:-${TOOLKIT_ROOT}/dependencies/python}"
    local semgrep_bin=""

    if [[ -f "${py_dir}/Scripts/semgrep.exe" ]]; then
        semgrep_bin="${py_dir}/Scripts/semgrep.exe"
    elif command -v semgrep &>/dev/null; then
        semgrep_bin="semgrep"
    fi

    if [[ -z "$semgrep_bin" ]] || ! "$semgrep_bin" --version &>/dev/null; then
        log_step "$label" "$desc" "PULADO" "Semgrep não disponível"
        summary_add "$desc" "SKIP" "Semgrep ausente ou bloqueado na rede"
        return 0
    fi

    local changed_files=()
    while IFS= read -r f; do
        [[ -n "$f" && -f "$f" ]] && changed_files+=("$f")
    done < <(git_diff_target_files "*.java" "*.ts" "*.js" 2>/dev/null)

    if [[ ${#changed_files[@]} -eq 0 ]]; then
        log_step "$label" "$desc" "OK" "Nenhum arquivo relevante alterado"
        summary_add "$desc" "OK" "Sem alterações"
        return 0
    fi

    log_step_header "$label" "$desc"
    log_substep "Analisando ${#changed_files[@]} arquivo(s) modificado(s)" \
        "$semgrep_bin" scan --config auto --error --quiet "${changed_files[@]}"
    local exit_code=$?

    if [[ $exit_code -ne 0 ]] && [[ "$_LOG_LAST_OUTPUT" =~ $_SEMGREP_PY_FAIL_PATTERNS ]] && _semgrep_is_portable "$semgrep_bin"; then
        bootstrap_python_repair
        if _semgrep_works; then
            log_substep "Reexecutando análise após reparo do Python" \
                "$semgrep_bin" scan --config auto --error --quiet "${changed_files[@]}"
            exit_code=$?
        fi
    fi

    if [[ $exit_code -eq 0 ]]; then
        log_step "$label" "$desc" "OK" "${#changed_files[@]} arquivo(s)"
        summary_add "$desc" "OK" "${#changed_files[@]} arquivo(s)"
    else
        log_step "$label" "$desc" "FAIL"
        summary_add "$desc" "FAIL" "Vulnerabilidades semânticas detectadas pelo Semgrep"
        log_show_last
    fi
    return $exit_code
}
