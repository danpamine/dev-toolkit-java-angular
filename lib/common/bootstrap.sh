#!/usr/bin/env bash
# ==============================================================================
# bootstrap.sh - Download e Instalação de Binários a partir do GitHub Releases
# ==============================================================================

_bootstrap_get_installed_version() {
    local target_bin="$1"
    local version_file="${target_bin}.version"
    if [[ -f "$version_file" ]]; then
        cat "$version_file" 2>/dev/null | tr -d '\r\n'
    else
        echo ""
    fi
}

_bootstrap_download_latest() {
    local repo="$1"
    local asset_pattern="$2"
    local dest_path="$3"
    local friendly_name="$4"

    local current_tag
    current_tag="$(_bootstrap_get_installed_version "$dest_path")"

    local auth_header=()
    if [[ -n "${GITHUB_TOKEN:-}" ]]; then
        auth_header=("-H" "Authorization: Bearer $GITHUB_TOKEN")
    elif [[ -n "${GH_TOKEN:-}" ]]; then
        auth_header=("-H" "Authorization: Bearer $GH_TOKEN")
    fi

    local version_tag=""
    local download_url=""
    # 1. API oficial do GitHub
    local api_url="https://api.github.com/repos/${repo}/releases/latest"
    local release_info
    release_info="$(curl -sL --ssl-no-revoke --connect-timeout 4 --max-time 8 "${auth_header[@]}" "$api_url" 2>/dev/null)"
    if [[ -n "$release_info" ]] && ! echo "$release_info" | grep -q '"message":'; then
        version_tag="$(echo "$release_info" | grep -oE '"tag_name"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed -E 's/.*"tag_name"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/')"
        download_url="$(echo "$release_info" | grep -oE '"browser_download_url"[[:space:]]*:[[:space:]]*"[^"]*"' | grep -iE "$asset_pattern" | head -1 | sed -E 's/.*"browser_download_url"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/')"
    fi
    # 2. Scraper web de contingência (imune a Rate Limit)
    if [[ -z "$download_url" ]]; then
        local effective_url
        effective_url="$(curl -sIL --ssl-no-revoke --connect-timeout 4 --max-time 8 -o /dev/null -w '%{url_effective}' "https://github.com/${repo}/releases/latest" 2>/dev/null)"
        local web_tag="${effective_url##*/}"
        web_tag="$(echo "$web_tag" | tr -d '\r\n')"
        if [[ -n "$web_tag" && "$web_tag" != "latest" ]]; then
            version_tag="$web_tag"
            local asset_path
            asset_path="$(curl -sL --ssl-no-revoke --connect-timeout 4 --max-time 10 "https://github.com/${repo}/releases/expanded_assets/${web_tag}" 2>/dev/null | grep -oE "href=\"/${repo}/releases/download/${web_tag}/[^\"]+\"" | grep -iE "$asset_pattern" | head -1 | sed 's/href="//;s/"//')"
            [[ -n "$asset_path" ]] && download_url="https://github.com${asset_path}"
        fi
    fi
    # Fallback para Google Java Format
    if [[ -z "$download_url" && "$repo" == "google/google-java-format" && -n "$version_tag" ]]; then
        local clean_tag="${version_tag#v}"
        download_url="https://github.com/google/google-java-format/releases/download/${version_tag}/google-java-format-${clean_tag}-all-deps.jar"
    fi
    if [[ -f "$dest_path" ]]; then
        if [[ -z "$version_tag" || "$current_tag" == "$version_tag" ]]; then
            printf "${_C_SUCCESS}[BOOTSTRAP]${_C_RESET} %s %s: OK (atualizado)\n" "$friendly_name" "${current_tag:-local}"
            return 0
        fi
    fi
    if [[ -z "$download_url" ]]; then
        if [[ -f "$dest_path" ]]; then
            printf "${_C_SUCCESS}[BOOTSTRAP]${_C_RESET} %s %s: OK (usando versão local)\n" "$friendly_name" "${current_tag:-instalado}"
            return 0
        fi
        printf "${_C_ERROR}[BOOTSTRAP] Não foi possível obter download de %s (Rate Limit de rede)${_C_RESET}\n" "$friendly_name"
        return 1
    fi
    printf "${_C_INFO}[BOOTSTRAP]${_C_RESET} Baixando/Atualizando %s (%s)...\n" "$friendly_name" "$version_tag"
    local tmp_dir
    tmp_dir="$(mktemp -d 2>/dev/null || echo "/tmp/bt_${RANDOM}")"
    mkdir -p "$tmp_dir"
    local tmp_file="${tmp_dir}/pkg"
    if ! curl -sL --ssl-no-revoke --connect-timeout 10 --max-time 90 "$download_url" -o "$tmp_file" 2>/dev/null; then
        rm -rf "$tmp_dir"
        [[ -f "$dest_path" ]] && return 0
        return 1
    fi
    mkdir -p "$(dirname "$dest_path")"
    case "$download_url" in
        *.zip)
            local extract_dir="${tmp_dir}/extracted"
            mkdir -p "$extract_dir"
            unzip -o -q "$tmp_file" -d "$extract_dir" 2>/dev/null
            local binary
            binary="$(find "$extract_dir" -type f \( -name "$(basename "$dest_path")" -o -name "*.exe" \) 2>/dev/null | head -1)"
            if [[ -n "$binary" ]]; then
                cp "$binary" "$dest_path"
                chmod +x "$dest_path"
            fi
            ;;
        *.tar.gz|*.tgz)
            tar -xzf "$tmp_file" -C "$tmp_dir" 2>/dev/null
            local binary
            binary="$(find "$tmp_dir" -type f \( -name "$(basename "$dest_path")" -o -name "*.exe" \) 2>/dev/null | head -1)"
            if [[ -n "$binary" ]]; then
                cp "$binary" "$dest_path"
                chmod +x "$dest_path"
            fi
            ;;
        *)
            cp "$tmp_file" "$dest_path"
            chmod +x "$dest_path"
            ;;
    esac
    rm -rf "$tmp_dir"
    if [[ -f "$dest_path" ]]; then
        echo "$version_tag" > "${dest_path}.version" 2>/dev/null || true
        local win_path
        win_path="$(cygpath -w "$dest_path" 2>/dev/null || echo "$dest_path")"
        powershell -Command "Unblock-File -LiteralPath '$win_path'" 2>/dev/null || true
        printf "${_C_SUCCESS}[BOOTSTRAP]${_C_RESET} %s atualizado com sucesso (%s)\n" "$friendly_name" "$version_tag"
        return 0
    fi
    return 1
}
