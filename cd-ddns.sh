#!/usr/bin/env bash
export LANG="zh_CN.UTF-8"

set -o errexit #严格模式 报错退出
set -o nounset
set -o pipefail
#set -o xtrace #调试

# Cloudflare API 密钥
CFKEY="000000000000000000000000000000000000"

# Cloudflare 帐号邮箱
CFUSER="xxx@xxx.com"

# 域名的区域名称
CFZONE_NAME="xxx.xxx"

# 需要更新的主机名
CFRECORD_NAME="xxx.xxx.xxx"

# DNS 记录的 TTL（生存时间），范围为 120 到 86400 秒
CFTTL=120

# 获取公网 IP 
get_public_ip() {
    local ip_version=$1
    local ip=""
    # 定义多个服务以获取公网 IP 地址
    local services=(
        "https://icanhazip.com"
        "https://ifconfig.me"
        "https://api.ip.sb/ip"
        "https://ipinfo.io/ip"
    )

    # 依次尝试每个服务，直到成功获取 IP 地址
    for service in "${services[@]}"; do
        ip=$(curl -s "$ip_version" "$service" || true)
        if [[ -n "$ip" ]]; then
            echo "$ip"
            return 0
        fi
    done

    return 1
}

# 并行获取 IPv4 和 IPv6 地址
IP4=$(get_public_ip -4 &)
IP6=$(get_public_ip -6 &)
wait

# 输出获取的 IP 地址
if [[ -n "$IP4" ]]; then
    echo "获取到的 IPv4 地址: $IP4"
else
    echo "未能获取到 IPv4 地址。"
fi

if [[ -n "$IP6" ]]; then
    echo "获取到的 IPv6 地址: $IP6"
else
    echo "未能获取到 IPv6 地址。"
fi

# 获取 Cloudflare 区域 ID
CFZONE_ID=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones?name=$CFZONE_NAME" \
    -H "X-Auth-Email: $CFUSER" \
    -H "X-Auth-Key: $CFKEY" \
    -H "Content-Type: application/json" | jq -r '.result[0].id')

# 获取 Cloudflare A 记录的 ID
CFRECORD_ID_A=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$CFZONE_ID/dns_records?name=$CFRECORD_NAME&type=A" \
    -H "X-Auth-Email: $CFUSER" \
    -H "X-Auth-Key: $CFKEY" \
    -H "Content-Type: application/json" | jq -r '.result[0].id')

# 获取 Cloudflare AAAA 记录的 ID
CFRECORD_ID_AAAA=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$CFZONE_ID/dns_records?name=$CFRECORD_NAME&type=AAAA" \
    -H "X-Auth-Email: $CFUSER" \
    -H "X-Auth-Key: $CFKEY" \
    -H "Content-Type: application/json" | jq -r '.result[0].id')

# 定义更新 DNS 记录的函数
update_dns_record() {
    local record_id=$1
    local record_type=$2
    local ip=$3

    # 发送请求更新 DNS 记录
    response=$(curl -s -X PUT "https://api.cloudflare.com/client/v4/zones/$CFZONE_ID/dns_records/$record_id" \
        -H "X-Auth-Email: $CFUSER" \
        -H "X-Auth-Key: $CFKEY" \
        -H "Content-Type: application/json" \
        --data "{\"type\":\"$record_type\",\"name\":\"$CFRECORD_NAME\",\"content\":\"$ip\",\"ttl\":$CFTTL}")

    # 检查更新是否成功
    if echo "$response" | jq -e '.success' >/dev/null; then
        echo "$record_type 记录已成功更新为 $ip"
    else
        echo "更新 $record_type 记录失败：$response"
    fi
}

# 更新 A 记录（IPv4）
if [[ -n "$IP4" ]]; then
    update_dns_record "$CFRECORD_ID_A" "A" "$IP4"
else
    echo "由于未获取到 IPv4 地址，跳过 A 记录的更新。"
fi

# 更新 AAAA 记录（IPv6）
if [[ -n "$IP6" ]]; then
    update_dns_record "$CFRECORD_ID_AAAA" "AAAA" "$IP6"
else
    echo "由于未获取到 IPv6 地址，跳过 AAAA 记录的更新。"
fi
