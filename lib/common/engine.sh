#!/usr/bin/env bash
# ==============================================================================
# engine.sh - Orquestrador Assíncrono com Propagação de Detalhes e Multi-Dependências
# ==============================================================================

declare -a _ENG_IDS=()
declare -a _ENG_DESCS=()
declare -a _ENG_FUNCS=()
declare -a _ENG_TOGGLES=()
declare -a _ENG_DEPS=()
declare -a _ENG_ACTIVE_INDICES=()

declare -A _ENG_STEP_NUM_MAP
declare -A _ENG_STEP_STATE
declare -A _ENG_STEP_PIDS
declare -A _ENG_STEP_LAST_SUBSTEP

_ENG_TMP_DIR="/tmp/toolkit_engine_$$"

engine_reset() {
    _ENG_IDS=()
    _ENG_DESCS=()
    _ENG_FUNCS=()
    _ENG_TOGGLES=()
    _ENG_DEPS=()
    _ENG_ACTIVE_INDICES=()

    for k in "${!_ENG_STEP_NUM_MAP[@]}"; do unset "_ENG_STEP_NUM_MAP[$k]"; done
    for k in "${!_ENG_STEP_STATE[@]}"; do unset "_ENG_STEP_STATE[$k]"; done
    for k in "${!_ENG_STEP_PIDS[@]}"; do unset "_ENG_STEP_PIDS[$k]"; done
    for k in "${!_ENG_STEP_LAST_SUBSTEP[@]}"; do unset "_ENG_STEP_LAST_SUBSTEP[$k]"; done

    rm -rf "$_ENG_TMP_DIR" 2>/dev/null || true
    mkdir -p "$_ENG_TMP_DIR"
}

engine_register() {
    local id="$1"
    local desc="$2"
    local func="$3"
    local toggle_var="$4"
    local depends_on="${5:-}"

    _ENG_IDS+=("$id")
    _ENG_DESCS+=("$desc")
    _ENG_FUNCS+=("$func")
    _ENG_TOGGLES+=("$toggle_var")
    _ENG_DEPS+=("$depends_on")
}

engine_is_enabled() {
    local toggle_var="$1"
    [[ -z "$toggle_var" ]] && return 0
    local val="${!toggle_var:-1}"
    [[ "$val" == "1" || "$val" == "true" || "$val" == "yes" ]]
}

