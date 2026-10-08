#!/usr/bin/env bash
# ==============================================================================
# run-tests.sh - Testes Unitários e de Integração do Dev Toolkit
# ==============================================================================

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLKIT_ROOT="$(dirname "$TEST_DIR")"
SANDBOX="/tmp/dev_toolkit_tests_$$"

C_GREEN='\033[0;32m'
C_RED='\033[0;31m'
C_RESET='\033[0m'
_PASSED=0
_FAILED=0

assert() {
    local expected="$1"
    local actual="$2"
    local desc="$3"
    if [[ "$expected" == "$actual" ]]; then
        printf "  ${C_GREEN}[PASS]${C_RESET} %s\n" "$desc"
        ((_PASSED++))
    else
        printf "  ${C_RED}[FAIL]${C_RESET} %s (Esperado: '%s', Obtido: '%s')\n" "$desc" "$expected" "$actual"
        ((_FAILED++))
    fi
}

setup() {
    rm -rf "$SANDBOX"
    mkdir -p "$SANDBOX"
    cd "$SANDBOX" || exit 1
    git init --quiet -b main
    git config user.name "Toolkit Tester"
    git config user.email "tester@toolkit.corp"
}
teardown() {
    cd "$TOOLKIT_ROOT" || exit 1
    rm -rf "$SANDBOX"
}

test_cache_ttl() {
    printf "\n--- Teste 1: Validação do Cache e TTL de 3 horas ---\n"
    source "$TOOLKIT_ROOT/lib/common/cache.sh"
    cache_init "repo_test"

    echo "payload" > dummy.txt
    local h
    h=$(sha256sum dummy.txt | awk '{print $1}')
    cache_save "scope_a" "$h"

    assert "0" "$(cache_is_valid "scope_a" "$h" 10800; echo $?)" "Cache com menos de 3h deve ser válido"

    local done_f="${_CACHE_REPO_DIR}/scope_a.done"
    touch -d "4 hours ago" "$done_f" 2>/dev/null || touch -t 202001010000 "$done_f"
    assert "1" "$(cache_is_valid "scope_a" "$h" 10800; echo $?)" "Cache expirado após 3h deve retornar 1"
}

test_toggles() {
    printf "\n--- Teste 2: Feature Toggles e Reenumeração Dinâmica ---\n"
    source "$TOOLKIT_ROOT/lib/common/logging.sh"
    source "$TOOLKIT_ROOT/lib/common/summary.sh"
    source "$TOOLKIT_ROOT/lib/common/engine.sh"

    mock_ok() { return 0; }
    export FEATURE_TEST_ONE=1
    export FEATURE_TEST_TWO=0

    engine_reset
    engine_register "step1" "Etapa Ativa" mock_ok "FEATURE_TEST_ONE"
    engine_register "step2" "Etapa Inativa" mock_ok "FEATURE_TEST_TWO"

    assert "0" "$(engine_is_enabled "FEATURE_TEST_ONE"; echo $?)" "Toggle Ativo deve retornar 0"
    assert "1" "$(engine_is_enabled "FEATURE_TEST_TWO"; echo $?)" "Toggle Inativo deve retornar 1"
}

test_angular_test_resolution() {
    printf "\n--- Teste 3: Resolução de Teste Angular & Java (Sem arquivos de teste) ---\n"
    source "$TOOLKIT_ROOT/lib/common/commands.sh"

    echo '{"name": "mock-app"}' > package.json
    run_angular_test
    assert "0" "$?" "Deve finalizar com sucesso se não houver script no package.json"

    echo '{"name": "mock-app", "scripts": {"test": "exit 1"}}' > package.json
    mkdir -p src
    run_angular_test
    assert "0" "$?" "Deve finalizar com sucesso se script existir mas não houver arquivos físicos"

    run_java_verify
    assert "0" "$?" "Deve finalizar com sucesso em Java se não houver arquivos em src/test/java"
}

