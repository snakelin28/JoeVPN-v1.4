#!/usr/bin/env bash
# lib/unlock.sh — 流媒体 DNS 解锁（v1.4）
#
# 原理：sing-box 路由里加一条规则——目标域名命中 UNLOCK_DOMAINS 时，
# 用 resolve 动作改由解锁 DNS（UNLOCK_IP）解析，再从本机直连解析出来的 IP。
# 其余域名照旧由 route.default_domain_resolver（Google DoT）解析。
# 只有地区验证相关的域名经过解锁商；视频流（nflxvideo.net 等）仍从本机直出。
#
# 注意：只对「客户端把域名发给服务器」的连接生效。客户端若在本地先解析成 IP
# 再发过来，服务器看不到域名，也就解锁不了（客户端用规则模式 / fake-ip 即可）。

# 兼容旧 config.conf（v1.3 及以前没有这些字段）：缺字段就用默认值，避免 set -u 退出
: "${UNLOCK_IP:=}"
: "${UNLOCK_PORT:=53}"
: "${UNLOCK_DOMAINS:=netflix.com netflix.net nflximg.com nflximg.net nflxext.com nflxso.net disneyplus.com disney-plus.net disneystreaming.com bamgrid.com}"
: "${LOCAL_TEST_PORT:=10808}"

unlock_enabled() { [[ -n "${UNLOCK_IP}" ]]; }

_is_ipv4() {
    local ip="$1" o x
    [[ "${ip}" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]] || return 1
    IFS=. read -r -a o <<<"${ip}"
    for x in "${o[@]}"; do (( 10#${x} <= 255 )) || return 1; done
}

# 校验参数，并把域名列表整理成 JSON 数组内容，写入全局 UNLOCK_DOMAINS_JSON
prepare_unlock() {
    UNLOCK_DOMAINS_JSON=""
    if ! unlock_enabled; then
        log_info "未设置 UNLOCK_IP，不启用 DNS 解锁"
        return 0
    fi

    if ! _is_ipv4 "${UNLOCK_IP}"; then
        log_err "UNLOCK_IP 不是有效的 IPv4 地址: ${UNLOCK_IP}"
        exit 1
    fi
    if ! [[ "${UNLOCK_PORT}" =~ ^[0-9]+$ ]] || (( UNLOCK_PORT < 1 || UNLOCK_PORT > 65535 )); then
        log_err "UNLOCK_PORT 不是有效端口: ${UNLOCK_PORT}"
        exit 1
    fi

    # 逗号/换行也当分隔符；去掉 "*." 和前导点；统一小写；去重
    local raw d out=() seen=" " list=()
    raw="$(printf '%s' "${UNLOCK_DOMAINS}" | tr ',\n\t' '   ')"
    read -r -a list <<<"${raw}"          # 用 read 拆分，避免 "*.xx" 被当成通配符展开
    for d in "${list[@]}"; do
        d="${d,,}"; d="${d#\*.}"; d="${d#.}"
        [[ -n "${d}" ]] || continue
        if ! [[ "${d}" =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$ ]]; then
            log_err "UNLOCK_DOMAINS 里有无效域名: ${d}"
            exit 1
        fi
        [[ "${seen}" == *" ${d} "* ]] && continue
        seen+="${d} "
        out+=("\"${d}\"")
    done
    if (( ${#out[@]} == 0 )); then
        log_err "已设置 UNLOCK_IP，但 UNLOCK_DOMAINS 为空"
        exit 1
    fi
    if [[ "${seen}" == *" nflxvideo.net "* ]]; then
        log_warn "UNLOCK_DOMAINS 包含 nflxvideo.net：Netflix 视频流会经过解锁商服务器，可能明显变慢"
    fi
    UNLOCK_DOMAINS_JSON="$(IFS=,; printf '%s' "${out[*]}")"
    UNLOCK_DOMAIN_COUNT="${#out[@]}"
    log_ok "DNS 解锁：${UNLOCK_IP}:${UNLOCK_PORT}，${UNLOCK_DOMAIN_COUNT} 个域名"
}

# 直接问解锁 DNS，确认白名单生效（需要 dig；没有就跳过）
# 返回 0 = 解锁 DNS 有应答；1 = 无应答/拒绝
unlock_dns_probe() {
    unlock_enabled || return 0
    if ! command -v dig >/dev/null 2>&1; then
        log_warn "没有 dig 命令，跳过解锁 DNS 探测（apt install -y dnsutils 后可用 unlock-check.sh 再测）"
        return 0
    fi
    local host="www.netflix.com" ans_unlock ans_google
    ans_unlock="$(dig +short +time=3 +tries=2 -p "${UNLOCK_PORT}" @"${UNLOCK_IP}" "${host}" A 2>/dev/null \
                  | grep -E '^[0-9]+(\.[0-9]+){3}$' | sort -u | tr '\n' ' ' || true)"
    ans_google="$(dig +short +time=3 +tries=2 @8.8.8.8 "${host}" A 2>/dev/null \
                  | grep -E '^[0-9]+(\.[0-9]+){3}$' | sort -u | tr '\n' ' ' || true)"

    echo "  解锁 DNS (${UNLOCK_IP}) 返回: ${ans_unlock:-（无应答）}"
    echo "  Google  (8.8.8.8)   返回: ${ans_google:-（无应答）}"
    if [[ -z "${ans_unlock}" ]]; then
        log_warn "解锁 DNS 没有应答：多半是白名单还没加本机 IP（${PUBLIC_IP:-本机公网 IP}），或 UNLOCK_IP 填错。"
        log_warn "这种情况下 Netflix / Disney+ 会直接打不开（不会退回原生 IP）。"
        return 1
    fi
    if [[ "${ans_unlock}" == "${ans_google}" ]]; then
        log_warn "解锁 DNS 和 Google 返回的 IP 一样——可能这个域名不在商家解锁范围，或白名单未生效。"
    else
        log_ok "解锁 DNS 有应答，白名单已生效（返回的 IP 和 Google 不同，一般就是商家的解锁节点；最终以 unlock-check.sh 第 2 步为准）"
    fi
    return 0
}

print_unlock_summary() {
    if unlock_enabled; then
        echo " DNS 解锁  : ${UNLOCK_IP}:${UNLOCK_PORT}  (${UNLOCK_DOMAIN_COUNT:-?} 个域名)"
    else
        echo " DNS 解锁  : 未启用（UNLOCK_IP 为空）"
    fi
}
