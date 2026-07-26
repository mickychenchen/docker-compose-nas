#!/bin/bash

DOCKER_CMD="${DOCKER_CMD:-docker}"
if ! $DOCKER_CMD info &>/dev/null && command -v sudo &>/dev/null && sudo docker info &>/dev/null; then
    DOCKER_CMD="sudo docker"
fi

wait_for_file() {
    local file="$1"
    local timeout="${2:-30}"
    local count=0
    echo "Waiting for ${file}..."
    while [ ! -f "$file" ]; do
        if [ "$count" -ge "$timeout" ]; then
            echo "Warning: Timeout waiting for ${file}"
            return 1
        fi
        sleep 1
        count=$((count + 1))
    done
    return 0
}

function update_arr_config {
  echo "Updating ${container} configuration..."
  local conf_file="${CONFIG_ROOT:-.}"/"$container"/config.xml
  if ! wait_for_file "$conf_file" 30; then
      echo "Skipping ${container} update due to missing config file."
      return 0
  fi
  sed -i.bak "s/<UrlBase><\/UrlBase>/<UrlBase>\/$1<\/UrlBase>/" "$conf_file" && rm -f "${conf_file}.bak"
  CONTAINER_NAME_UPPER=$(echo "$container" | tr '[:lower:]' '[:upper:]')
  local api_key=$(sed -n 's/.*<ApiKey>\(.*\)<\/ApiKey>.*/\1/p' "$conf_file")
  if [ -n "$api_key" ]; then
      sed -i.bak 's/^'"${CONTAINER_NAME_UPPER}"'_API_KEY=.*/'"${CONTAINER_NAME_UPPER}"'_API_KEY='"${api_key}"'/' .env && rm -f .env.bak
  fi
  echo "Update of ${container} configuration complete, restarting..."
  $DOCKER_CMD compose restart "$container"
}

function update_qbittorrent_config {
    echo "Updating ${container} configuration..."
    local conf_file="${CONFIG_ROOT:-.}"/"$container"/qBittorrent/qBittorrent.conf
    if ! wait_for_file "$conf_file" 15; then
        echo "Skipping ${container} update due to missing config file."
        return 0
    fi
    $DOCKER_CMD compose stop "$container"
    sed -i.bak '/WebUI\\ServerDomains=*/a WebUI\\Password_PBKDF2="@ByteArray(ARQ77eY1NUZaQsuDHbIMCA==:0WMRkYTUWVT9wVvdDtHAjU9b3b7uB8NR1Gur2hmQCvCDpm39Q+PsJRJPaCU51dEiz+dTzh8qbPsL8WkFljQYFQ==)"' "$conf_file" && rm -f "${conf_file}.bak"
    echo "Update of ${container} configuration complete, restarting..."
    $DOCKER_CMD compose start "$container"
}

function update_bazarr_config {
    echo "Updating ${container} configuration..."
    local conf_file="${CONFIG_ROOT:-.}"/"$container"/config/config/config.yaml
    if ! wait_for_file "$conf_file" 30; then
        echo "Skipping ${container} update due to missing config file."
        return 0
    fi
    sed -i.bak "s/base_url: ''/base_url: '\/$container'/" "$conf_file" && rm -f "${conf_file}.bak"
    sed -i.bak "s/use_radarr: false/use_radarr: true/" "$conf_file" && rm -f "${conf_file}.bak"
    sed -i.bak "s/use_sonarr: false/use_sonarr: true/" "$conf_file" && rm -f "${conf_file}.bak"
    
    local sonarr_conf="${CONFIG_ROOT:-.}"/sonarr/config.xml
    if [ -f "$sonarr_conf" ]; then
        SONARR_API_KEY=$(sed -n 's/.*<ApiKey>\(.*\)<\/ApiKey>.*/\1/p' "$sonarr_conf")
        sed -i.bak "/sonarr:/,/^radarr:/ { s/apikey: .*/apikey: $SONARR_API_KEY/; s/base_url: .*/base_url: \/sonarr/; s/ip: .*/ip: sonarr/ }" "$conf_file" && rm -f "${conf_file}.bak"
    fi
    local radarr_conf="${CONFIG_ROOT:-.}"/radarr/config.xml
    if [ -f "$radarr_conf" ]; then
        RADARR_API_KEY=$(sed -n 's/.*<ApiKey>\(.*\)<\/ApiKey>.*/\1/p' "$radarr_conf")
        sed -i.bak "/radarr:/,/^sonarr:/ { s/apikey: .*/apikey: $RADARR_API_KEY/; s/base_url: .*/base_url: \/radarr/; s/ip: .*/ip: radarr/ }" "$conf_file" && rm -f "${conf_file}.bak"
    fi
    
    local bazarr_key=$(sed -n 's/.*apikey: \(.*\)*/\1/p' "$conf_file" | head -n 1)
    if [ -n "$bazarr_key" ]; then
        sed -i.bak 's/^BAZARR_API_KEY=.*/BAZARR_API_KEY='"${bazarr_key}"'/' .env && rm -f .env.bak
    fi
    echo "Update of ${container} configuration complete, restarting..."
    $DOCKER_CMD compose restart "$container"
}

for container in $($DOCKER_CMD ps --format '{{.Names}}'); do
  if [[ "$container" =~ ^(radarr|sonarr|lidarr|prowlarr)$ ]]; then
    update_arr_config "$container"
  elif [[ "$container" =~ ^(bazarr)$ ]]; then
    update_bazarr_config "$container"
  elif [[ "$container" =~ ^(qbittorrent)$ ]]; then
    update_qbittorrent_config "$container"
  fi
done
