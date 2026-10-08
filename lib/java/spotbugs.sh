#!/usr/bin/env bash
# ==============================================================================
# spotbugs.sh - Análise SAST Incremental com SpotBugs + FindSecBugs (Latest Stable)
# ==============================================================================

if ! declare -f git_diff_target_files &>/dev/null; then
    _SCRIPT_D="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    _TK_R="${TOOLKIT_ROOT:-$(cd "$_SCRIPT_D/../.." && pwd)}"
    if [[ -f "$_TK_R/lib/common/git-diff.sh" ]]; then
        source "$_TK_R/lib/common/git-diff.sh"
    fi
fi

if ! declare -f maven_resolve_plugin_version &>/dev/null; then
    _SCRIPT_D="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    _TK_R="${TOOLKIT_ROOT:-$(cd "$_SCRIPT_D/../.." && pwd)}"
    if [[ -f "$_TK_R/lib/common/commands.sh" ]]; then
        source "$_TK_R/lib/common/commands.sh"
    fi
fi

step_spotbugs() {
    local label="$1"
    local desc="$2"

    if [[ ! -f "pom.xml" ]]; then
        log_step "$label" "$desc" "PULADO" "pom.xml ausente"
        summary_add "$desc" "SKIP" "Sem pom.xml"
        return 0
    fi

    local changed_java_files=()
    while IFS= read -r f; do
        [[ -n "$f" && -f "$f" ]] && changed_java_files+=("$f")
    done < <(git_diff_target_files "*.java" 2>/dev/null)

    if [[ ${#changed_java_files[@]} -eq 0 ]]; then
        log_step "$label" "$desc" "OK" "Sem arquivos Java alterados"
        [[ -n "${_CURRENT_ENGINE_DETAIL_FILE:-}" ]] && echo "Sem alterações" > "$_CURRENT_ENGINE_DETAIL_FILE"
        summary_add "$desc" "OK" "Sem alterações"
        return 0
    fi

    local target_classes=()
    for f in "${changed_java_files[@]}"; do
        if [[ "$f" =~ (^|/)src/test/ ]]; then
            continue
        fi

        local cls
        cls=$(basename "$f" .java)
        [[ "$cls" == "package-info" || "$cls" == "module-info" ]] && continue

        local pkg
        pkg=$(grep -E '^[[:space:]]*package[[:space:]]+' "$f" 2>/dev/null | head -1 | sed -E 's/^[[:space:]]*package[[:space:]]+([^;]+);.*/\1/' | tr -d '\r\n ')

        local fqcn="$cls"
        [[ -n "$pkg" ]] && fqcn="${pkg}.${cls}"
        target_classes+=("$fqcn")
    done

    if [[ ${#target_classes[@]} -eq 0 ]]; then
        log_step "$label" "$desc" "OK" "Sem classes de produção alteradas"
        [[ -n "${_CURRENT_ENGINE_DETAIL_FILE:-}" ]] && echo "Sem alterações em src/main" > "$_CURRENT_ENGINE_DETAIL_FILE"
        summary_add "$desc" "OK" "Sem alterações em src/main"
        return 0
    fi

    local unique_classes=()
    while IFS= read -r c; do
        [[ -n "$c" ]] && unique_classes+=("$c")
    done < <(printf '%s\n' "${target_classes[@]}" | sort -u)

    local hash
    hash=$( (sha256sum pom.xml 2>/dev/null; sha256sum "${changed_java_files[@]}" 2>/dev/null) | sha256sum | awk '{print $1}')

    if cache_is_valid "spotbugs" "$hash"; then
        log_step "$label" "$desc" "OK" "Cache"
        [[ -n "${_CURRENT_ENGINE_DETAIL_FILE:-}" ]] && echo "Cache" > "$_CURRENT_ENGINE_DETAIL_FILE"
        summary_add "$desc" "OK" "Cache"
        return 0
    fi

    local class_filter
    class_filter=$(IFS=,; echo "${unique_classes[*]}")

    local spotbugs_ver findsecbugs_ver
    spotbugs_ver="$(maven_resolve_plugin_version "com/github/spotbugs" "spotbugs-maven-plugin" "${SPOTBUGS_PLUGIN_VERSION:-}")"
    findsecbugs_ver="$(maven_resolve_plugin_version "com/h3xstream/findsecbugs" "findsecbugs-plugin" "${FINDSECBUGS_PLUGIN_VERSION:-}")"

    if [[ -z "$spotbugs_ver" || -z "$findsecbugs_ver" ]]; then
        log_step "$label" "$desc" "FAIL" "Não foi possível resolver versão do SpotBugs/FindSecBugs"
        [[ -n "${_CURRENT_ENGINE_DETAIL_FILE:-}" ]] && echo "Falha na resolução de versão" > "$_CURRENT_ENGINE_DETAIL_FILE"
        summary_add "$desc" "FAIL" "Conecte-se à rede para baixar a versão mais recente do SpotBugs"
        return 1
    fi

    log_step_header "$label" "$desc"

    log_substep "Executando SpotBugs v${spotbugs_ver} + FindSecBugs v${findsecbugs_ver} (${#unique_classes[@]} classe(s))" \
        mvn com.github.spotbugs:spotbugs-maven-plugin:"${spotbugs_ver}":check \
            -Dspotbugs.effort=max \
            -Dspotbugs.threshold=low \
            -Dspotbugs.failOnError=true \
            -Dspotbugs.plugins=com.h3xstream.findsecbugs:findsecbugs-plugin:"${findsecbugs_ver}" \
            -Dspotbugs.onlyAnalyze="$class_filter" \
            -DonlyAnalyze="$class_filter" -q
    local exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
        cache_save "spotbugs" "$hash"
        local detail_msg="${#unique_classes[@]} classe(s)"
        [[ -n "${_CURRENT_ENGINE_DETAIL_FILE:-}" ]] && echo "$detail_msg" > "$_CURRENT_ENGINE_DETAIL_FILE"
        log_step "$label" "$desc" "OK" "$detail_msg"
        summary_add "$desc" "OK" "$detail_msg"
    else
        log_step "$label" "$desc" "FAIL"
        summary_add "$desc" "FAIL" "Vulnerabilidades detectadas pelo SpotBugs + FindSecBugs"
        log_show_last
    fi
    return $exit_code
}
