#!/usr/bin/env bash
# migrate.sh — 把旧版（v1.2 / v1.3）config.conf 的设置和凭据搬进本目录的新版 config.conf
#
# 新版 config.conf 多了新字段（如 v1.4 的 UNLOCK_*），直接拿旧文件覆盖会丢掉这些字段和说明。
# 本脚本只把旧文件里「新版也有、且值不同」的项写进来，其余保持新版默认。
#
# 用法： bash migrate.sh ~/JoeVPN-v1.3-main/config.conf
set -Eeuo pipefail
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONF_FILE="${PROJECT_DIR}/config.conf"
source "${PROJECT_DIR}/lib/common.sh"
source "${PROJECT_DIR}/lib/reality.sh"     # 提供 save_conf_value

OLD="${1:-}"
if [[ -z "${OLD}" || ! -f "${OLD}" ]]; then
    log_err "用法: bash migrate.sh <旧版 config.conf 路径>"
    echo "  例: bash migrate.sh ~/JoeVPN-v1.3-main/config.conf"
    exit 1
fi
if [[ "$(readlink -f "${OLD}")" == "$(readlink -f "${CONF_FILE}")" ]]; then
    log_err "旧文件就是本目录的 config.conf，不用迁移"
    exit 1
fi

# 在子 shell 里 source，各自取值，互不污染
_val() { ( set +u; source "$1" >/dev/null 2>&1; eval "printf '%s' \"\${$2-}\"" ); }
_has() { grep -qE "^$2=" "$1"; }

[[ -f "${CONF_FILE}.template.bak" ]] || cp -a "${CONF_FILE}" "${CONF_FILE}.template.bak"   # 只备份第一次（干净模板）
n=0
while IFS= read -r key; do
    _has "${CONF_FILE}" "${key}" || continue          # 新版已没有的字段，跳过
    old_v="$(_val "${OLD}" "${key}")"
    new_v="$(_val "${CONF_FILE}" "${key}")"
    [[ "${old_v}" == "${new_v}" ]] && continue
    save_conf_value "${key}" "${old_v}"
    case "${key}" in
        UUID|REALITY_PRIVATE_KEY|REALITY_PUBLIC_KEY|REALITY_SHORT_ID|HY2_PASSWORD|ANYTLS_PASSWORD|SUB_TOKEN)
            echo "  ${key} = （凭据，已迁移）" ;;
        *)  echo "  ${key} = ${old_v}" ;;
    esac
    n=$((n + 1))
done < <(grep -oE '^[A-Z][A-Z0-9_]*=' "${OLD}" | tr -d '=' | sort -u)

log_ok "已迁移 ${n} 项到 ${CONF_FILE}（迁移前的新版模板备份为 config.conf.template.bak）"
echo "  下一步：nano config.conf 检查一遍（要用 DNS 解锁就填 UNLOCK_IP），然后 bash install.sh"
