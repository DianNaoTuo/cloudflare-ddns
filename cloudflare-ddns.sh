#!/usr/bin/env bash
set -euo pipefail

# =============================
# Cloudflare DDNS 主腳本（多服務共用）
# 用法：
#   cloudflare-ddns.sh /path/to/.env
# 說明：
# - 每個服務用自己的 .env（放在各 docker-compose 目錄下很OK）
# - 主腳本只保留一份，未來新增服務只要多一個 .env + 一條 cron
# =============================

CONFIG_FILE="${1:-}"
if [[ -z "$CONFIG_FILE" || ! -f "$CONFIG_FILE" ]]; then
  echo "用法：$0 /path/to/.env"
  exit 2
fi

# ---------------------------------------------------------
# 【重要】安全讀取 .env
# 目的：支援註解/空行，避免直接 source 時誤吃到奇怪內容
# 限制：.env 請維持 KEY=VALUE 格式（不要有空白，不要用 export）
# ---------------------------------------------------------
load_env() {
  local file="$1"
  while IFS= read -r line || [[ -n "$line" ]]; do
    # 忽略空行與註解
    [[ -z "${line}" || "${line}" =~ ^[[:space:]]*# ]] && continue

    # 只接受 KEY=VALUE
    if [[ "$line" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; then
      # 去除行尾 \r（避免 Windows 換行）
      line="${line%$'\r'}"
      export "$line"
    else
      echo "設定檔格式錯誤（必須是 KEY=VALUE）：$line"
      return 1
    fi
  done < "$file"
}

load_env "$CONFIG_FILE"

# ---------------------------------------------------------
# 【重要】必要變數檢查（少一個就直接中文報錯退出）
# ---------------------------------------------------------
require_var() {
  local name="$1"
  if [[ -z "${!name:-}" ]]; then
    echo "缺少必要設定：$name（請檢查 $CONFIG_FILE）"
    exit 2
  fi
}

require_var CF_API_TOKEN
require_var CF_ZONE_ID
require_var CF_DNS_RECORD_NAME

# 這些有預設值
SERVICE_NAME="${SERVICE_NAME:-ddns}"
ENABLE_IPV4="${ENABLE_IPV4:-true}"
ENABLE_IPV6="${ENABLE_IPV6:-false}"
DEFAULT_PROXIED="${DEFAULT_PROXIED:-false}"
IPV4_PROVIDER="${IPV4_PROVIDER:-https://api.ipify.org}"
IPV6_PROVIDER="${IPV6_PROVIDER:-https://api64.ipify.org}"

echo "[$SERVICE_NAME] 開始執行 DDNS：${CF_DNS_RECORD_NAME}（IPv4=$ENABLE_IPV4, IPv6=$ENABLE_IPV6, proxied預設=$DEFAULT_PROXIED）"

# ---------------------------------------------------------
# 自動檢查並安裝依賴（Ubuntu/Debian）
# - 有就跳過
# - 沒有才安裝
# - 用 dpkg lock + flock 避免鎖衝突
# ---------------------------------------------------------
auto_install_dep() {
  local bin="$1"
  local pkg="$2"

  if command -v "$bin" >/dev/null 2>&1; then
    return 0
  fi

  echo "[$SERVICE_NAME] 缺少依賴：$bin，嘗試自動安裝套件：$pkg"

  # 先確保 apt-get 存在（避免非 Debian/Ubuntu）
  if ! command -v apt-get >/dev/null 2>&1; then
    echo "[$SERVICE_NAME] 系統沒有 apt-get，無法自動安裝 $pkg，請手動安裝後再試。"
    return 1
  fi

  # 避免多個 cron 同時跑 apt 造成鎖死
  exec 9>/var/lib/dpkg/lock-frontend || true
  if command -v flock >/dev/null 2>&1; then
    flock -n 9 || { echo "[$SERVICE_NAME] APT 正在被使用，跳過本次安裝"; return 1; }
  fi

  # 降低 noise
  DEBIAN_FRONTEND=noninteractive apt-get update -qq
  DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "$pkg"
}

auto_install_dep curl curl
auto_install_dep jq jq

# ===== 取得 IP =====
get_ipv4() {
  local ip
  ip="$(curl -fsS "$IPV4_PROVIDER")"
  [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
  echo "$ip"
}

get_ipv6() {
  local ip
  ip="$(curl -fsS "$IPV6_PROVIDER" || true)"
  [[ -z "$ip" ]] && { echo ""; return 0; }
  # IPv6 格式很多，這裡做基本檢查：至少含冒號
  [[ "$ip" == *:* ]] || return 1
  echo "$ip"
}

# ===== 更新 A/AAAA 共用函式 =====
update_record() {
  local recordType="$1"   # A / AAAA
  local currentIp="$2"

  local queryUrl res resSuccess recordCount recordId recordIp recordProxied
  local apiMethod apiEndpoint payload updateRes updateSuccess

  queryUrl="https://api.cloudflare.com/client/v4/zones/${CF_ZONE_ID}/dns_records?type=${recordType}&name=${CF_DNS_RECORD_NAME}"

  res="$(curl -fsS -X GET "$queryUrl" \
    -H "Authorization: Bearer ${CF_API_TOKEN}" \
    -H "Content-Type: application/json")"

  resSuccess="$(jq -r '.success' <<<"$res")"
  if [[ "$resSuccess" != "true" ]]; then
    echo "[$SERVICE_NAME][$recordType] Cloudflare 查詢失敗：$(jq -c '.errors' <<<"$res")"
    return 1
  fi

  recordCount="$(jq -r '.result | length' <<<"$res")"
  recordId=""
  recordIp=""
  recordProxied="$DEFAULT_PROXIED"

  if [[ "$recordCount" -ge 1 ]]; then
    recordId="$(jq -r '.result[0].id' <<<"$res")"
    recordIp="$(jq -r '.result[0].content' <<<"$res")"
    # 若 Cloudflare 有回 proxied 值，更新時沿用；沒有就用 DEFAULT_PROXIED
    proxiedFromApi="$(jq -r '.result[0].proxied // empty' <<<"$res")"
    [[ -n "$proxiedFromApi" ]] && recordProxied="$proxiedFromApi"
  fi

  if [[ -n "$recordId" && "$recordIp" == "$currentIp" ]]; then
    echo "[$SERVICE_NAME][$recordType] IP 沒有變化 (${currentIp})，無需更新。"
    return 0
  fi

  if [[ -z "$recordId" ]]; then
    echo "[$SERVICE_NAME][$recordType] DNS 紀錄不存在，正在新增..."
    apiMethod="POST"
    apiEndpoint="https://api.cloudflare.com/client/v4/zones/${CF_ZONE_ID}/dns_records"
  else
    echo "[$SERVICE_NAME][$recordType] IP 變更，正在更新 DNS 紀錄..."
    apiMethod="PUT"
    apiEndpoint="https://api.cloudflare.com/client/v4/zones/${CF_ZONE_ID}/dns_records/${recordId}"
  fi

  # 用 jq 產生 JSON payload，避免手拼 JSON 造成格式錯誤
  payload="$(jq -nc \
    --arg type "$recordType" \
    --arg name "$CF_DNS_RECORD_NAME" \
    --arg content "$currentIp" \
    --argjson proxied "$recordProxied" \
    '{type:$type, name:$name, content:$content, proxied:$proxied}')"

  updateRes="$(curl -fsS -X "$apiMethod" "$apiEndpoint" \
    -H "Authorization: Bearer ${CF_API_TOKEN}" \
    -H "Content-Type: application/json" \
    --data "$payload")"

  updateSuccess="$(jq -r '.success' <<<"$updateRes")"
  if [[ "$updateSuccess" == "true" ]]; then
    echo "[$SERVICE_NAME][$recordType] 成功更新 IP 到 ${currentIp}"
    return 0
  else
    echo "[$SERVICE_NAME][$recordType] 更新失敗：$(jq -c '.errors' <<<"$updateRes")"
    return 1
  fi
}

# ===== 主流程 =====
if [[ "$ENABLE_IPV4" == "true" ]]; then
  if ipv4="$(get_ipv4)"; then
    update_record "A" "$ipv4"
  else
    echo "[$SERVICE_NAME][A] 取得 IPv4 失敗，跳過本次更新。"
  fi
else
  echo "[$SERVICE_NAME][A] IPv4 已停用（ENABLE_IPV4=false）。"
fi

if [[ "$ENABLE_IPV6" == "true" ]]; then
  ipv6="$(get_ipv6 || true)"
  if [[ -n "$ipv6" ]]; then
    update_record "AAAA" "$ipv6"
  else
    echo "[$SERVICE_NAME][AAAA] 抓不到 IPv6（可能沒有IPv6），跳過本次更新。"
  fi
else
  echo "[$SERVICE_NAME][AAAA] IPv6 已停用（ENABLE_IPV6=false）。"
fi
