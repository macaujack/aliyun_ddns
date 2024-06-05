#!/bin/sh

echo2() {
    echo "$@" 1>&2
}

echon() {
    printf '%s' "$1"
}

# Echo 这个脚本所处的目录，最后不包含这个脚本的文件名
getScriptDir() {
    script=$(readlink -f "$0")
    scriptDir=$(dirname "$script")
    echon "$scriptDir"
}

# Echo 本机的 IPv4 地址
getMachineIpv4() {
    # TODO: Complete this function
    echon "192.168.2.1"
}

# Echo 本机的 IPv6 地址，会尽量选择永久（非临时）的地址
getMachineIpv6() {
    # TODO: Complete this function
    echon "fd17::1"
}

# Echo 给定的单个字符的 UTF-8 编码，比如参数为「夏」则返回「%E5%A4%8F」
getUtf8Hex() {
    ch="$1"
    length=${#ch}
    if [ "$length" -ne 1 ]; then
        echo "err"
        return
    fi

    echon "$ch" | hexdump -ve '/1 "_%02X"' | tr '_' '%'
}

# Echo 给定的字符串的 url encode 之后的结果，支持包括中文在内的国际字符，
# 比如参数为「www.例子.中国」，则返回「www.%E4%BE%8B%E5%AD%90.%E4%B8%AD%E5%9B%BD」
urlEncode() {
    str="$1"
    chs=$(echon "$str" | sed -e 's/\(.\)/\1\n/g')
    ret=""
    for c in $chs; do
        case "$c" in
        [-_.~a-zA-Z0-9])
            enc="$c"
            ;;
        *)
            enc=$(getUtf8Hex "$c")
            if [ "$enc" = "err" ]; then
                echon ""
                return
            fi
            ;;
        esac
        ret="${ret}${enc}"
    done
    echon "$ret"
}

# Param1: Canonical query string
# Param2: 请求头中 "x-acs_action" 的值，也就是 API 名字，如 DescribeSubDomainRecords
# Param3: Access Key ID
# Param4: Access Key Secret
# 根据这些参数 echo 一个 raw JSON
callAliDnsOpenApi() {
    canonicalQueryString="$1"
    xAcsAction="$2"
    accessKeyId="$3"
    accessKeySecret="$4"

    host="alidns.cn-hangzhou.aliyuncs.com"
    xAcsContentSha256="e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
    xAcsDate=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    xAcsSignatureNonce=$(awk 'BEGIN{srand(); for(i=0;i<4;i++) printf "%08x",int(rand()*"0xFFFFFFFF")}')
    xAcsVersion="2015-01-09"
    signedHeaders="host;x-acs-action;x-acs-content-sha256;x-acs-date;x-acs-signature-nonce;x-acs-version"

    canonicalRequest="POST
/
${canonicalQueryString}
host:${host}
x-acs-action:${xAcsAction}
x-acs-content-sha256:${xAcsContentSha256}
x-acs-date:${xAcsDate}
x-acs-signature-nonce:${xAcsSignatureNonce}
x-acs-version:${xAcsVersion}

${signedHeaders}
${xAcsContentSha256}"
    hashedCanonicalRequest=$(echon "$canonicalRequest" | openssl dgst -sha256 | tail -c 65 | head -c 64)
    stringToSign="ACS3-HMAC-SHA256
${hashedCanonicalRequest}"
    signature=$(echon "$stringToSign" | openssl dgst -sha256 -hmac "$accessKeySecret" | tail -c 65 | head -c 64)

    authorization="ACS3-HMAC-SHA256 Credential=${accessKeyId},SignedHeaders=${signedHeaders},Signature=${signature}"
    url="${host}/?${canonicalQueryString}"
    rawJson=$(curl -s -X POST \
        -H "Authorization: $authorization" \
        -H "host: $host" \
        -H "x-acs-action: $xAcsAction" \
        -H "x-acs-content-sha256: $xAcsContentSha256" \
        -H "x-acs-date: $xAcsDate" \
        -H "x-acs-signature-nonce: $xAcsSignatureNonce" \
        -H "x-acs-version: $xAcsVersion" \
        "$url")
    echon "$rawJson"
}

# 调阿里的 Open API 获取单个 sub domain 的解析记录，echo 逗号分隔字符串，格式如下：
# A,192.168.2.1
# AAAA,fd17::1
describeSubDomainRecords() {
    subDomain=$(urlEncode "$1")
    rawJson=$(callAliDnsOpenApi "SubDomain=${subDomain}" "DescribeSubDomainRecords" "$ACCESS_KEY_ID" "$ACCESS_KEY_SECRET")
    # TODO: grep useful info from raw JSON
    echon "$rawJson"
}

# 读取配置文件，若配置文件不存在，则新建一个并退出
readConfigFile() {
    configPath="$(getScriptDir)/config.sh"
    echo2 "准备读取配置文件：${configPath}"
    if [ ! -r "$configPath" ]; then
        if [ -f "$configPath" ]; then
            echo2 "虽然配置文件存在，但是当前系统用户无配置文件的 Read 权限，脚本退出"
            exit 1
        fi

        echo2 "配置文件不存在，准备新建配置文件"

        cat >"$configPath" <<EOL
#!/bin/sh
ACCESS_KEY_ID=YourAccessKeyID
ACCESS_KEY_SECRET=YourAccessKeySecret
SUB_DOMAINS="www.example.com, example.com, www.例子.中国, 例子.中国"
IPV4_DDNS=true
IPV6_DDNS=true
EOL

        retVal=$?
        if [ "$retVal" -ne 0 ]; then
            echo2 "由于未知错误，无法创建配置文件，脚本退出"
            exit 99
        fi
        chmod a-x "$configPath"
        chmod u+wr "$configPath"
        echo2 "已创建配置文件：${configPath}"
        echo2 "脚本将要退出，请手动编辑配置文件后再次运行此脚本"
        exit 2
    fi

    # shellcheck disable=SC1090
    . "$configPath"
}

main() {
    readConfigFile
}

main
