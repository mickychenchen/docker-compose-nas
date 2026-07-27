#!/usr/bin/env bash

# ==============================================================================
# Docker Compose NAS - 一鍵自動安裝與設定腳本 (針對 Linux 小白 & Oracle Cloud TA)
# ==============================================================================

set -e

# 定義顏色輸出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# 標題列
print_banner() {
    clear
    echo -e "${CYAN}================================================================${NC}"
    echo -e "${PURPLE}         🐳 Docker Compose NAS 一鍵自動安裝與嚮導 🚀         ${NC}"
    echo -e "${CYAN}================================================================${NC}"
    echo -e "${YELLOW}本腳本專為 Linux 初學者與 Oracle Cloud (OCI) 使用者設計，自動完成依賴安裝、${NC}"
    echo -e "${YELLOW}防火牆放行、Tailscale 整合、Traefik SSL 憑證、設定檔與權限建立。${NC}"
    echo -e "${CYAN}----------------------------------------------------------------${NC}"
    echo ""
}

log_info() {
    echo -e "${BLUE}[資訊]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[成功]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[警告]${NC} $1"
}

log_error() {
    echo -e "${RED}[錯誤]${NC} $1"
}

set_env_var() {
    local key="$1"
    local val="$2"
    local file="${3:-.env}"
    if grep -q "^${key}=" "$file" 2>/dev/null; then
        local escaped_val=$(printf '%s\n' "$val" | sed -e 's/[\/&]/\\&/g')
        sed -i "s|^${key}=.*|${key}=${escaped_val}|" "$file"
    else
        echo "${key}=${val}" >> "$file"
    fi
}


# 1. 檢查權限與基本用戶
check_user() {
    REAL_USER="${SUDO_USER:-$USER}"
    if [ "$REAL_USER" = "root" ]; then
        REAL_UID=1000
        REAL_GID=1000
    else
        REAL_UID=$(id -u "$REAL_USER" 2>/dev/null || echo 1000)
        REAL_GID=$(id -g "$REAL_USER" 2>/dev/null || echo 1000)
    fi
    log_info "當前執行使用者: ${REAL_USER} (UID: ${REAL_UID}, GID: ${REAL_GID})"
}