test_version_increments() {
    printf "\n--- Teste 4: Validação de Incremento Estrito vs. Branch Base Remota ---\n"
    source "$TOOLKIT_ROOT/lib/common/logging.sh"
    source "$TOOLKIT_ROOT/lib/common/summary.sh"
    source "$TOOLKIT_ROOT/lib/common/git-diff.sh"
    source "$TOOLKIT_ROOT/lib/java/version-check.sh"

    echo '<project><modelVersion>4.0.0</modelVersion><groupId>br.com.corp</groupId><artifactId>app</artifactId><version>1.0.0-SNAPSHOT</version></project>' > pom.xml
    git add pom.xml
    git commit -m "base commit" --quiet

    git checkout -b feature/minha-tarefa --quiet
    export BASE_BRANCH="main"

    echo '<project><modelVersion>4.0.0</modelVersion><groupId>br.com.corp</groupId><artifactId>app</artifactId><version>1.0.0-SNAPSHOT</version></project>' > pom.xml
    step_version_check "STEP" "Versão Pom" >/dev/null 2>&1
    assert "1" "$?" "Versão idêntica à base deve falhar (1.0.0-SNAPSHOT == 1.0.0-SNAPSHOT)"

    echo '<project><modelVersion>4.0.0</modelVersion><groupId>br.com.corp</groupId><artifactId>app</artifactId><version>0.9.0-SNAPSHOT</version></project>' > pom.xml
    step_version_check "STEP" "Versão Pom" >/dev/null 2>&1
    assert "1" "$?" "Versão regredida deve falhar (0.9.0-SNAPSHOT < 1.0.0-SNAPSHOT)"

    echo '<project><modelVersion>4.0.0</modelVersion><groupId>br.com.corp</groupId><artifactId>app</artifactId><version>1.0.1-SNAPSHOT</version></project>' > pom.xml
    step_version_check "STEP" "Versão Pom" >/dev/null 2>&1
    assert "0" "$?" "Versão incrementada deve ser aprovada (1.0.0-SNAPSHOT -> 1.0.1-SNAPSHOT)"
}

test_async_failures() {
    printf "\n--- Teste 5: Isolamento de Logs em Falhas Concorrentes ---\n"
    source "$TOOLKIT_ROOT/lib/common/logging.sh"
    source "$TOOLKIT_ROOT/lib/common/summary.sh"
    source "$TOOLKIT_ROOT/lib/common/engine.sh"

    mock_fail_1() { echo "Erro critico 1"; return 1; }
    mock_fail_2() { echo "Erro critico 2"; return 1; }
    export TOGGLE_F1=1
    export TOGGLE_F2=1

    engine_reset
    engine_register "fail1" "Validação Falha 1" mock_fail_1 "TOGGLE_F1"
    engine_register "fail2" "Validação Falha 2" mock_fail_2 "TOGGLE_F2"

    local log_out="/tmp/async_out_$$.log"
    engine_run "TESTE FALHAS CONCORRENTES" > "$log_out" 2>&1
    summary_print "RESUMO TESTE" "OK" "FAIL" >> "$log_out" 2>&1

    local has_f1=0 has_f2=0
    grep -q "Erro critico 1" "$log_out" && has_f1=1
    grep -q "Erro critico 2" "$log_out" && has_f2=1
    rm -f "$log_out"

    assert "1" "$has_f1" "Log da falha 1 deve constar no relatório final"
    assert "1" "$has_f2" "Log da falha 2 deve constar no relatório final sem sobreposição"
}

test_spotbugs_incremental() {
    printf "\n--- Teste 6: SpotBugs Incremental (Ignora quando sem alterações Java) ---\n"
    source "$TOOLKIT_ROOT/lib/common/logging.sh"
    source "$TOOLKIT_ROOT/lib/common/summary.sh"
    source "$TOOLKIT_ROOT/lib/common/git-diff.sh"
    source "$TOOLKIT_ROOT/lib/java/spotbugs.sh"

    echo '<project></project>' > pom.xml
    step_spotbugs "STEP" "SpotBugs" >/dev/null 2>&1
    assert "0" "$?" "SpotBugs deve concluir com sucesso em 0s quando não houver arquivos Java alterados"
}

test_gitleaks_pull_scope() {
    printf "\n--- Teste 7: Escopo do Gitleaks no Post-Merge ---\n"
    source "$TOOLKIT_ROOT/lib/common/gitleaks.sh"

    git update-ref -d ORIG_HEAD 2>/dev/null || true
    assert "full" "$(_gitleaks_pull_scope)" "Sem ORIG_HEAD deve degradar para full scan"

    git commit -m "init" --quiet --allow-empty
    local base_sha
    base_sha="$(git rev-parse HEAD)"

    git update-ref ORIG_HEAD "$base_sha"
    assert "empty" "$(_gitleaks_pull_scope)" "ORIG_HEAD igual a HEAD deve reportar nenhum commit recebido"

    git commit -m "novo commit" --quiet --allow-empty
    assert "range" "$(_gitleaks_pull_scope)" "Commits recebidos devem ser varridos por intervalo"
}

