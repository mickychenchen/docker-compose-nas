# Docker Compose NAS (繁體中文指南)

[English](README.md) | **繁體中文**

在尋找理想的 NAS 解決方案後，本專案實現了一套基於 Docker 容器的極簡且強大的私有 NAS 系統。只要在一台乾淨的 Linux 主機上，即可建立包含資源搜尋、自動追劇/點片、WireGuard VPN 加密下載、媒體串流播放、Traefik 免費 SSL 憑證以及 Tailscale 異地安全內網存取的全功能 NAS 系統。

系統需求：支援 Docker 的 Linux 主機（如 Ubuntu Server 22.04/24.04, Debian, Oracle Linux, RHEL, CentOS 等），並安裝 Docker Engine 與 Docker Compose V2。

![Docker-Compose NAS Homepage](https://github.com/AdrienPoupa/docker-compose-nas/assets/15086425/3492a9f6-3779-49a5-b052-4193844f16f0)

---

## 目錄

- [Docker Compose NAS (繁體中文指南)](#docker-compose-nas-繁體中文指南)
  - [目錄](#目錄)
  - [收錄應用程式列表](#收錄應用程式列表)
  - [快速入門](#快速入門)
    - [選項 1：一鍵自動安裝嚮導 (推薦新手與 Oracle Cloud VPS)](#選項-1一鍵自動安裝嚮導-推薦新手與-oracle-cloud-vps)
    - [選項 2：手動部署](#選項-2手動部署)
  - [環境變數說明 (.env)](#環境變數說明-env)
  - [PIA WireGuard VPN 模組](#pia-wireguard-vpn-模組)
  - [Sonarr, Radarr 與 Lidarr 目錄結構](#sonarr-radarr-與-lidarr-目錄結構)
    - [硬連結 (Hardlinks) 目錄結構](#硬連結-hardlinks-目錄結構)
    - [下載客戶端關聯](#下載客戶端關聯)
  - [Prowlarr 索引管理](#prowlarr-索引管理)
  - [qBittorrent BT 下載](#qbittorrent-bt-下載)
  - [Jellyfin 媒體伺服器](#jellyfin-媒體伺服器)
  - [Homepage 總儀表板](#homepage-總儀表板)
  - [Seerr 點片系統](#seerr-點片系統)
  - [Traefik 逆向代理與 SSL 免費憑證](#traefik-逆向代理與-ssl-免費憑證)
    - [透過 Tailscale 實現安全異地連線](#透過-tailscale-實現安全異地連線)
  - [選配擴充服務 (Optional Services)](#選配擴充服務-optional-services)

---

## 收錄應用程式列表

| **應用程式** | **說明** | **Docker 鏡像** | **訪問網址** |
| :--- | :--- | :--- | :--- |
| [Sonarr](https://sonarr.tv) | 影集/電視劇自動追劇與下載管理 | `lscr.io/linuxserver/sonarr` | `/sonarr` |
| [Radarr](https://radarr.video) | 電影自動搜尋與下載管理 | `lscr.io/linuxserver/radarr` | `/radarr` |
| [Bazarr](https://www.bazarr.media/) | Sonarr/Radarr 字幕自動搜尋下載工具 | `lscr.io/linuxserver/bazarr` | `/bazarr` |
| [Prowlarr](https://github.com/Prowlarr/Prowlarr) | Tracker 索引器聚合管理工具 | `lscr.io/linuxserver/prowlarr:latest` | `/prowlarr` |
| [PIA WireGuard VPN](https://github.com/thrnz/docker-wireguard-pia) | 選配 - 使用 WireGuard 與 Port Forwarding 加密保護 qBittorrent 下載 | `ghcr.io/thrnz/docker-wireguard-pia:latest` | |
| [qBittorrent](https://www.qbittorrent.org) | 強大的 BT 下載客戶端（支援 VueTorrent WebUI） | `lscr.io/linuxserver/qbittorrent:libtorrentv1` | `/qbittorrent` |
| [Unpackerr](https://unpackerr.zip) | 下載完成自動解壓縮工具 | `ghcr.io/unpackerr/unpackerr` | |
| [Jellyfin](https://jellyfin.org) | 影音串流伺服器 (支援硬體解碼) | `lscr.io/linuxserver/jellyfin` | `/jellyfin` |
| [Seerr](https://seerr.dev/) | 媒體點片與推薦請求系統 | `ghcr.io/seerr-team/seerr:latest` | `$SEERR_HOSTNAME` |
| [Homepage](https://gethomepage.dev) | 美觀現代化的 NAS 個人總儀表板 | `ghcr.io/gethomepage/homepage` | `/` |
| [Traefik](https://traefik.io) | 逆向代理與自動 SSL 憑證管理 | `ghcr.io/traefik/traefik:3.7` | |
| [Watchtower](https://watchtower.nickfedor.com) | 自動更新 Docker 鏡像 | `ghcr.io/nicholas-fedor/watchtower` | |
| [Autoheal](https://github.com/willfarrell/docker-autoheal/) | 自動重啟不健康容器 | `willfarrell/autoheal` | |
| [Immich](https://immich.app) | 選配 - 私有極速相簿備份 (`COMPOSE_PROFILES=immich`) | `ghcr.io/immich-app/immich-server` | `/` |
| [Home Assistant](https://www.home-assistant.io) | 選配 - 智慧家庭控制中心 (`COMPOSE_PROFILES=homeassistant`) | `ghcr.io/home-assistant/home-assistant` | `/` |
| [AdGuard Home](https://adguard.com) | 選配 - 全家網路廣告攔截與 DNS 伺服器 (`COMPOSE_PROFILES=adguardhome`) | `adguard/adguardhome` | `dns.$BASE_HOSTNAME` |
| [Vaultwarden](https://github.com/dani-garcia/vaultwarden) | 選配 - 私有密碼管理器 (`COMPOSE_PROFILES=vaultwarden`) | `ghcr.io/dani-garcia/vaultwarden` | `/vaultwarden` |
| [Paperless Ngx](https://paperless-ngx.com) | 選配 - 無紙化文件檔案管理 (`COMPOSE_PROFILES=paperless`) | `ghcr.io/paperless-ngx/paperless-ngx` | `/paperless` |

---

## 快速入門

### 選項 1：一鍵自動安裝嚮導 (推薦新手與 Oracle Cloud VPS)

本專案提供針對 **Linux 初學者** 與 **Oracle Cloud (OCI) 主機** 優化的自動化嚮導腳本：

```bash
chmod +x install.sh
./install.sh
```

**本腳本將自動為您完成：**
1. **依賴環境自動安裝**：檢測並自動下載 Docker 與 Docker Compose V2。
2. **防火牆自動放行**：針對 Oracle Cloud (OCI) 及系統 `firewalld`/`iptables` 自動開放 HTTP 80 與 HTTPS 443 埠。
3. **Tailscale 整合**：一鍵安裝 Tailscale 異地安全內網，免暴露公網 Port 即可存取。
4. **Traefik + Cloudflare SSL 設定**：導引設定子域名與 Cloudflare DNS01 Challenge 自動申請免費 SSL 憑證。
5. **極簡 `.env` 配置**：智慧感應 IP、時區與 UID/GID，引導選配擴充服務。
6. **權限自動修正**：建立數據目錄並執行 `chown` 權限修復，避免權限不足報錯。
7. **一鍵啟動與金鑰填寫**：啟動容器並自動執行 `./update-config.sh` 填入 API 金鑰至 `.env`。

---

### 選項 2：手動部署

1. 複製設定檔範本：
   ```bash
   cp .env.example .env
   ```
2. 根據需求編輯 `.env` 中的變數（如 `DATA_ROOT`、`TIMEZONE` 等）。
3. 啟動容器服務：
   ```bash
   docker compose up -d
   ```
4. 第一次啟動完成後，執行設定更新腳本以擷取各服務 API Key 並更新 base URL：
   ```bash
   ./update-config.sh
   ```

---

## 環境變數說明 (.env)

| 變數名稱 | 說明 | 預設值 |
| :--- | :--- | :--- |
| `COMPOSE_FILE` | 載入的 Docker Compose 設定檔清單 | `docker-compose.yml:...` |
| `COMPOSE_PROFILES` | 啟用的選配擴充服務 (如 `immich,adguardhome`) | |
| `USER_ID` | Docker 容器使用的使用者 UID | `1000` |
| `GROUP_ID` | Docker 容器使用的群組 GID | `1000` |
| `TIMEZONE` | 容器時區設定 | `Asia/Taipei` |
| `CONFIG_ROOT` | 服務設定檔儲存宿主機路徑 | `.` |
| `DATA_ROOT` | 媒體數據與下載資料儲存根目錄 | `/mnt/data` |
| `DOWNLOAD_ROOT` | qBittorrent 下載儲存路徑 (需為 `DATA_ROOT` 子目錄) | `/mnt/data/torrents` |
| `BASE_HOSTNAME` | 基礎主機名稱/域名 (如 `yourdomain.com`) | `localhost` |
| `HOSTNAME` | NAS 完整子域名 (如 `nas.${BASE_HOSTNAME}`) | `nas.${BASE_HOSTNAME}` |
| `PIA_USER` | PIA VPN 帳號 (若使用 VPN 下載) | |
| `PIA_PASS` | PIA VPN 密碼 (若使用 VPN 下載) | |
| `DNS_CHALLENGE` | 是否啟用 Traefik DNS01 憑證挑戰 | `false` |
| `DNS_CHALLENGE_PROVIDER` | ACME DNS Challenge 提供商 | `cloudflare` |

---

## PIA WireGuard VPN 模組

本專案支援將 qBittorrent 的所有下載流量透過 [PIA WireGuard VPN](https://github.com/thrnz/docker-wireguard-pia) 進行加密與 Port Forwarding 轉發。

- 若要啟用 VPN 保護，請在安裝腳本中選擇啟用 PIA，或在 `COMPOSE_FILE` 中引入 `:vpn/docker-compose.yml` 並填寫 `PIA_USER` 與 `PIA_PASS`。
- 若無 PIA VPN 帳號，請維持不寫入 `vpn/docker-compose.yml`，系統將安全地暫停啟動 `vpn` 與 `qbittorrent`，避免未加密下載或連線失敗。

---

## Sonarr, Radarr 與 Lidarr 目錄結構

### 硬連結 (Hardlinks) 目錄結構

為了支援**硬連結 (Hardlinks)**（即下載完成移至媒體庫時瞬間完成且不佔用雙倍硬碟空間），qBittorrent 與 *arr 應用程式必須共享同一個掛載卷：

```
data
├── torrents (qBittorrent 下載目錄)
│   ├── movies
│   └── tv
└── media (Sonarr / Radarr 媒體庫)
    ├── movies (Radarr)
    └── tv (Sonarr)
```

在 Sonarr 與 Radarr 設定中：
- Sonarr 根目錄設為：`/data/media/tv`
- Radarr 根目錄設為：`/data/media/movies`

---

## Traefik 逆向代理與 SSL 免費憑證

Traefik 預設監聽 80 與 443 埠，透過 Cloudflare DNS01 Challenge 自動向 Let's Encrypt 申請 SSL 免費憑證。

若您使用 Cloudflare 管理域名：
1. 將 Cloudflare API Token 填入 `.env` 的 `CLOUDFLARE_DNS_API_TOKEN` 與 `CLOUDFLARE_ZONE_API_TOKEN`。
2. 將 DNS `A` 紀錄指向主機公網 IP 或 Tailscale IP。
3. Traefik 將自動全自動獲取並更新 HTTPS 證書。

---

### 透過 Tailscale 實現安全異地連線

若不想公開開放 Port 到公網，推薦搭配 [Tailscale](https://tailscale.com)：
1. 執行 `./install.sh` 並同意安裝 Tailscale。
2. 執行 `sudo tailscale up` 登入並綁定您的裝置。
3. 將域名的 `A` 紀錄指向 Tailscale 賦予的 IP（如 `100.x.x.x`）。
4. 即可在世界上任何地方連線 Tailscale 並使用包含 SSL 憑證的自訂域名安全存取 NAS！
