#!/usr/bin/env bash
# ==============================================================================
# tool-update.sh - Gatilho de Atualização Diária por Ferramenta e Provisionamento
# ==============================================================================
_TOOL_UPDATE_DIR="${DEV_TOOLKIT_UPDATE_DIR:-$HOME/.dev-toolkit/updates}"
_TOOL_UPDATE_FILE="${_TOOL_UPDATE_DIR}/updates.env"
_TOOL_UPDATE_TODAY="$(date +%F)"

_is_windows() {
    [[ "$(uname -s)" =~ ^(MINGW|MSYS|CYGWIN) ]]
}

_tool_bin_suffix() {
    if _is_windows; then printf '.exe'; else printf ''; fi
}

_tool_update_marker_read() {
    local tool="$1"
    [[ -f "$_TOOL_UPDATE_FILE" ]] || { printf ''; return 0; }
    local line
    line="$(grep -E "^${tool}_LAST_UPDATE=" "$_TOOL_UPDATE_FILE" 2>/dev/null | tail -1 | cut -d= -f2 | tr -d '\r\n')"
    printf '%s' "$line"
}

_tool_update_marker_write() {
    local tool="$1"
    mkdir -p "$_TOOL_UPDATE_DIR" 2>/dev/null || true
    local tmp_file="${_TOOL_UPDATE_FILE}.tmp.$$"
    { grep -vE "^${tool}_LAST_UPDATE=" "$_TOOL_UPDATE_FILE" 2>/dev/null; printf '%s_LAST_UPDATE=%s\n' "$tool" "$_TOOL_UPDATE_TODAY"; } > "$tmp_file" 2>/dev/null
    mv -f "$tmp_file" "$_TOOL_UPDATE_FILE" 2>/dev/null || true
}

_tool_update_force() {
    local tool="$1"
    [[ "${DEV_TOOLKIT_FORCE_UPDATE:-0}" == "1" ]] && return 0
    local force_var="DEV_TOOLKIT_FORCE_UPDATE_${tool}"
    [[ "${!force_var:-0}" == "1" ]]
}

_tool_update_due() {
    local tool="$1"
    _tool_update_force "$tool" && return 0
    local last
    last="$(_tool_update_marker_read "$tool")"
    [[ "$last" != "$_TOOL_UPDATE_TODAY" ]]
}

_tool_update_bin_present() {
    local tool="$1"
    local local_bin="${LOCAL_BIN:-$HOME/.local/bin}"
    local suffix
    suffix="$(_tool_bin_suffix)"
    case "$tool" in
        GITLEAKS) [[ -f "$local_bin/gitleaks${suffix}" ]] || command -v gitleaks &>/dev/null ;;
        TRIVY) [[ -f "$local_bin/trivy${suffix}" ]] || command -v trivy &>/dev/null ;;
        SYFT) [[ -f "$local_bin/syft${suffix}" ]] || command -v syft &>/dev/null ;;
        GJF) [[ -f "$local_bin/google-java-format.jar" ]] ;;
        AST_GREP) [[ -f "$local_bin/ast-grep${suffix}" ]] || command -v ast-grep &>/dev/null ;;
        OSV_SCANNER) [[ -f "$local_bin/osv-scanner${suffix}" ]] || command -v osv-scanner &>/dev/null ;;
        *) return 1 ;;
    esac
}

_tool_update_tools_for_step() {
    local step_id="$1"
    case "$step_id" in
        gitleaks|gitleaks-pull) printf 'GITLEAKS' ;;
        sca) printf 'TRIVY SYFT' ;;
        osv) printf 'OSV_SCANNER' ;;
        semgrep) printf 'PYTHON' ;;
        java-format) printf 'GJF' ;;
        ast-grep) printf 'AST_GREP' ;;
        *) printf '' ;;
    esac
}

