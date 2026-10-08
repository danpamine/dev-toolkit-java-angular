#!/usr/bin/env bash
# ==============================================================================
# osv-scanner.sh - SCA Rápido via Google OSV Database com Fallback Offline e Exceções
# ==============================================================================

if ! declare -f vuln_exceptions_load &>/dev/null; then
    _SCRIPT_D="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    _TK_R="${TOOLKIT_ROOT:-$(cd "$_SCRIPT_D/../.." && pwd)}"
    if [[ -f "$_TK_R/lib/common/vuln-exceptions.sh" ]]; then
        source "$_TK_R/lib/common/vuln-exceptions.sh"
    fi
fi

_OSV_NETWORK_PATTERNS='dial tcp|connection refused|i/o timeout|context deadline|no such host|network is unreachable|proxyconnect|proxy error|tls:|x509|unable to query|failed to query|failed to connect'

_osv_classify_output() {
    local output="$1"
    if echo "$output" | grep -qE "Total [1-9][0-9]* packages? affected"; then
        printf 'FAIL'
    elif echo "$output" | grep -q "Total 0 packages affected"; then
        printf 'OK'
    elif echo "$output" | grep -q "0 known vulnerabilities"; then
        printf 'OK'
    elif echo "$output" | grep -qiE "$_OSV_NETWORK_PATTERNS"; then
        printf 'SKIP'
    else
        printf 'FAIL'
    fi
}

_osv_extract_ids() {
    printf '%s' "$1" | grep -oE 'https://osv\.dev/[A-Za-z0-9._-]+' | sed 's|https://osv.dev/||' | sort -u
}

# Classifica o veredito bruto aplicando as exceções corporativas.
# Seta _VX_APPLIED/_VX_ORPHAN/_VX_UNEXCEPTED/_VX_EXPIRED_NOTE e imprime o veredito final.
_osv_apply_exceptions() {
    local verdict="$1"

    if [[ "$verdict" != "FAIL" && "$verdict" != "OK" ]]; then
        _VX_APPLIED=0
        _VX_ORPHAN=0
        _VX_UNEXCEPTED=0
        _VX_EXPIRED_NOTE=""
        printf '%s' "$verdict"
        return 0
    fi

    vuln_exceptions_load
    local ids
    ids="$(_osv_extract_ids "$_LOG_LAST_OUTPUT")"
    read -r _VX_APPLIED _VX_ORPHAN _VX_UNEXCEPTED <<< "$(vuln_exceptions_classify "$ids")"
    _VX_EXPIRED_NOTE="$(vuln_exceptions_expired_summary)"

    if [[ "$verdict" == "FAIL" && "$_VX_UNEXCEPTED" -eq 0 && "$_VX_APPLIED" -gt 0 ]]; then
        printf 'OK'
    else
        printf '%s' "$verdict"
    fi
}

_osv_exceptions_detail() {
    local parts=""
    [[ "${_VX_APPLIED:-0}" -gt 0 ]] && parts="${_VX_APPLIED} exceção(ões) aplicada(s)"
    [[ "${_VX_UNEXCEPTED:-0}" -gt 0 ]] && parts="${parts:+$parts; }${_VX_UNEXCEPTED} vulnerabilidade(s) fora de exceção"
    [[ "${_VX_ORPHAN:-0}" -gt 0 ]] && parts="${parts:+$parts; }${_VX_ORPHAN} exceção(ões) órfã(s) — remova do arquivo"
    [[ -n "${_VX_EXPIRED_NOTE:-}" ]] && parts="${parts:+$parts; }${_VX_EXPIRED_NOTE}"
    printf '%s' "$parts"
}

_osv_offline_db_dir() {
    local cache_base="${DEV_TOOLKIT_CACHE_DIR:-/tmp/cicd_cache}"
    cache_base="${cache_base%$'\r'}"
    printf '%s/osv-db' "$cache_base"
}