# 2. 檢查與安裝依賴套件
check_dependencies() {
    log_info "正在檢查基本系統工具 (curl, git, jq, sed, grep)..."
    MISSING_PKGS=()
    for pkg in curl git jq sed grep; do
        if ! command -v "$pkg" &>/dev/null; then
            MISSING_PKGS+=("$pkg")
        fi
    done

    if [ ${#MISSING_PKGS[@]} -ne 0 ]; then
        log_warning "缺少以下必要工具: ${MISSING_PKGS[*]}"
        log_info "正在嘗試自動安裝..."
        if command -v apt-get &>/dev/null; then
            sudo apt-get update -qq && sudo apt-get install -y -qq "${MISSING_PKGS[@]}"
        elif command -v dnf &>/dev/null; then
            sudo dnf install -y "${MISSING_PKGS[@]}"
        elif command -v yum &>/dev/null; then
            sudo yum install -y "${MISSING_PKGS[@]}"
        elif command -v pacman &>/dev/null; then
            sudo pacman -Sy --noconfirm "${MISSING_PKGS[@]}"
        else
            log_error "無法自動識別包管理器，請手動安裝: ${MISSING_PKGS[*]}"
            exit 1
        fi
    fi
    log_success "基本系統工具檢查完成！"
}

# 3. 檢查與開放防火牆 (針對 Oracle Cloud OCI 防火牆封鎖 80/443 的問題)
check_oci_firewall() {
    log_info "正在檢查並放行系統防火牆埠號 (HTTP 80 / HTTPS 443)..."
    
    # 1. 處理 firewalld (如 Oracle Linux / RHEL / CentOS)
    if command -v firewall-cmd &>/dev/null && systemctl is-active firewalld &>/dev/null; then
        log_info "檢測到 firewalld 服務正在運作，正在開放 80/443 埠..."
        sudo firewall-cmd --permanent --add-port=80/tcp 2>/dev/null || true
        sudo firewall-cmd --permanent --add-port=443/tcp 2>/dev/null || true
        sudo firewall-cmd --reload 2>/dev/null || true
    fi

    # 2. 處理 iptables (如 Oracle Cloud Ubuntu 預設防火牆)
    if command -v iptables &>/dev/null; then
        sudo iptables -I INPUT -p tcp --dport 80 -j ACCEPT 2>/dev/null || true
        sudo iptables -I INPUT -p tcp --dport 443 -j ACCEPT 2>/dev/null || true
        
        if command -v netfilter-persistent &>/dev/null; then
            sudo netfilter-persistent save 2>/dev/null || true
        elif [ -f /etc/redhat-release ] && command -v service &>/dev/null; then
            sudo service iptables save 2>/dev/null || true
        fi
    fi
    log_success "防火牆 80/443 埠放行處置完成！"
}

# 4. 檢查與自動安裝 Docker & Docker Compose
check_docker() {
    log_info "正在檢查 Docker 與 Docker Compose V2 環境..."
    if ! command -v docker &>/dev/null; then
        log_info "未檢測到 Docker 環境，正在自動下載並安裝官方 Docker 套件..."
        curl -fsSL https://get.docker.com | sh
        
        log_info "啟動 Docker 服務並設定開機自啟..."
        sudo systemctl enable --now docker 2>/dev/null || sudo service docker start 2>/dev/null || true

        if [ -n "$REAL_USER" ] && [ "$REAL_USER" != "root" ]; then
            log_info "將使用者 ${REAL_USER} 加入 docker 用戶組..."
            sudo usermod -aG docker "$REAL_USER" || true
        fi
        log_success "Docker 安裝完成！"
    fi

    # 自動判定調用 docker 還是 sudo docker
    if docker info &>/dev/null && docker compose version &>/dev/null; then
        DOCKER_CMD="docker"
    elif sudo docker info &>/dev/null && sudo docker compose version &>/dev/null; then
        DOCKER_CMD="sudo docker"
        log_info "備註：當前使用者權限尚未重新載入 docker 群組，本次安裝將自動透過 sudo docker 執行。"
    else
        log_error "無法連線至 Docker Daemon 或未檢測到 Docker Compose V2。請確認 Docker 服務已啟動。"
        exit 1
    fi
    export DOCKER_CMD
    log_success "Docker 運作正常 (權限判定: ${DOCKER_CMD})"
}

# 5. Tailscale 異地安全內網連線整合 (直接自動安裝與連線)
setup_tailscale() {
    log_info "正在檢查 Tailscale 異地安全內網連線環境..."
    if ! command -v tailscale &>/dev/null; then
        log_info "正在自動下載並安裝 Tailscale 官方套件..."
        curl -fsSL https://tailscale.com/install.sh | sh
        sudo systemctl enable --now tailscaled 2>/dev/null || sudo service tailscaled start 2>/dev/null || true
        log_success "Tailscale 安裝完成！"
    else
        log_success "系統已安裝 Tailscale！"
    fi

    # 檢測連線狀態
    TAILSCALE_IP=$(tailscale ip -4 2>/dev/null || echo "")
    if [ -n "$TAILSCALE_IP" ]; then
        log_success "Tailscale 連線正常，您的 Tailscale IP 為: ${GREEN}${TAILSCALE_IP}${NC}"
    else
        log_info "正在自動啟動 Tailscale 登入綁定 (請點擊終端顯示的網址完成登入)..."
        sudo tailscale up || log_warning "Tailscale 登入已跳過，您稍後可隨時手動執行 sudo tailscale up"
        TAILSCALE_IP=$(tailscale ip -4 2>/dev/null || echo "")
    fi
}

# 6. 配置嚮導 (.env 配置)
configure_env() {
    log_info "開始進行專案設定嚮導 (.env)..."
    
    if [ -f .env ]; then
        echo -n -e "${YELLOW}偵測到已存在的 .env 檔案。是否重新進行設定？[y/N]: ${NC}"
        read -r reconfig_choice
        if [[ ! "$reconfig_choice" =~ ^[Yy]$ ]]; then
            log_info "保持原有 .env 設定檔不變。"
            return 0
        fi
        cp .env .env.bak.$(date +%s)
        log_info "已將舊的 .env 備份。"
    fi

    if [ -f .env.example ]; then
        cp .env.example .env
    else
        log_error "找不到 .env.example 模板檔案！"
        exit 1
    fi

    # 自動感應預設值
    DETECTED_IP=$(ip route get 1.1.1.1 2>/dev/null | grep -oP 'src \K\S+' || hostname -I 2>/dev/null | awk '{print $1}')
    DETECTED_IP=${DETECTED_IP:-"localhost"}

    # 自動感應主機域名或回退至 IP
    DETECTED_DOMAIN=$(hostname -f 2>/dev/null || hostname 2>/dev/null || echo "")
    if [[ -z "$DETECTED_DOMAIN" ]] || [[ "$DETECTED_DOMAIN" == "localhost"* ]]; then
        DETECTED_DOMAIN="$DETECTED_IP"
    fi

    # 優先嘗試透過 GeoIP 自動檢測實體所在地時區
    DETECTED_TZ=""
    GEO_TZ=$(curl -s --max-time 2 http://ip-api.com/line/?fields=timezone 2>/dev/null || curl -s --max-time 2 https://ipapi.co/timezone 2>/dev/null || true)
    if [ -n "$GEO_TZ" ] && [[ "$GEO_TZ" =~ ^[A-Za-z0-9_]+/[A-Za-z0-9_]+$ ]]; then
        DETECTED_TZ="$GEO_TZ"
    fi

    if [ -z "$DETECTED_TZ" ]; then
        if [ -f /etc/timezone ]; then
            DETECTED_TZ=$(cat /etc/timezone 2>/dev/null)
        elif command -v timedatectl &>/dev/null; then
            DETECTED_TZ=$(timedatectl show --property=Timezone --value 2>/dev/null)
        elif [ -L /etc/localtime ]; then
            DETECTED_TZ=$(readlink -f /etc/localtime 2>/dev/null | sed 's|.*/zoneinfo/||')
        fi
    fi
    DETECTED_TZ=${DETECTED_TZ:-"Asia/Taipei"}

    # 自動選擇預設數據目錄
    if [ -d "/home/${REAL_USER}" ]; then
        DEFAULT_DATA_ROOT="/home/${REAL_USER}/data"
    elif [ -d "/home/ubuntu" ]; then
        DEFAULT_DATA_ROOT="/home/ubuntu/data"
    else
        DEFAULT_DATA_ROOT="/root/data"
    fi

    echo ""
    echo -e "${CYAN}--- 步驟 1/4: 基本域名設定 ---${NC}"
    echo -n -e "請輸入主機基礎域名或 IP [預設: ${GREEN}${DETECTED_DOMAIN}${NC}]: "
    read -r user_hostname
    user_hostname=${user_hostname:-$DETECTED_DOMAIN}

    set_env_var "BASE_HOSTNAME" "$user_hostname"
    set_env_var "HOSTNAME" 'nas.${BASE_HOSTNAME}'
    set_env_var "TIMEZONE" "$DETECTED_TZ"
    set_env_var "USER_ID" "$REAL_UID"
    set_env_var "GROUP_ID" "$REAL_GID"
    set_env_var "DATA_ROOT" "$DEFAULT_DATA_ROOT"
    set_env_var "DOWNLOAD_ROOT" "${DEFAULT_DATA_ROOT}/torrents"
    set_env_var "IMMICH_UPLOAD_LOCATION" "${DEFAULT_DATA_ROOT}/photos"
    set_env_var "CONFIG_ROOT" "."

    echo ""
    echo -e "${CYAN}--- 步驟 2/4: Traefik 網域與 SSL 憑證 (Cloudflare DNS Challenge) ---${NC}"
    echo -n -e "是否要配置 SSL 憑證與 Cloudflare DNS 自動憑證？[y/N]: "
    read -r enable_ssl
    if [[ "$enable_ssl" =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}💡 提示：請前往 Cloudflare 申請 API Token: https://dash.cloudflare.com/profile/api-tokens${NC}"
        echo -n -e "請輸入 Let's Encrypt 通知 Email: "
        read -r user_le_email
        echo -n -e "請輸入 Cloudflare 帳號 Email: "
        read -r user_cf_email
        echo -n -e "請輸入 Cloudflare DNS API Token: "
        read -r user_cf_dns_token
        echo -n -e "請輸入 Cloudflare Zone API Token (同上可直接 Enter): "
        read -r user_cf_zone_token
        user_cf_zone_token=${user_cf_zone_token:-$user_cf_dns_token}

        user_domain=$(echo "$user_hostname" | sed -E 's/^nas\.//i')

        set_env_var "BASE_HOSTNAME" "$user_domain"
        set_env_var "HOSTNAME" 'nas.${BASE_HOSTNAME}'
        set_env_var "SEERR_HOSTNAME" 'seerr.${BASE_HOSTNAME}'
        set_env_var "DNS_CHALLENGE" "true"
        set_env_var "DNS_CHALLENGE_PROVIDER" "cloudflare"
        set_env_var "LETS_ENCRYPT_EMAIL" "$user_le_email"
        set_env_var "CLOUDFLARE_EMAIL" "$user_cf_email"
        set_env_var "CLOUDFLARE_DNS_API_TOKEN" "$user_cf_dns_token"
        set_env_var "CLOUDFLARE_ZONE_API_TOKEN" "$user_cf_zone_token"
        log_success "Cloudflare SSL 自動憑證配置完畢！"
    else
        set_env_var "DNS_CHALLENGE" "false"
        set_env_var "DNS_CHALLENGE_PROVIDER" "cloudflare"
        set_env_var "SEERR_HOSTNAME" 'seerr.${BASE_HOSTNAME}'
    fi

    echo ""
    echo -e "${CYAN}--- 步驟 3/4: PIA WireGuard VPN 設定 ---${NC}"
    echo -n -e "您是否有 Private Internet Access (PIA) VPN 帳號？[y/N]: "
    read -r has_pia
    if [[ "$has_pia" =~ ^[Yy]$ ]]; then
        echo -n -e "請輸入 PIA 用戶名 (PIA Username): "
        read -r pia_user
        echo -n -e "請輸入 PIA 密碼 (PIA Password): "
        read -r pia_pass
        echo -n -e "請輸入 PIA 伺服器位置 [預設: ${GREEN}ca${NC}]: "
        read -r pia_loc
        pia_loc=${pia_loc:-"ca"}

        set_env_var "PIA_USER" "$pia_user"
        set_env_var "PIA_PASS" "$pia_pass"
        set_env_var "PIA_LOCATION" "$pia_loc"

        CURRENT_PROFILES=$(grep "^COMPOSE_PROFILES=" .env 2>/dev/null | cut -d'=' -f2- | tr -d '"')
        if [[ ! "$CURRENT_PROFILES" =~ "vpn" ]]; then
            if [ -n "$CURRENT_PROFILES" ]; then
                set_env_var "COMPOSE_PROFILES" "${CURRENT_PROFILES},vpn"
            else
                set_env_var "COMPOSE_PROFILES" "vpn"
            fi
        fi
        log_success "已啟用 PIA WireGuard VPN，將同時啟動 VPN 與 qBittorrent 加密下載。"
    else
        set_env_var "PIA_USER" ""
        set_env_var "PIA_PASS" ""

        CURRENT_PROFILES=$(grep "^COMPOSE_PROFILES=" .env 2>/dev/null | cut -d'=' -f2- | tr -d '"')
        NEW_PROFILES=$(echo "$CURRENT_PROFILES" | sed -E 's/(^|,)vpn($|,)/\1\2/g' | sed -E 's/^,|,$//g' | sed 's/,,/,/g')
        set_env_var "COMPOSE_PROFILES" "$NEW_PROFILES"
        log_info "未啟用 PIA VPN：系統將關閉 VPN 與 qBittorrent 下載器。"
    fi

    echo ""
    echo -e "${CYAN}--- 步驟 4/4: 選配擴充服務 (Profiles) ---${NC}"
    echo "預設啟動基礎媒體庫：Sonarr, Radarr, Bazarr, Prowlarr, Jellyfin, Homepage, Seerr"
    echo -n -e "是否要挑選並啟用其他擴充服務？[y/N]: "
    read -r enable_profiles
    if [[ "$enable_profiles" =~ ^[Yy]$ ]]; then
        echo ""
        echo "請選擇要啟用的擴充服務 (可多選，輸入數字並以逗號分隔，例如 1,3,4):"
        echo " 1) Immich (相簿備份管理)"
        echo " 2) Home Assistant (智慧家庭控制)"
        echo " 3) AdGuard Home (全家網路廣告攔截)"
        echo " 4) Vaultwarden (私有密碼管理器)"
        echo " 5) Paperless Ngx (無紙化文件管理)"
        echo " 6) FlareSolverr (繞過 Cloudflare 驗證)"
        echo " 7) Tandoor (智慧食譜管理)"
        echo " 8) Joplin (雲端筆記)"
        echo " 9) Calibre-Web (電子書庫)"
        echo "10) Lidarr (音樂下載管理)"
        echo "11) SABnzbd (Usenet 下載器)"
        echo "12) Cleanuparr (媒體自動清理)"
        echo "13) Cross-Seed (自動跨站補種)"
        echo "14) Autobrr (自動搶種)"
        echo "15) Suggestarr (媒體建議推薦)"
        echo "16) PIA VPN & qBittorrent (WireGuard 加密 BT 下載器)"
        echo "17) 全部啟用 (All)"
        echo -n -e "請選擇數字 [預設不加選]: "
        read -r profile_choices

        SELECTED_PROFILES=()
        if [ "$profile_choices" = "17" ] || [ "$profile_choices" = "all" ]; then
            SELECTED_PROFILES=("immich" "homeassistant" "adguardhome" "vaultwarden" "paperless" "flaresolverr" "tandoor" "joplin" "calibre-web" "lidarr" "sabnzbd" "cleanuparr" "cross-seed" "autobrr" "suggestarr" "vpn")
        else
            IFS=',' read -ra ADDR <<< "$profile_choices"
            for choice in "${ADDR[@]}"; do
                choice=$(echo "$choice" | tr -d ' ')
                case "$choice" in
                    1) SELECTED_PROFILES+=("immich") ;;
                    2) SELECTED_PROFILES+=("homeassistant") ;;
                    3) SELECTED_PROFILES+=("adguardhome") ;;
                    4) SELECTED_PROFILES+=("vaultwarden") ;;
                    5) SELECTED_PROFILES+=("paperless") ;;
                    6) SELECTED_PROFILES+=("flaresolverr") ;;
                    7) SELECTED_PROFILES+=("tandoor") ;;
                    8) SELECTED_PROFILES+=("joplin") ;;
                    9) SELECTED_PROFILES+=("calibre-web") ;;
                    10) SELECTED_PROFILES+=("lidarr") ;;
                    11) SELECTED_PROFILES+=("sabnzbd") ;;
                    12) SELECTED_PROFILES+=("cleanuparr") ;;
                    13) SELECTED_PROFILES+=("cross-seed") ;;
                    14) SELECTED_PROFILES+=("autobrr") ;;
                    15) SELECTED_PROFILES+=("suggestarr") ;;
                    16) SELECTED_PROFILES+=("vpn") ;;
                esac
            done
        fi

        PROFILES_STR=""
        if [ ${#SELECTED_PROFILES[@]} -gt 0 ]; then
            PROFILES_STR=$(IFS=','; echo "${SELECTED_PROFILES[*]}")
            log_success "已選取擴充服務: ${PROFILES_STR}"
        fi
        set_env_var "COMPOSE_PROFILES" "$PROFILES_STR"

        if [[ "$PROFILES_STR" =~ "adguardhome" ]]; then
            log_info "檢測到啟用了 AdGuard Home，正在自動釋放 systemd-resolved 53 埠佔用..."
            sudo mkdir -p /etc/systemd/resolved.conf.d/
            echo -e "[Resolve]\nDNSStubListener=no" | sudo tee /etc/systemd/resolved.conf.d/adguardhome.conf > /dev/null
            sudo systemctl restart systemd-resolved 2>/dev/null || true
        fi
    else
        HAS_VPN=$(grep "^COMPOSE_PROFILES=" .env 2>/dev/null | grep -q "vpn" && echo "vpn" || echo "")
        set_env_var "COMPOSE_PROFILES" "$HAS_VPN"
    fi

    log_success ".env 設定嚮導完成！"
}

# 7. 建立儲存目錄與修正權限
setup_directories() {
    log_info "正在自動建立所需目錄與權限管理..."

    DATA_ROOT_PATH=$(grep "^DATA_ROOT=" .env | cut -d'=' -f2- | tr -d '"')
    DOWNLOAD_ROOT_PATH=$(grep "^DOWNLOAD_ROOT=" .env | cut -d'=' -f2- | tr -d '"')
    IMMICH_PATH=$(grep "^IMMICH_UPLOAD_LOCATION=" .env | cut -d'=' -f2- | tr -d '"')
    CONFIG_ROOT_PATH=$(grep "^CONFIG_ROOT=" .env | cut -d'=' -f2- | tr -d '"')

    DATA_ROOT_PATH=${DATA_ROOT_PATH:-"/mnt/data"}
    DOWNLOAD_ROOT_PATH=${DOWNLOAD_ROOT_PATH:-"${DATA_ROOT_PATH}/torrents"}
    IMMICH_PATH=${IMMICH_PATH:-"${DATA_ROOT_PATH}/photos"}
    CONFIG_ROOT_PATH=${CONFIG_ROOT_PATH:-"."}

    log_info "創建數據與下載目錄: ${DATA_ROOT_PATH}, ${DOWNLOAD_ROOT_PATH}"
    sudo mkdir -p "$DATA_ROOT_PATH" "$DOWNLOAD_ROOT_PATH" "$IMMICH_PATH"
    sudo mkdir -p "${DATA_ROOT_PATH}/media/tv" "${DATA_ROOT_PATH}/media/movies" "${DATA_ROOT_PATH}/media/music"

    log_info "創建 config 子目錄與修正權限..."
    for dir in letsencrypt sonarr radarr lidarr bazarr seerr prowlarr qbittorrent pia pia-shared immich homeassistant adguardhome tandoor joplin vaultwarden paperless autobrr suggestarr cross-seed cleanuparr homepage jellyfin calibre-web flaresolverr privoxy; do
        sudo mkdir -p "${CONFIG_ROOT_PATH}/${dir}"
        sudo chown -R "${REAL_UID}:${REAL_GID}" "${CONFIG_ROOT_PATH}/${dir}" 2>/dev/null || true
    done

    log_info "為數據目錄設置權限屬性 (UID: ${REAL_UID}, GID: ${REAL_GID})..."
    sudo chown -R "${REAL_UID}:${REAL_GID}" "$DATA_ROOT_PATH" 2>/dev/null || true

    log_success "目錄建置與權限設定完畢！"
}

# 8. 啟動服務與自動更新配置
start_services() {
    log_info "正在啟動 Docker 容器服務 stack (${DOCKER_CMD} compose up -d)..."
    $DOCKER_CMD compose up -d

    log_info "等待容器初始化 (約 15 秒)..."
    sleep 15

    log_info "執行配置與 API Key 自動擷取程式 (update-config.sh)..."
    if [ -f "./update-config.sh" ]; then
        chmod +x ./update-config.sh
        DOCKER_CMD="$DOCKER_CMD" ./update-config.sh || log_warning "update-config.sh 執行期間有小警告，容器將保持運作。"
    fi

    log_success "所有服務啟動與配置完成！"
}

# 9. 安裝完成儀表板展示
show_completion() {
    BASE_HOST=$(grep "^BASE_HOSTNAME=" .env 2>/dev/null | cut -d'=' -f2- | tr -d '"')
    RAW_HOSTNAME=$(grep "^HOSTNAME=" .env 2>/dev/null | cut -d'=' -f2- | tr -d '"')
    RAW_SEERR=$(grep "^SEERR_HOSTNAME=" .env 2>/dev/null | cut -d'=' -f2- | tr -d '"')

    if [ -n "$BASE_HOST" ]; then
        SERVER_IP=$(echo "$RAW_HOSTNAME" | sed "s/\${BASE_HOSTNAME}/$BASE_HOST/g")
        SEERR_DOMAIN=$(echo "$RAW_SEERR" | sed "s/\${BASE_HOSTNAME}/$BASE_HOST/g")
    else
        SERVER_IP=${RAW_HOSTNAME:-"localhost"}
        SEERR_DOMAIN=${RAW_SEERR:-"seerr.localhost"}
    fi
    SERVER_IP=${SERVER_IP:-"localhost"}
    SEERR_DOMAIN=${SEERR_DOMAIN:-"seerr.${SERVER_IP}"}
    TS_IP=$(tailscale ip -4 2>/dev/null || echo "")

    echo ""
    echo -e "${GREEN}================================================================${NC}"
    echo -e "${GREEN}   🎉 恭喜！Docker Compose NAS 已經在 Oracle/Linux 上成功安裝！   ${NC}"
    echo -e "${GREEN}================================================================${NC}"
    echo ""
    if [ -n "$TS_IP" ]; then
        echo -e "${CYAN}🔒 Tailscale 安全異地連線 IP: ${GREEN}${TS_IP}${NC}"
    fi
    echo -e "${CYAN}📌 常用服務訪問網址：${NC}"
    echo -e "  🌐 總儀表板 (Homepage) : ${YELLOW}http://${SERVER_IP}/${NC}"
    echo -e "  🎬 影音管理 (Jellyfin) : ${YELLOW}http://${SERVER_IP}/jellyfin${NC}"
    echo -e "  📺 影集追劇 (Sonarr)   : ${YELLOW}http://${SERVER_IP}/sonarr${NC}"
    echo -e "  🎥 電影管理 (Radarr)   : ${YELLOW}http://${SERVER_IP}/radarr${NC}"
    echo -e "  💬 字幕下載 (Bazarr)   : ${YELLOW}http://${SERVER_IP}/bazarr${NC}"
    echo -e "  🔍 索引聚合 (Prowlarr) : ${YELLOW}http://${SERVER_IP}/prowlarr${NC}"
    echo -e "  ⬇️  BT 下載器 (qBittorrent): ${YELLOW}http://${SERVER_IP}/qbittorrent${NC}"
    echo -e "      └ (帳號: ${GREEN}admin${NC} / 預設密碼: ${GREEN}adminadmin${NC})"
    echo -e "  🍿 點片系統 (Seerr)    : ${YELLOW}http://${SEERR_DOMAIN}/${NC}"
    echo ""
    echo -e "${CYAN}💡 Tailscale & 網域解析說明：${NC}"
    echo -e "  • 若使用 Tailscale 異地連線，建議在 Cloudflare 將 ${YELLOW}${SERVER_IP}${NC} 的 A 紀錄指向 ${GREEN}${TS_IP:-"您的 Tailscale IP"}${NC}"
    echo -e "  • 如此即可在無須暴露公網 Port 的情況下，透過自訂子域名與 SSL 憑證安全存取 NAS！"
    echo ""
    echo -e "${CYAN}🛠️  常用管理指令：${NC}"
    echo -e "  • 查看容器運作狀態 : ${YELLOW}${DOCKER_CMD} compose ps${NC}"
    echo -e "  • 查看容器日誌訊息 : ${YELLOW}${DOCKER_CMD} compose logs -f${NC}"
    echo -e "  • 重新啟動所有服務 : ${YELLOW}${DOCKER_CMD} compose restart${NC}"
    echo -e "  • 停止所有服務     : ${YELLOW}${DOCKER_CMD} compose down${NC}"
    echo ""
    echo -e "${CYAN}================================================================${NC}"
}

# 主執行流程
main() {
    print_banner
    check_user
    check_dependencies
    check_oci_firewall
    check_docker
    setup_tailscale
    configure_env
    setup_directories
    start_services
    show_completion
}

main "$@"