_tool_update_osv_db() {
    local local_bin="${LOCAL_BIN:-$HOME/.local/bin}"
    local suffix
    suffix="$(_tool_bin_suffix)"
    local bin="${local_bin}/osv-scanner${suffix}"
    command -v "$bin" &>/dev/null || bin="osv-scanner"
    command -v "$bin" &>/dev/null || return 0
    local cache_base="${DEV_TOOLKIT_CACHE_DIR:-/tmp/cicd_cache}"
    cache_base="${cache_base%$'\r'}"
    local db_dir="${cache_base}/osv-db"
    mkdir -p "$db_dir" 2>/dev/null || true
    if [[ -d "$db_dir/osv-scanner" ]] && ! _tool_update_due "OSV_DB"; then
        return 0
    fi
    printf "${_C_INFO}[BOOTSTRAP]${_C_RESET} Sincronizando base local oficial do OSV (best effort)...\n"
    OSV_SCANNER_LOCAL_DB_CACHE_DIRECTORY="$db_dir" "$bin" scan --offline-vulnerabilities --download-offline-databases "$TOOLKIT_ROOT" >/dev/null 2>&1 || true
    _tool_update_marker_write "OSV_DB"
}

_toolkit_self_update_guard() {
    [[ "${DEV_TOOLKIT_NO_UPDATE:-0}" == "1" ]] && return 0
    type toolkit_auto_update &>/dev/null || return 0
    local pre_sha post_sha
    pre_sha="$(git -C "$TOOLKIT_ROOT" rev-parse HEAD 2>/dev/null)"
    toolkit_auto_update
    post_sha="$(git -C "$TOOLKIT_ROOT" rev-parse HEAD 2>/dev/null)"
    if [[ -n "$pre_sha" && -n "$post_sha" && "$pre_sha" != "$post_sha" ]]; then
        printf "${_C_BYELLOW}[AUTO-UPDATE]${_C_RESET} Dev Toolkit atualizado (%s -> %s).\n" "${pre_sha:0:7}" "${post_sha:0:7}"
        printf "${_C_BYELLOW}[AUTO-UPDATE]${_C_RESET} Validação abortada: execute o comando novamente para validar com a versão atual.\n"
        exit 1
    fi
}

bootstrap_ensure_tool() {
    local tool="$1"
    if _tool_update_bin_present "$tool" && ! _tool_update_due "$tool"; then
        printf "${_C_SUCCESS}[BOOTSTRAP]${_C_RESET} %s: atualizado hoje\n" "$tool"
        return 0
    fi
    local local_bin="${LOCAL_BIN:-$HOME/.local/bin}"
    mkdir -p "$local_bin" 2>/dev/null || true
    local ensure_code=0
    case "$tool" in
        GITLEAKS)
            if _is_windows; then
                _bootstrap_download_latest "gitleaks/gitleaks" "windows.*(x64|x86_64).*\.zip" "$local_bin/gitleaks.exe" "Gitleaks" || ensure_code=$?
            else
                _bootstrap_download_latest "gitleaks/gitleaks" "linux_x64.*\.tar\.gz" "$local_bin/gitleaks" "Gitleaks" || ensure_code=$?
            fi
            ;;
        TRIVY)
            if _is_windows; then
                _bootstrap_download_latest "aquasecurity/trivy" "windows.*64.*\.zip" "$local_bin/trivy.exe" "Trivy SCA" || ensure_code=$?
            else
                _bootstrap_download_latest "aquasecurity/trivy" "Linux-64bit.*\.tar\.gz" "$local_bin/trivy" "Trivy SCA" || ensure_code=$?
            fi
            ;;
        GJF)
            _bootstrap_download_latest "google/google-java-format" "google-java-format.*all-deps\.jar" "$local_bin/google-java-format.jar" "Google Java Format" || ensure_code=$?
            ;;
        SYFT)
            if _is_windows; then
                _bootstrap_download_latest "anchore/syft" "windows.*(x86_64|amd64).*\.zip" "$local_bin/syft.exe" "Syft SBOM" || ensure_code=$?
            else
                _bootstrap_download_latest "anchore/syft" "linux_amd64.*\.tar\.gz" "$local_bin/syft" "Syft SBOM" || ensure_code=$?
            fi
            ;;
        AST_GREP)
            if _is_windows; then
                _bootstrap_download_latest "ast-grep/ast-grep" "x86_64-pc-windows-msvc\.zip" "$local_bin/ast-grep.exe" "ast-grep" || ensure_code=$?
            else
                _bootstrap_download_latest "ast-grep/ast-grep" "app-x86_64-unknown-linux-gnu\.zip" "$local_bin/ast-grep" "ast-grep" || ensure_code=$?
            fi
            ;;
        OSV_SCANNER)
            if _is_windows; then
                _bootstrap_download_latest "google/osv-scanner" "windows_amd64\.exe" "$local_bin/osv-scanner.exe" "OSV Scanner" || ensure_code=$?
            else
                _bootstrap_download_latest "google/osv-scanner" "linux_amd64" "$local_bin/osv-scanner" "OSV Scanner" || ensure_code=$?
            fi
            _tool_update_osv_db
            ;;
        PYTHON)
            bootstrap_python_ensure || ensure_code=$?
            ;;
        *)
            return 0
            ;;
    esac
    if [[ $ensure_code -eq 0 && "$tool" != "PYTHON" ]]; then
        _tool_update_marker_write "$tool"
    fi
    return $ensure_code
}

