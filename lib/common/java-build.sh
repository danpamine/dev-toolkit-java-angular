#!/usr/bin/env bash
# ==============================================================================
# java-build.sh - Compilação do Projeto Java como Etapa de Dependência do DAG
# ==============================================================================

if ! declare -f git_diff_target_files &>/dev/null; then
    _SCRIPT_D="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    _TK_R="${TOOLKIT_ROOT:-$(cd "$_SCRIPT_D/../.." && pwd)}"
    if [[ -f "$_TK_R/lib/common/git-diff.sh" ]]; then
        source "$_TK_R/lib/common/git-diff.sh"
    fi
fi

step_java_build() {
    local label="$1"
    local desc="$2"

    if [[ ! -f "pom.xml" ]]; then
        log_step "$label" "$desc" "PULADO" "pom.xml ausente"
        summary_add "$desc" "SKIP" "Sem pom.xml"
        return 0
    fi

    if ! engine_is_enabled "FEATURE_SPOTBUGS" && ! engine_is_enabled "FEATURE_PMD" \
        && ! engine_is_enabled "FEATURE_OPENAPI" && ! engine_is_enabled "FEATURE_MAVEN_VERIFY"; then
        log_step "$label" "$desc" "PULADO" "Sem consumidores de compilação"
        summary_add "$desc" "SKIP" "Nenhuma etapa dependente de build ativa"
        return 0
    fi

    local changed_java_files=()
    while IFS= read -r f; do
        [[ -n "$f" && -f "$f" ]] && changed_java_files+=("$f")
    done < <(git_diff_target_files "*.java" 2>/dev/null)

    local hash
    hash=$( (sha256sum pom.xml 2>/dev/null; sha256sum "${changed_java_files[@]}" 2>/dev/null) | sha256sum | awk '{print $1}')

    if cache_is_valid "java-build" "$hash" && [[ -d "target" ]]; then
        log_step "$label" "$desc" "OK" "Cache"
        [[ -n "${_CURRENT_ENGINE_DETAIL_FILE:-}" ]] && echo "Cache" > "$_CURRENT_ENGINE_DETAIL_FILE"
        summary_add "$desc" "OK" "Cache"
        return 0
    fi

    log_step_header "$label" "$desc"

    rm -rf "target" 2>/dev/null || true
    log_substep "Compilando projeto (mvn test-compile)" mvn test-compile -q -DskipTests
    local exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
        cache_save "java-build" "$hash"
        log_step "$label" "$desc" "OK"
        summary_add "$desc" "OK"
    else
        log_step "$label" "$desc" "FAIL"
        summary_add "$desc" "FAIL" "Falha na compilação do projeto"
        log_show_last
    fi
    return $exit_code
}