_osv_offline_db_ready() {
    local db_dir
    db_dir="$(_osv_offline_db_dir)"
    [[ -d "$db_dir/osv-scanner" ]]
}

_osv_fallback_enabled() {
    local verdict="$1"
    [[ "$verdict" == "SKIP" ]] && _osv_offline_db_ready
}

_osv_run_scan() {
    local bin="$1"
    shift
    log_substep "Varrendo dependências OSV" "$bin" scan "$@"
}

_osv_settle() {
    local label="$1"
    local desc="$2"
    local hash="$3"
    local mode_note="$4"

    local verdict
    verdict="$(_osv_classify_output "$_LOG_LAST_OUTPUT")"
    verdict="$(_osv_apply_exceptions "$verdict")"

    local detail
    detail="$(_osv_exceptions_detail)"
    [[ -n "$mode_note" ]] && detail="${detail:+$detail; }$mode_note"

    case "$verdict" in
        OK)
            cache_save "osv-scanner" "$hash"
            log_step "$label" "$desc" "OK" "$detail"
            summary_add "$desc" "OK" "$detail"
            return 0
            ;;
        SKIP)
            log_step "$label" "$desc" "PULADO" "Rede corporativa indisponível para consulta OSV"
            summary_add "$desc" "SKIP" "Rede corporativa indisponível para consulta OSV"
            return 0
            ;;
        *)
            log_step "$label" "$desc" "FAIL"
            summary_add "$desc" "FAIL" "${detail:-Vulnerabilidades identificadas pelo OSV-Scanner}"
            log_show_last
            return 1
            ;;
    esac
}

step_osv_scanner() {
    local label="$1"
    local desc="$2"
    local bin="osv-scanner"
    [[ -f "$LOCAL_BIN/osv-scanner.exe" ]] && bin="$LOCAL_BIN/osv-scanner.exe"

    if ! command -v "$bin" &>/dev/null; then
        log_step "$label" "$desc" "PULADO" "osv-scanner não instalado"
        summary_add "$desc" "SKIP" "osv-scanner não instalado"
        return 0
    fi

    local target_file=""
    local scan_flag=""
    if [[ -f "target/bom.json" ]]; then
        target_file="target/bom.json"
        scan_flag="--sbom"
    elif [[ -f "pom.xml" ]]; then
        target_file="pom.xml"
        scan_flag="--lockfile"
    elif [[ -f "package-lock.json" ]]; then
        target_file="package-lock.json"
        scan_flag="--lockfile"
    fi
    if [[ -z "$target_file" ]]; then
        log_step "$label" "$desc" "OK" "Sem manifesto compatível"
        summary_add "$desc" "OK" "Sem manifesto"
        return 0
    fi

    local scan_args=()
    if [[ "$scan_flag" == "--sbom" ]]; then
        scan_args+=("-L" "$target_file")
    else
        scan_args+=("$scan_flag=$target_file")
    fi

    vuln_exceptions_load
    local exc_digest
    exc_digest="$(vuln_exceptions_digest)"

    local hash
    hash="$(sha256sum "$target_file" 2>/dev/null | awk '{print $1}')"
    hash="${hash}.${exc_digest}"

    if cache_is_valid "osv-scanner" "$hash" 10800; then
        log_step "$label" "$desc" "OK" "Cache (3h)"
        summary_add "$desc" "OK" "Cache (3h)"
        return 0
    fi

    log_step_header "$label" "$desc"
    _osv_run_scan "$bin" "${scan_args[@]}"

    local verdict
    verdict="$(_osv_classify_output "$_LOG_LAST_OUTPUT")"

    if _osv_fallback_enabled "$verdict"; then
        export OSV_SCANNER_LOCAL_DB_CACHE_DIRECTORY="$(_osv_offline_db_dir)"
        _osv_run_scan "$bin" --offline-vulnerabilities "${scan_args[@]}"
        _osv_settle "$label" "$desc" "$hash" "Modo offline (base local OSV)"
        return $?
    fi

    _osv_settle "$label" "$desc" "$hash" ""
}
