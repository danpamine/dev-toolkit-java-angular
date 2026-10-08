#!/usr/bin/env bash
# ==============================================================================
# sca-trivy.sh - SCA com Trivy (TTL: 3h, Todas as Severidades, Unfixed Off)
# ==============================================================================

step_sca_universal() {
    local label="$1"
    local desc="$2"
    local trivy_bin="trivy"
    [[ -f "$LOCAL_BIN/trivy.exe" ]] && trivy_bin="$LOCAL_BIN/trivy.exe"

    if ! command -v "$trivy_bin" &>/dev/null; then
        log_step "$label" "$desc" "PULADO" "Trivy não instalado"
        summary_add "$desc" "SKIP" "Trivy ausente"
        return 0
    fi

    local target_hash=""
    if [[ -f "pom.xml" ]]; then
        target_hash="$(sha256sum pom.xml 2>/dev/null | awk '{print $1}')"
    elif [[ -f "package-lock.json" ]]; then
        target_hash="$(sha256sum package-lock.json 2>/dev/null | awk '{print $1}')"
    elif [[ -f "pnpm-lock.yaml" ]]; then
        target_hash="$(sha256sum pnpm-lock.yaml 2>/dev/null | awk '{print $1}')"
    fi

    if [[ -n "$target_hash" ]] && cache_is_valid "trivy-sca" "$target_hash" 10800; then
        log_step "$label" "$desc" "OK" "Cache (3h)"
        summary_add "$desc" "OK" "Cache (3h)"
        return 0
    fi

    log_step_header "$label" "$desc"
    local exit_code=0

    if [[ -f "pom.xml" ]]; then
        local sbom_file=""
        if [[ -f "target/bom.json" ]]; then
            sbom_file="target/bom.json"
        else
            local syft_bin="syft"
            [[ -f "$LOCAL_BIN/syft.exe" ]] && syft_bin="$LOCAL_BIN/syft.exe"
            local tmp_sbom="/tmp/sbom_java_$$.json"

            if command -v "$syft_bin" &>/dev/null; then
                log_substep "Gerando SBOM via Syft" "$syft_bin" scan dir:. -o cyclonedx-json="$tmp_sbom" -q
            else
                log_substep "Gerando SBOM via Maven CycloneDX" mvn org.cyclonedx:cyclonedx-maven-plugin:RELEASE:makeBom -DoutputFormat=json -DoutputName=sbom -q
                [[ -f "target/sbom.json" ]] && cp target/sbom.json "$tmp_sbom"
            fi
            sbom_file="$tmp_sbom"
        fi

        log_substep "Varrendo vulnerabilidades SBOM (Trivy)" "$trivy_bin" sbom "$sbom_file" \
            --scanners vuln \
            --ignore-unfixed \
            --severity LOW,MEDIUM,HIGH,CRITICAL \
            --exit-code 1

        exit_code=$?
        [[ "$sbom_file" == /tmp/* ]] && rm -f "$sbom_file"
    else
        log_substep "Varrendo dependências Angular (Trivy)" "$trivy_bin" fs . \
            --scanners vuln \
            --ignore-unfixed \
            --severity LOW,MEDIUM,HIGH,CRITICAL \
            --exit-code 1

        exit_code=$?
    fi

    if [[ $exit_code -eq 0 ]]; then
        [[ -n "$target_hash" ]] && cache_save "trivy-sca" "$target_hash"
        log_step "$label" "$desc" "OK"
        summary_add "$desc" "OK"
    else
        log_step "$label" "$desc" "FAIL"
        summary_add "$desc" "FAIL" "Atualize dependências com CVEs que possuem patch disponível"
        log_show_last 30
    fi
    return $exit_code
}