test_osv_classification() {
    printf "\n--- Teste 8: Classificação de Saída do OSV-Scanner ---\n"
    source "$TOOLKIT_ROOT/lib/common/osv-scanner.sh"

    assert "OK" "$(_osv_classify_output "Total 0 packages affected")" "Zero vulnerabilidades deve aprovar"
    assert "OK" "$(_osv_classify_output "No packages have known vulnerabilities, 0 known vulnerabilities")" "Saída de zero vulnerabilidades conhecidas deve aprovar"
    assert "FAIL" "$(_osv_classify_output "Total 3 packages affected")" "Vulnerabilidades reais devem reprovar"
    assert "SKIP" "$(_osv_classify_output "failed to query OSV database: dial tcp 127.0.0.1:443: i/o timeout")" "Falha de rede deve pular sem bloquear o fluxo"
    assert "FAIL" "$(_osv_classify_output "erro inesperado de parsing do manifesto")" "Erro desconhecido deve reprovar (comportamento conservador)"
}

test_osv_offline_fallback() {
    printf "\n--- Teste 9: Fallback Offline Automático do OSV-Scanner ---\n"
    source "$TOOLKIT_ROOT/lib/common/osv-scanner.sh"

    export DEV_TOOLKIT_CACHE_DIR="$SANDBOX/osv-cache"
    assert "1" "$(_osv_fallback_enabled "SKIP"; echo $?)" "Sem base local, falha de rede não deve tentar fallback offline"

    mkdir -p "$SANDBOX/osv-cache/osv-db/osv-scanner"
    assert "0" "$(_osv_fallback_enabled "SKIP"; echo $?)" "Com base local, falha de rede deve ativar fallback offline"
    assert "1" "$(_osv_fallback_enabled "FAIL"; echo $?)" "Vulnerabilidades reais não devem disparar fallback"
    assert "1" "$(_osv_fallback_enabled "OK"; echo $?)" "Resultado online válido não deve disparar fallback"
}

test_engine_multi_deps() {
    printf "\n--- Teste 10: DAG com Multi-Dependências ---\n"
    source "$TOOLKIT_ROOT/lib/common/logging.sh"
    source "$TOOLKIT_ROOT/lib/common/summary.sh"
    source "$TOOLKIT_ROOT/lib/common/engine.sh"

    mock_ok() { return 0; }
    mock_fail() { return 1; }
    export TOGGLE_M1=1
    export TOGGLE_M2=1
    export TOGGLE_M3=1

    engine_reset
    engine_register "m1" "Dependência A" mock_ok "TOGGLE_M1"
    engine_register "m2" "Dependência B" mock_ok "TOGGLE_M2"
    engine_register "m3" "Dependente" mock_ok "TOGGLE_M3" "m1,m2"
    engine_run "TESTE MULTI-DEP OK" >/dev/null 2>&1
    assert "DONE_0" "${_ENG_STEP_STATE[m3]:-}" "Dependente com duas dependências concluídas deve executar"

    engine_reset
    engine_register "m1" "Dependência A" mock_fail "TOGGLE_M1"
    engine_register "m2" "Dependência B" mock_ok "TOGGLE_M2"
    engine_register "m3" "Dependente" mock_ok "TOGGLE_M3" "m1,m2"
    engine_run "TESTE MULTI-DEP FALHA" >/dev/null 2>&1
    assert "SKIPPED_DEP" "${_ENG_STEP_STATE[m3]:-}" "Falha em qualquer dependência deve bloquear o dependente"

    export TOGGLE_M2=0
    engine_reset
    engine_register "m1" "Dependência A" mock_ok "TOGGLE_M1"
    engine_register "m2" "Dependência B" mock_ok "TOGGLE_M2"
    engine_register "m3" "Dependente" mock_ok "TOGGLE_M3" "m1,m2"
    engine_run "TESTE MULTI-DEP DESATIVADA" >/dev/null 2>&1
    assert "SKIPPED_DEP" "${_ENG_STEP_STATE[m3]:-}" "Dependência desativada por toggle deve pular o dependente"
    export TOGGLE_M2=1
}

setup
test_cache_ttl
test_toggles
test_angular_test_resolution
test_version_increments
test_async_failures
test_spotbugs_incremental
test_gitleaks_pull_scope
test_osv_classification
test_osv_offline_fallback
test_engine_multi_deps
teardown

printf "\n==================================================\n"
printf "Resultado: %d passaram, %d falharam.\n" "$_PASSED" "$_FAILED"
[[ $_FAILED -gt 0 ]] && exit 1
exit 0
