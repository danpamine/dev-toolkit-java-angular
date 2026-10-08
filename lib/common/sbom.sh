#!/usr/bin/env bash
# ==============================================================================
# sbom.sh - Geração de SBOM CycloneDX como Etapa de Dependência do DAG (Java)
# ==============================================================================

step_sbom_generate() {
    local label="$1"
    local desc="$2"

    if [[ ! -f "pom.xml" ]]; then
        log_step "$label" "$desc" "PULADO" "pom.xml ausente"
        summary_add "$desc" "SKIP" "Sem pom.xml"
        return 0
    fi

    if ! engine_is_enabled "FEATURE_SCA" && ! engine_is_enabled "FEATURE_OSV"; then
        log_step "$label" "$desc" "PULADO" "Sem consumidores de SBOM"
        summary_add "$desc" "SKIP" "SCA e OSV desativados"
        return 0
    fi

    local hash
    hash="$(sha256sum pom.xml 2>/dev/null | awk '{print $1}')"

    if cache_is_valid "sbom" "$hash"; then
        log_step "$label" "$desc" "OK" "Cache"
        [[ -n "${_CURRENT_ENGINE_DETAIL_FILE:-}" ]] && echo "Cache" > "$_CURRENT_ENGINE_DETAIL_FILE"
        summary_add "$desc" "OK" "Cache"
        return 0
    fi

    log_step_header "$label" "$desc"
    local syft_bin="syft"
    [[ -f "$LOCAL_BIN/syft.exe" ]] && syft_bin="$LOCAL_BIN/syft.exe"

    if command -v "$syft_bin" &>/dev/null; then
        log_substep "Gerando SBOM via Syft (target/bom.json)" "$syft_bin" scan dir:. -o cyclonedx-json="target/bom.json" -q
    else
        log_substep "Gerando SBOM via Maven CycloneDX (target/bom.json)" mvn org.cyclonedx:cyclonedx-maven-plugin:RELEASE:makeBom -DoutputFormat=json -DoutputName=bom -q
    fi

    if [[ -f "target/bom.json" ]]; then
        cache_save "sbom" "$hash"
        log_step "$label" "$desc" "OK" "target/bom.json"
        summary_add "$desc" "OK" "target/bom.json"
    else
        log_step "$label" "$desc" "FAIL"
        summary_add "$desc" "FAIL" "Falha ao gerar o SBOM"
        log_show_last
    fi
}
