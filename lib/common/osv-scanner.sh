#!/usr/bin/env bash
# ==============================================================================
# osv-scanner.sh - SCA Rápido via Google OSV Database com fallback offline automático
# ==============================================================================

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

_osv_report_ok() {
    local label="$1"
    local desc="$2"
    local detail="${3:-}"
    local hash="$4"
    cache_save "osv-scanner" "$hash"
    log_step "$label" "$desc" "OK" "$detail"
    summary_add "$desc" "OK" "$detail"
}

_osv_report_fail() {
    local label="$1"
    local desc="$2"
    local detail="$3"
    log_step "$label" "$desc" "FAIL"
    summary_add "$desc" "FAIL" "$detail"
    log_show_last
}

_osv_report_skip() {
    local label="$1"
    local desc="$2"
    local detail="$3"
    log_step "$label" "$desc" "PULADO" "$detail"
    summary_add "$desc" "SKIP" "$detail"
}

_osv_finalize() {
    local label="$1"
    local desc="$2"
    local verdict="$3"
    local hash="$4"

    case "$verdict" in
        OK)
            _osv_report_ok "$label" "$desc" "" "$hash"
            return 0
            ;;
        SKIP)
            _osv_report_skip "$label" "$desc" "Rede corporativa indisponível para consulta OSV"
            return 0
            ;;
        *)
            _osv_report_fail "$label" "$desc" "Vulnerabilidades identificadas pelo OSV-Scanner"
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
        _osv_report_skip "$label" "$desc" "osv-scanner não instalado"
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

    local hash
    hash="$(sha256sum "$target_file" 2>/dev/null | awk '{print $1}')"
    if cache_is_valid "osv-scanner" "$hash" 10800; then
        log_step "$label" "$desc" "OK" "Cache (3h)"
        summary_add "$desc" "OK" "Cache (3h)"
        return 0
    fi

    log_step_header "$label" "$desc"
    _osv_run_scan "$bin" "$scan_flag=$target_file"

    local verdict
    verdict="$(_osv_classify_output "$_LOG_LAST_OUTPUT")"

    if _osv_fallback_enabled "$verdict"; then
        export OSV_SCANNER_LOCAL_DB_CACHE_DIRECTORY="$(_osv_offline_db_dir)"
        _osv_run_scan "$bin" --offline-vulnerabilities "$scan_flag=$target_file"
        verdict="$(_osv_classify_output "$_LOG_LAST_OUTPUT")"

        case "$verdict" in
            OK)
                _osv_report_ok "$label" "$desc" "Modo offline (base local OSV)" "$hash"
                summary_add "$desc" "OK" "Modo offline aplicado: rede corporativa indisponível para consulta online"
                return 0
                ;;
            SKIP)
                _osv_report_skip "$label" "$desc" "Rede corporativa e base local OSV indisponíveis"
                return 0
                ;;
            *)
                _osv_report_fail "$label" "$desc" "Vulnerabilidades identificadas pelo OSV-Scanner (modo offline)"
                return 1
                ;;
        esac
    fi

    _osv_finalize "$label" "$desc" "$verdict" "$hash"
}