bootstrap_prepare() {
    _toolkit_self_update_guard
    local local_bin="${LOCAL_BIN:-$HOME/.local/bin}"
    local deps_dir="${DEV_TOOLKIT_DEPENDENCIES_DIR:-${TOOLKIT_ROOT}/dependencies}"
    mkdir -p "$local_bin" "$deps_dir" 2>/dev/null || true
    [[ -z "${_ENG_IDS+x}" ]] && return 0
    local i id toggle tools
    local needed=""
    local total=${#_ENG_IDS[@]}
    for ((i=0; i<total; i++)); do
        id="${_ENG_IDS[$i]}"
        toggle="${_ENG_TOGGLES[$i]}"
        engine_is_enabled "$toggle" || continue
        tools="$(_tool_update_tools_for_step "$id")"
        [[ -n "$tools" ]] && needed="$needed $tools"
    done
    local tool
    for tool in $(printf '%s\n' $needed | sort -u); do
        bootstrap_ensure_tool "$tool"
    done
}

_tool_update_py_dir() {
    printf '%s' "${DEV_TOOLKIT_PYTHON_DIR:-${TOOLKIT_ROOT}/dependencies/python}"
}

_semgrep_python_bin() {
    local py_dir="$(_tool_update_py_dir)"
    if _is_windows; then printf '%s/python.exe' "$py_dir"; else printf '%s/venv/bin/python' "$py_dir"; fi
}

_semgrep_exec_bin() {
    local py_dir="$(_tool_update_py_dir)"
    if _is_windows; then printf '%s/Scripts/semgrep.exe' "$py_dir"; else printf '%s/venv/bin/semgrep' "$py_dir"; fi
}

_semgrep_works() {
    local semgrep_bin
    semgrep_bin="$(_semgrep_exec_bin)"
    [[ -f "$semgrep_bin" ]] && "$semgrep_bin" --version &>/dev/null
}

_semgrep_pip_install() {
    "$(_semgrep_python_bin)" -m pip install semgrep --timeout 25 --retries 1 --no-warn-script-location -q "$@" 2>/dev/null
}

_semgrep_install_channels() {
    local semgrep_bin
    semgrep_bin="$(_semgrep_exec_bin)"
    local py_dir="$(_tool_update_py_dir)"
    if [[ -d "${py_dir}/wheels" ]]; then
        _semgrep_pip_install --no-index --find-links "${py_dir}/wheels"
        [[ -f "$semgrep_bin" ]] && "$semgrep_bin" --version &>/dev/null && return 0
    fi
    _semgrep_pip_install --trusted-host pypi.org --trusted-host files.pythonhosted.org --trusted-host pypi.python.org
    [[ -f "$semgrep_bin" ]] && "$semgrep_bin" --version &>/dev/null && return 0
    if [[ -n "${DEV_TOOLKIT_PYPI_INDEX_URL:-}" ]]; then
        _semgrep_pip_install --index-url "$DEV_TOOLKIT_PYPI_INDEX_URL"
        [[ -f "$semgrep_bin" ]] && "$semgrep_bin" --version &>/dev/null && return 0
    fi
    if [[ -n "${DEV_TOOLKIT_SEMGREP_WHEELS_DIR:-}" && -d "${DEV_TOOLKIT_SEMGREP_WHEELS_DIR}" ]]; then
        _semgrep_pip_install --no-index --find-links "$DEV_TOOLKIT_SEMGREP_WHEELS_DIR"
        [[ -f "$semgrep_bin" ]] && "$semgrep_bin" --version &>/dev/null && return 0
    fi
    return 1
}

_bootstrap_python_candidates() {
    if [[ -n "${DEV_TOOLKIT_PYTHON_VERSION:-}" ]]; then
        printf '%s\n' "${DEV_TOOLKIT_PYTHON_VERSION}"
        return 0
    fi
    curl -sL --ssl-no-revoke --connect-timeout 4 --max-time 8 "https://www.python.org/ftp/python/" 2>/dev/null \
        | grep -oE 'href="3\.[0-9]+\.[0-9]+/"' \
        | sed 's/href="//;s/"//;s#/$##' \
        | sort -V | tail -3 | tac
}

_bootstrap_python_install_linux() {
    local py_dir="$(_tool_update_py_dir)"
    local py_bin="${DEV_TOOLKIT_LINUX_PYTHON:-python3}"
    if ! command -v "$py_bin" &>/dev/null; then
        printf "${_C_ERROR}[BOOTSTRAP]${_C_RESET} Python ausente no Linux. Instale o pacote python3 do SO ou defina DEV_TOOLKIT_LINUX_PYTHON.\n"
        return 1
    fi
    rm -rf "$py_dir/venv" 2>/dev/null || true
    mkdir -p "$py_dir" 2>/dev/null || true
    printf "${_C_INFO}[BOOTSTRAP]${_C_RESET} Criando venv isolado em %s...\n" "$py_dir/venv"
    if ! "$py_bin" -m venv "$py_dir/venv" 2>/dev/null; then
        printf "${_C_ERROR}[BOOTSTRAP]${_C_RESET} Falha ao criar venv. Instale o suporte a venv (python3-venv ou equivalente).\n"
        rm -rf "$py_dir/venv" 2>/dev/null || true
        return 1
    fi
    "${py_dir}/venv/bin/python" -m pip install --upgrade pip -q 2>/dev/null || true
    if _semgrep_install_channels; then
        local real_py_ver real_semgrep_ver
        real_py_ver="$("${py_dir}/venv/bin/python" -c 'import sys; print(".".join(map(str, sys.version_info[:3])))' 2>/dev/null || echo '?')"
        real_semgrep_ver="$("${py_dir}/venv/bin/semgrep" --version 2>/dev/null | head -1 | tr -d '\r\n')"
        printf "${_C_SUCCESS}[BOOTSTRAP]${_C_RESET} Python venv v%s (Semgrep %s): OK (isolado do SO)\n" "$real_py_ver" "$real_semgrep_ver"
        return 0
    fi
    rm -rf "$py_dir/venv" 2>/dev/null || true
    return 1
}

bootstrap_python_install() {
    if ! _is_windows; then
        _bootstrap_python_install_linux
        return $?
    fi
    local py_dir="$(_tool_update_py_dir)"
    local ver py_url tmp_zip
    for ver in $(_bootstrap_python_candidates); do
        py_url="https://www.python.org/ftp/python/${ver}/python-${ver}-embed-amd64.zip"
        tmp_zip="/tmp/py_portable_$$.zip"
        rm -rf "$py_dir" 2>/dev/null || true
        mkdir -p "$py_dir" 2>/dev/null || true
        printf "${_C_INFO}[BOOTSTRAP]${_C_RESET} Instalando Python Portátil v%s...\n" "$ver"
        if ! curl -sL --ssl-no-revoke --connect-timeout 8 --max-time 60 "$py_url" -o "$tmp_zip" 2>/dev/null; then
            rm -f "$tmp_zip" 2>/dev/null
            continue
        fi
        unzip -o -q "$tmp_zip" -d "$py_dir" 2>/dev/null
        rm -f "$tmp_zip" 2>/dev/null
        local pth_file
        pth_file="$(find "$py_dir" -maxdepth 1 -name "*._pth" 2>/dev/null | head -1)"
        if [[ -f "$pth_file" ]]; then
            sed -i 's/^#import site/import site/' "$pth_file"
            grep -q "^import site" "$pth_file" || echo "import site" >> "$pth_file"
            grep -q "Lib/site-packages" "$pth_file" || echo "Lib/site-packages" >> "$pth_file"
        fi
        local win_py_dir
        win_py_dir="$(cygpath -w "$py_dir" 2>/dev/null || echo "$py_dir")"
        powershell -Command "Get-ChildItem -LiteralPath '$win_py_dir' -Recurse | Unblock-File" 2>/dev/null || true
        local py_exe="${py_dir}/python.exe"
        local get_pip="${py_dir}/get-pip.py"
        if curl -sL --ssl-no-revoke --connect-timeout 8 --max-time 30 "https://bootstrap.pypa.io/get-pip.py" -o "$get_pip" 2>/dev/null; then
            "$py_exe" "$get_pip" --no-warn-script-location --no-setuptools --no-wheel -q 2>/dev/null || true
            rm -f "$get_pip" 2>/dev/null
        fi
        if _semgrep_install_channels; then
            local real_py_ver real_semgrep_ver
            real_py_ver="$("$py_exe" -c 'import sys; print(".".join(map(str, sys.version_info[:3])))' 2>/dev/null || echo "$ver")"
            real_semgrep_ver="$("${py_dir}/Scripts/semgrep.exe" --version 2>/dev/null | head -1 | tr -d '\r\n')"
            printf "${_C_SUCCESS}[BOOTSTRAP]${_C_RESET} Python Portátil v%s (Semgrep %s): OK (instalado)\n" "$real_py_ver" "$real_semgrep_ver"
            return 0
        fi
    done
    rm -rf "$py_dir" 2>/dev/null || true
    return 1
}

bootstrap_python_ensure() {
    if _semgrep_works; then
        local py_exe semgrep_bin py_ver s_ver
        py_exe="$(_semgrep_python_bin)"
        semgrep_bin="$(_semgrep_exec_bin)"
        py_ver="$("$py_exe" -c 'import sys; print(".".join(map(str, sys.version_info[:3])))' 2>/dev/null)"
        s_ver="$("$semgrep_bin" --version 2>/dev/null | head -1 | tr -d '\r\n')"
        if _is_windows; then
            printf "${_C_SUCCESS}[BOOTSTRAP]${_C_RESET} Python Portátil v%s (Semgrep %s): OK\n" "$py_ver" "$s_ver"
        else
            printf "${_C_SUCCESS}[BOOTSTRAP]${_C_RESET} Python venv v%s (Semgrep %s): OK (isolado do SO)\n" "$py_ver" "$s_ver"
        fi
        return 0
    fi
    if bootstrap_python_install; then
        return 0
    fi
    if [[ "${FEATURE_SEMGREP_REQUIRED:-1}" == "1" ]]; then
        printf "${_C_ERROR}[BOOTSTRAP]${_C_RESET} Falha ao instalar Python + Semgrep (obrigatório). Verifique rede, mirror corporativo ou wheels offline.\n"
        return 1
    fi
    printf "${_C_WARN}[BOOTSTRAP]${_C_RESET} Semgrep não pôde ser instalado. Etapa Semgrep será pulada.\n"
    return 0
}

bootstrap_python_repair() {
    printf "${_C_INFO}[BOOTSTRAP]${_C_RESET} Falha relacionada ao Python detectada. Reinstalando runtime + Semgrep...\n"
    bootstrap_python_install
}
