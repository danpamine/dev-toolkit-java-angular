#!/usr/bin/env bash
# ==============================================================================
# vuln-exceptions.sh - Exceções Corporativas de Vulnerabilidade (Unificada)
# ==============================================================================

declare -a _VX_GROUPS=()
declare -a _VX_EXPIRY=()
declare -a _VX_REASON=()

_VX_APPLIED=0
_VX_ORPHAN=0
_VX_UNEXCEPTED=0
_VX_EXPIRED_NOTE=""

_vuln_exceptions_files() {
    local root="${TOOLKIT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
    local files=()
    [[ -f "$root/env/vuln-exceptions/global.list" ]] && files+=("$root/env/vuln-exceptions/global.list")
    [[ -n "${REPO_NAME:-}" && -f "$root/env/vuln-exceptions/${REPO_NAME}.list" ]] && files+=("$root/env/vuln-exceptions/${REPO_NAME}.list")
    if [[ ${#files[@]} -gt 0 ]]; then
        printf '%s\n' "${files[@]}"
    fi
}

vuln_exceptions_load() {
    _VX_GROUPS=()
    _VX_EXPIRY=()
    _VX_REASON=()
    _VX_APPLIED=0
    _VX_ORPHAN=0
    _VX_UNEXCEPTED=0
    _VX_EXPIRED_NOTE=""

    local f line ids expiry reason
    while IFS= read -r f; do
        [[ -n "$f" ]] || continue
        while IFS= read -r line; do
            line="${line//$'\r'/}"
            line="$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
            [[ -z "$line" || "$line" == \#* ]] && continue
            IFS='|' read -r ids expiry reason <<< "$line"
            ids="$(echo "$ids" | tr -d '[:space:]')"
            expiry="$(echo "$expiry" | tr -d '[:space:]')"
            reason="$(echo "$reason" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
            [[ -z "$ids" || -z "$expiry" ]] && continue
            _VX_GROUPS+=("$ids")
            _VX_EXPIRY+=("$expiry")
            _VX_REASON+=("$reason")
        done < "$f"
    done < <(_vuln_exceptions_files)
}

vuln_exceptions_group_status() {
    local idx="$1"
    local today
    today="$(date +%F)"
    if [[ "${_VX_EXPIRY[$idx]}" < "$today" ]]; then
        printf 'expired'
    else
        printf 'valid'
    fi
}

vuln_exceptions_valid_ids() {
    local i ids id
    for i in "${!_VX_GROUPS[@]}"; do
        [[ "$(vuln_exceptions_group_status "$i")" == "valid" ]] || continue
        IFS=',' read -ra ids <<< "${_VX_GROUPS[$i]}"
        for id in "${ids[@]}"; do
            [[ -n "$id" ]] && printf '%s\n' "$id"
        done
    done
    return 0
}

vuln_exceptions_expired_summary() {
    local i n=0
    for i in "${!_VX_GROUPS[@]}"; do
        [[ "$(vuln_exceptions_group_status "$i")" == "expired" ]] && ((n++))
    done
    if [[ $n -gt 0 ]]; then
        printf '%d exceção(ões) expirada(s) — reavalie ou renove' "$n"
    fi
    return 0
}

# stdin/arg: IDs reportados (um por linha).
# Seta _VX_APPLIED / _VX_ORPHAN / _VX_UNEXCEPTED e imprime "applied orphan unexcepted".
vuln_exceptions_classify() {
    local reported="${1:-}"
    local i ids id hit
    local all_group_ids=""

    _VX_APPLIED=0
    _VX_ORPHAN=0
    _VX_UNEXCEPTED=0

    for i in "${!_VX_GROUPS[@]}"; do
        [[ "$(vuln_exceptions_group_status "$i")" == "valid" ]] || continue
        IFS=',' read -ra ids <<< "${_VX_GROUPS[$i]}"
        hit=0
        for id in "${ids[@]}"; do
            [[ -z "$id" ]] && continue
            all_group_ids="$all_group_ids $id"
            if printf '%s\n' "$reported" | grep -qxF "$id"; then
                hit=1
            fi
        done
        if [[ $hit -eq 1 ]]; then
            _VX_APPLIED=$((_VX_APPLIED + 1))
        else
            _VX_ORPHAN=$((_VX_ORPHAN + 1))
        fi
    done

    local r
    while IFS= read -r r; do
        [[ -z "$r" ]] && continue
        if ! printf '%s\n' $all_group_ids | grep -qxF "$r"; then
            _VX_UNEXCEPTED=$((_VX_UNEXCEPTED + 1))
        fi
    done <<< "$reported"

    printf '%d %d %d' "$_VX_APPLIED" "$_VX_ORPHAN" "$_VX_UNEXCEPTED"
    return 0
}

vuln_exceptions_digest() {
    local files="" f
    while IFS= read -r f; do
        [[ -n "$f" ]] && files="$files $f"
    done < <(_vuln_exceptions_files)
    if [[ -z "${files// }" ]]; then
        printf 'none'
        return 0
    fi
    (sha256sum $files 2>/dev/null) | sha256sum | awk '{print $1}'
}
