#!/usr/bin/env bash
# unlock-check.sh — 测流媒体解锁（v1.4）
#
# 和直接在 VPS 上跑 check.unlock.media 的区别：
#   直接跑   → 用系统 DNS，测的是「原生 IP」，DNS 解锁对它不生效
#   本脚本   → 经过 sing-box 本机测试端口（127.0.0.1:LOCAL_TEST_PORT），
#              走的是和客户端完全一样的路由 + DNS 解锁规则，结果 = 客户端实际看到的
#
# 用法： bash unlock-check.sh        # 跨国平台（Netflix / Disney+ / YouTube 等）
#        bash unlock-check.sh 2      # 跨国 + 香港平台（1=台湾 3=日本 66=全部）
set -Eeuo pipefail
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONF_FILE="${PROJECT_DIR}/config.conf"
source "${PROJECT_DIR}/lib/common.sh"
source "${CONF_FILE}"
source "${PROJECT_DIR}/lib/system.sh"
source "${PROJECT_DIR}/lib/unlock.sh"

check_root
REGION="${1:-0}"

echo "${C_GRN}========== JoeVPN 解锁检测 ==========${C_RST}"

# 1. 参数 + sing-box 状态
prepare_unlock
if ! systemctl is-active --quiet sing-box; then
    log_err "sing-box 没在运行，先跑 install.sh 或看： journalctl -u sing-box -n 30 --no-pager"
    exit 1
fi
detect_public_ip

# 2. 直接问解锁 DNS（白名单是否生效）
if unlock_enabled; then
    echo
    log_info "第 1 步：直接问解锁 DNS（白名单是否生效）"
    if ! unlock_dns_probe; then
        log_err "解锁 DNS 不应答，后面的检测没有意义。先去商家后台把 ${PUBLIC_IP} 加进白名单。"
        exit 1
    fi
else
    log_warn "UNLOCK_IP 为空：下面测的就是原生 IP 的解锁情况"
fi

# 3. 经过 sing-box 跑完整检测
if ! [[ "${LOCAL_TEST_PORT:-0}" =~ ^[0-9]+$ ]] || (( ${LOCAL_TEST_PORT:-0} == 0 )); then
    log_err "config.conf 里 LOCAL_TEST_PORT=0，没开本机测试端口。改成 10808 后重跑 install.sh"
    exit 1
fi
if ! ss -ltn 2>/dev/null | awk '{print $4}' | grep -qx "127.0.0.1:${LOCAL_TEST_PORT}"; then
    log_err "本机测试端口 127.0.0.1:${LOCAL_TEST_PORT} 没在监听。v1.3 升级上来的话，重跑一次 install.sh"
    exit 1
fi

echo
log_info "第 2 步：经过 sing-box 跑 check.unlock.media（结果 = 客户端看到的）"
TMP="$(mktemp)"
trap 'rm -f "${TMP}"' EXIT
if ! curl -fsSL --max-time 30 check.unlock.media -o "${TMP}" || [[ ! -s "${TMP}" ]]; then
    log_err "下载 check.unlock.media 失败，稍后再试"
    exit 1
fi
# 用 http:// 代理：curl 把域名原样交给 sing-box 解析，DNS 解锁规则才会生效
# （socks5:// 会让 curl 在本机先解析域名，绕过解锁）
bash "${TMP}" -P "http://127.0.0.1:${LOCAL_TEST_PORT}" -M 4 -R "${REGION}" || true

cat <<EOF

${C_YEL}怎么看：${C_RST}
  • Netflix: Yes (Region: HK) / Disney+: Yes (Region: HK) → 解锁生效（地区以你买的为准）
  • Netflix: Originals Only → 解锁没生效：域名不在 UNLOCK_DOMAINS，或商家没解锁这个地区
  • Netflix: Failed (Network Connection) → 解锁 DNS 指向的节点连不上，找商家
  • 客户端里仍只能看自制剧 → 客户端在本地解析了域名，改用规则模式 / fake-ip
EOF