_engine_check_deps() {
    local deps="$1"
    [[ -z "$deps" ]] && { printf 'ready'; return 0; }

    local d state failed=0 waiting=0
    for d in ${deps//,/ }; do
        state="${_ENG_STEP_STATE[$d]:-}"
        if [[ "$state" == "DONE_0" ]]; then
            continue
        elif [[ "$state" =~ ^DONE_[1-9] || "$state" == "SKIPPED_DEP" ]]; then
            failed=1
        elif [[ -z "$state" ]]; then
            continue
        else
            waiting=1
        fi
    done

    if [[ $failed -eq 1 ]]; then
        printf 'failed'
    elif [[ $waiting -eq 1 ]]; then
        printf 'waiting'
    else
        printf 'ready'
    fi
}

_engine_launch_step() {
    local id="$1"
    local label="$2"
    local desc="$3"
    local func="$4"
    local dep_info="$5"

    local out_file="${_ENG_TMP_DIR}/${id}.log"
    local meta_file="${_ENG_TMP_DIR}/${id}.meta"
    local substep_file="${_ENG_TMP_DIR}/${id}.substep"
    local detail_file="${_ENG_TMP_DIR}/${id}.detail"
    echo "" > "$substep_file"
    echo "" > "$detail_file"

    _ENG_STEP_STATE["$id"]="RUNNING"
    printf "${_C_BOLD}[%s] %s${_C_RESET}\n" "$label" "$desc"
    if [[ -n "$dep_info" ]]; then
        printf "  ${_C_INFO}↳ Dependência [%s] concluída. Iniciando execução...${_C_RESET}\n" "$dep_info"
    else
        printf "  ${_C_INFO}↳ Em execução em segundo plano...${_C_RESET}\n"
    fi

    (
        export _CURRENT_ENGINE_SUBSTEP_FILE="$substep_file"
        export _CURRENT_ENGINE_DETAIL_FILE="$detail_file"
        start_t=$(date +%s)
        "$func" "$label" "$desc" > "$out_file" 2>&1
        code=$?
        end_t=$(date +%s)
        duration=$((end_t - start_t))
        echo "${code}:${duration}" > "$meta_file"
    ) < /dev/null &
    _ENG_STEP_PIDS["$id"]=$!
}

engine_run() {
    local suite_title="$1"
    local total_registered=${#_ENG_IDS[@]}

    _ENG_ACTIVE_INDICES=()
    for ((i=0; i<total_registered; i++)); do
        local toggle="${_ENG_TOGGLES[$i]}"
        if engine_is_enabled "$toggle"; then
            _ENG_ACTIVE_INDICES+=("$i")
        else
            summary_add "${_ENG_DESCS[$i]}" "SKIP" "Desativado via Feature Toggle"
        fi
    done

    local total_active=${#_ENG_ACTIVE_INDICES[@]}
    if [[ $total_active -eq 0 ]]; then
        printf "${_C_YELLOW}[INFO] Nenhuma validação habilitada.${_C_RESET}\n"
        return 0
    fi

    local seq=1
    for idx in "${_ENG_ACTIVE_INDICES[@]}"; do
        local id="${_ENG_IDS[$idx]}"
        _ENG_STEP_NUM_MAP["$id"]="$seq"
        _ENG_STEP_STATE["$id"]="PENDING"
        _ENG_STEP_LAST_SUBSTEP["$id"]=""
        ((seq++))
    done

    printf "\n${_C_BCYAN}Iniciando execução assíncrona (%s etapas ativas)...${_C_RESET}\n\n" "$total_active"

    for idx in "${_ENG_ACTIVE_INDICES[@]}"; do
        local id="${_ENG_IDS[$idx]}"
        local desc="${_ENG_DESCS[$idx]}"
        local func="${_ENG_FUNCS[$idx]}"
        local dep="${_ENG_DEPS[$idx]}"
        local s_num="${_ENG_STEP_NUM_MAP[$id]}"
        local label="ETAPA ${s_num}/${total_active}"

        if [[ -z "$dep" ]]; then
            _engine_launch_step "$id" "$label" "$desc" "$func" ""
        else
            _ENG_STEP_STATE["$id"]="WAITING"
            printf "${_C_BOLD}[%s] %s${_C_RESET}\n" "$label" "$desc"
            printf "  ${_C_PURPLE}↳ Aguardando conclusão da dependência [%s]...${_C_RESET}\n" "$dep"
        fi
    done

    printf "\n"

    local pending_count=$total_active

    while [[ $pending_count -gt 0 ]]; do
        for idx in "${_ENG_ACTIVE_INDICES[@]}"; do
            local id="${_ENG_IDS[$idx]}"
            local desc="${_ENG_DESCS[$idx]}"
            local func="${_ENG_FUNCS[$idx]}"
            local dep="${_ENG_DEPS[$idx]}"
            local s_num="${_ENG_STEP_NUM_MAP[$id]}"
            local label="ETAPA ${s_num}/${total_active}"

            if [[ "${_ENG_STEP_STATE[$id]}" == "WAITING" ]]; then
                local dep_status
                dep_status="$(_engine_check_deps "$dep")"

                if [[ "$dep_status" == "ready" ]]; then
                    _engine_launch_step "$id" "$label" "$desc" "$func" "$dep"
                elif [[ "$dep_status" == "failed" ]]; then
                    _ENG_STEP_STATE["$id"]="SKIPPED_DEP"
                    log_step "$label" "$desc" "BLOCKED" "Dependência ($dep) falhou"
                    summary_add "$desc" "BLOCKED" "Dependência ($dep) falhou"
                    ((pending_count--))
                fi
            fi
        done

        for idx in "${_ENG_ACTIVE_INDICES[@]}"; do
            local id="${_ENG_IDS[$idx]}"
            if [[ "${_ENG_STEP_STATE[$id]}" == "RUNNING" ]]; then
                local s_num="${_ENG_STEP_NUM_MAP[$id]}"
                local label="ETAPA ${s_num}/${total_active}"
                local desc="${_ENG_DESCS[$idx]}"

                local substep_file="${_ENG_TMP_DIR}/${id}.substep"
                if [[ -s "$substep_file" ]]; then
                    local current_sub
                    current_sub=$(cat "$substep_file" 2>/dev/null)
                    if [[ -n "$current_sub" && "$current_sub" != "${_ENG_STEP_LAST_SUBSTEP[$id]}" ]]; then
                        _ENG_STEP_LAST_SUBSTEP["$id"]="$current_sub"
                        printf "  ${_C_DIM}[%s] ↳ %s...${_C_RESET}\n" "$label" "$current_sub"
                    fi
                fi

                local pid="${_ENG_STEP_PIDS[$id]}"
                if ! kill -0 "$pid" 2>/dev/null; then
                    wait "$pid" 2>/dev/null
                    local meta
                    meta=$(cat "${_ENG_TMP_DIR}/${id}.meta" 2>/dev/null || echo "1:0")
                    local exit_code="${meta%%:*}"
                    local duration="${meta##*:}"
                    _ENG_STEP_STATE["$id"]="DONE_${exit_code}"
                    ((pending_count--))

                    local detail
                    detail="$(cat "${_ENG_TMP_DIR}/${id}.detail" 2>/dev/null | tr -d '\r\n')"

                    if [[ "$exit_code" -eq 0 ]]; then
                        local step_det="${duration}s"
                        [[ -n "$detail" ]] && step_det="${detail}, ${duration}s"
                        log_step "$label" "$desc" "OK" "$step_det"
                        summary_add "$desc" "OK" "$detail" "" "$duration"
                    else
                        local fail_det="Detalhes abaixo"
                        [[ -n "$detail" ]] && fail_det="$detail"
                        log_step "$label" "$desc" "FAIL" "${fail_det}, ${duration}s"
                        summary_add "$desc" "FAIL" "$fail_det" "" "$duration"
                    fi
                fi
            fi
        done
        sleep 0.2
    done
}

engine_print_failures() {
    local has_failures=0
    for idx in "${_ENG_ACTIVE_INDICES[@]}"; do
        local id="${_ENG_IDS[$idx]}"
        if [[ "${_ENG_STEP_STATE[$id]:-}" =~ ^DONE_[1-9] ]]; then
            has_failures=1
            break
        fi
    done

    if [[ $has_failures -eq 1 ]]; then
        printf "${_C_RED}======================================================================${_C_RESET}\n"
        printf "${_C_RED}                 RELATÓRIO CONSOLIDADO DE FALHAS                      ${_C_RESET}\n"
        printf "${_C_RED}======================================================================${_C_RESET}\n"

        for idx in "${_ENG_ACTIVE_INDICES[@]}"; do
            local id="${_ENG_IDS[$idx]}"
            local desc="${_ENG_DESCS[$idx]}"
            local state="${_ENG_STEP_STATE[$id]:-}"
            local s_num="${_ENG_STEP_NUM_MAP[$id]:-0}"
            local log_path="${_ENG_TMP_DIR}/${id}.log"

            if [[ "$state" =~ ^DONE_[1-9] ]]; then
                local code="${state##DONE_}"
                printf "\n${_C_BYELLOW}[FALHA] ETAPA %s/%s: %s (Status: %s)${_C_RESET}\n" "$s_num" "${#_ENG_ACTIVE_INDICES[@]}" "$desc" "$code"
                printf '%s\n' "${_C_WHITE:-}----------------------------------------------------------------------${_C_RESET}"
                if [[ -s "$log_path" ]]; then
                    tr -d '\000-\010\013\014\016-\032\034-\037' < "$log_path"
                else
                    printf "  [Nenhuma saída registrada pelo comando]\n"
                fi
                printf '%s\n' "${_C_WHITE:-}----------------------------------------------------------------------${_C_RESET}"
            fi
        done
        printf "\n"
    fi

    rm -rf "$_ENG_TMP_DIR" 2>/dev/null || true
}
