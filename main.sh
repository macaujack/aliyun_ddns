#!/bin/sh

log() (
    level="$1"
    text="$2"
    case "$level" in
    "debug" | "Debug" | "DEBUG") color='\033[0;36m' ;; # Cyan
    "verb" | "Verb" | "VERB") color='\033[0;37m' ;;    # Gray
    "info" | "Info" | "INFO") color='\033[0;32m' ;;    # Green
    "warn" | "Warn" | "WARN") color='\033[0;33m' ;;    # Yellow
    "error" | "Error" | "ERROR") color='\033[0;31m' ;; # Red
    *)
        color="\033[0;35m" # Purple
        level="UNKNOWN"
        ;;
    esac

    level=$(printf '%s' "$level" | tr '[:lower:]' '[:upper:]')
    date=$(date +%Y-%m-%dT%H:%M:%S)
    printf '%b\n' "${color}${date} <${level}> ${text}\033[0m" 1>&2
)

echon() (
    printf '%s' "$1"
)

# Echo 这个脚本所处的目录，最后不包含这个脚本的文件名
getScriptDir() (
    script=$(readlink -f "$0")
    scriptDir=$(dirname "$script")
    echon "$scriptDir"
)

# Echo 本机的 IPv4 地址。当配置文件中 GET_IPV4_COMMAND 为空时，就会默认调用此函数
getMachineIpv4() (
    curl -s 4.ipw.cn
)

# Echo 本机的 IPv6 地址。当配置文件中 GET_IPV6_COMMAND 为空时，就会默认调用此函数。
# 需要注意，对于 IPv6 地址而言，每台设备或者每个网口都可能有多个公网 IPv6 地址，其中有一个是「永久」地址，
# 也就是只要运营商分配的前缀不变，就永远不会变。如果用目前采用的 curl 的方式，是获取不到这个永久地址的，
# 这是出于隐私保护的目的，当我们发起网络请求时，操作系统会使用非永久、临时的地址，这个基本上一天一变。不过既然
# 用了 DDNS 技术，是不是其实也没什么所谓？
#
# 如果一定想要获得永久地址，可以调「ip -6 addr」命令，然后自己 grep/sed 出来想要的那个地址
getMachineIpv6() (
    curl -s 6.ipw.cn
)

# Echo 给定的单个字符的 UTF-8 编码，比如参数为「夏」则返回「%E5%A4%8F」
getUtf8Hex() (
    ch="$1"
    length=${#ch}
    if [ "$length" -ne 1 ]; then
        log error "Length of 「${ch}」: ${length}"
        return 1
    fi

    enc=$(echon "$ch" | hexdump -ve '/1 "_%02X"' | tr '_' '%')
    echon "$enc"
)

# Echo 给定的单行字符串的 url encode 之后的结果，支持包括中文在内的国际字符，
# 比如参数为「www.例子.中国」，则返回「www.%E4%BE%8B%E5%AD%90.%E4%B8%AD%E5%9B%BD」
urlEncode() (
    str="$1"
    length=${#str}
    ret=""
    i=1
    while [ "$i" -le "$length" ]; do
        c=$(echon "$str" | cut -c "$i")
        case "$c" in
        [-_.~a-zA-Z0-9])
            enc="$c"
            ;;
        *)
            enc=$(getUtf8Hex "$c")
            retVal=$?
            if [ "$retVal" -ne 0 ]; then
                log error "无法对「${str}」进行 url encode"
                return 1
            fi
            ;;
        esac

        ret="${ret}${enc}"
        i=$((i + 1))
    done

    log verb "URL encode for \\033[4m「${str}」\\033[24m is \\033[4m「${ret}」\\033[24m"
    echon "$ret"
)

# Param1: Canonical query string
# Param2: 请求头中 "x-acs_action" 的值，也就是 API 名字，如 DescribeSubDomainRecords
# Param3: Access Key ID
# Param4: Access Key Secret
# 根据这些参数 echo 一个 raw JSON
callAliDnsOpenApi() (
    canonicalQueryString="$1"
    xAcsAction="$2"
    accessKeyId="$3"
    accessKeySecret="$4"

    host="alidns.cn-hangzhou.aliyuncs.com"
    xAcsContentSha256="e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
    xAcsDate=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    xAcsSignatureNonce=$(openssl rand -hex 32)
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

    log verb "准备发送 HTTP 请求……"
    rawJson=$(curl -s -X POST \
        -H "Authorization: $authorization" \
        -H "host: $host" \
        -H "x-acs-action: $xAcsAction" \
        -H "x-acs-content-sha256: $xAcsContentSha256" \
        -H "x-acs-date: $xAcsDate" \
        -H "x-acs-signature-nonce: $xAcsSignatureNonce" \
        -H "x-acs-version: $xAcsVersion" \
        "$url")
    retVal=$?
    if [ "$retVal" -ne 0 ]; then
        log error "HTTP 请求失败，可能是断网了"
        return 1
    fi
    log verb "🥰 HTTP 请求成功"
    echon "$rawJson"
)

# 用来检查返回的 raw JSON 里是否不存在 "Code" 字段，若不存在则为成功
# Param1: Raw JSON
checkIfApiCallSuccess() (
    echon "$rawJson" | grep -E '"Code" *: *"[a-zA-Z0-9.]+"'
    retVal=$?
    if [ "$retVal" -eq 0 ]; then
        log error "HTTP 请求成功，但是存在业务错误（比如参数不合法）。原始 JSON 返回值为「${rawJson}」"
        return 1
    fi
)

# 获取一个 JSON 对象（不可是数组）的一个 key 对应的值（该值类型必须为字符串）
# Param1: Raw JSON
# Param2: key 的名字
getJsonStringValueOfKey() (
    regex=$(printf 's/^.*"%s" *: *"([^"]+)".*$/\\1/p' "$2")
    echon "$1" | sed -nE "$regex"
)

# 调阿里的 Open API 获取单个 sub domain 的解析记录，echo 一个用制表符分隔的多行字符串，一行表示一种类型的记录，
# 需要注意第 2 个字段是 RR（即主机记录），由于这个函数是用来查询某个给定 SubDomain 的所有记录，因此结果里每行的
# RR 都是一样的，比如输入参数为「www.example.com」，那么所有记录的 RR 都是 www。
# 格式如下（第一个是 Record ID，\t 是制表符）
# 666666660000000000\twww\tA\t192.168.2.1
# 666666660000000001\twww\tAAAA\tfd17::1
# 666666660000000002\twww\tTXT\tsometext
callDescribeSubDomainRecords() (
    subDomain=$(urlEncode "$1") || return 1
    rawJson=$(callAliDnsOpenApi "SubDomain=${subDomain}" "DescribeSubDomainRecords" "$ACCESS_KEY_ID" "$ACCESS_KEY_SECRET") || return 2
    checkIfApiCallSuccess "$rawJson" || return 3

    records=$(echon "$rawJson" | sed -nE 's/^.*"Record" *: *(\[.*\]).*$/\1/p')
    if [ ${#records} -eq 0 ]; then
        log error "HTTP 请求成功且没有业务错误，但是无法匹配预期的字符串，请联系脚本作者检查服务器返回的 JSON 格式和匹配规则"
        log error "原始 JSON 返回值为「${rawJson}」"
        return 4
    fi

    if [ "$records" = '[]' ]; then
        log warn "当前不存在域名「${1}」的任何类型的解析记录"
        return
    fi

    records=$(echon "$records" | grep -oE '\{[^}]+\}')
    ret=""
    while read -r record; do
        recordId=$(getJsonStringValueOfKey "$record" "RecordId")
        rr=$(getJsonStringValueOfKey "$record" "RR")
        type=$(getJsonStringValueOfKey "$record" "Type")
        value=$(getJsonStringValueOfKey "$record" "Value")
        tem=$(printf '%s\t%s\t%s\t%s' "$recordId" "$rr" "$type" "$value")
        ret="${ret}${tem}
"
    done <<EOL
${records}
EOL

    echon "$ret"
)

# 调阿里的 Open API 更新单个解析记录。
# Param1: Record ID
# Param2: RR，（即主机记录，比如 www, @, 测试），支持包括中文在内的国际字符
# Param3: Type （即记录类型，比如 A, AAAA, CNAME, TXT）
# Param4: Value
callUpdateDomainRecord() (
    recordId=$(urlEncode "$1") || return 1
    rr=$(urlEncode "$2") || return 1
    type=$(urlEncode "$3") || return 1
    value=$(urlEncode "$4") || return 1
    canonicalQueryString="RR=${rr}&RecordId=${recordId}&Type=${type}&Value=${value}"
    rawJson=$(callAliDnsOpenApi "$canonicalQueryString" "UpdateDomainRecord" "$ACCESS_KEY_ID" "$ACCESS_KEY_SECRET") || return 2
    checkIfApiCallSuccess "$rawJson" || return 3
)

# 读取配置文件，若配置文件不存在，则新建一个并退出
readConfigFile() {
    configPath="$(getScriptDir)/config.sh"
    log info "准备读取配置文件：${configPath}"
    if [ ! -r "$configPath" ]; then
        if [ -f "$configPath" ]; then
            log error "虽然配置文件存在，但是当前系统用户无配置文件的 Read 权限，脚本退出"
            exit 1
        fi

        log info "配置文件不存在，准备新建配置文件"

        cat >"$configPath" <<EOL
#!/bin/sh

##################### 必填项 ###########################

# 你的阿里云 Access Key ID
ACCESS_KEY_ID=YourAccessKeyID
# 你的阿里云 Access Key Secret
ACCESS_KEY_SECRET=YourAccessKeySecret
# 所有需要被关注的完整域名，用任意数量的英文逗号和空格分隔
SUB_DOMAINS="www.example.com, example.com, www.例子.中国, 例子.中国"
# 在域名已有 A 类解析记录的情况下，是否要将该记录的值更新为本机 IP
IPV4_DDNS=true
# 在域名已有 AAAA 类解析记录的情况下，是否要将该记录的值更新为本机 IP
IPV6_DDNS=true

##################### 选填项 ###########################

# 自定义的本机 IPv4 地址，注意此处可以使用 $() 来以命令方式获取 IP 地址，不一定是硬编码一个地址
MACHINE_IPV4=
# 自定义的本机 IPv6 地址，注意此处可以使用 $() 来以命令方式获取 IP 地址，不一定是硬编码一个地址
MACHINE_IPV6=
EOL

        retVal=$?
        if [ "$retVal" -ne 0 ]; then
            log error "由于未知错误，无法创建配置文件，脚本退出"
            exit 99
        fi
        chmod a-x "$configPath"
        chmod u+wr "$configPath"
        log info "已创建配置文件：${configPath}"
        log info "脚本将要退出，请手动编辑配置文件后再次运行此脚本"
        exit 2
    fi

    # shellcheck disable=SC1090
    . "$configPath"
    log info "已载入配置文件"
}

# 判断当前的记录值是否需要更新，若需要则调 Open API
checkAndUpdateRecord() {
    if [ "$value" = "$gtValue" ]; then
        log info "\\033[1m${type} 类型\\033[22m: 解析记录与实际一致，不需要更新。记录值为「${gtValue}」"
        return
    fi

    log info "\\033[1m${type} 类型\\033[22m: 即将更新记录。解析记录值为「${value}」，真实值应为「${gtValue}」"
    callUpdateDomainRecord "$recordId" "$rr" "$type" "$gtValue"
}

# 各个域名之间是独立处理、互不影响的，该函数处理单个域名
handleSubDomain() {
    records=$(callDescribeSubDomainRecords "$subDomain")

    # 处理该子域名的每个记录
    while read -r record; do
        recordId=$(echon "$record" | cut -f 1)
        rr=$(echon "$record" | cut -f 2)
        type=$(echon "$record" | cut -f 3)
        value=$(echon "$record" | cut -f 4)
        gtValue="gtValue"

        if [ "$type" = "A" ] && [ "$IPV4_DDNS" = "true" ]; then
            if [ "$MACHINE_IPV4" = "" ]; then
                log verb "首次获取真实 IPv4 地址，结果将会缓存，不会再次调用获取真实地址的命令"
                MACHINE_IPV4=$(getMachineIpv4)
            fi
            gtValue="$MACHINE_IPV4"
        elif [ "$type" = "AAAA" ] && [ "$IPV6_DDNS" = "true" ]; then
            if [ "$MACHINE_IPV6" = "" ]; then
                log verb "首次获取真实 IPv6 地址，结果将会缓存，不会再次调用获取真实地址的命令"
                MACHINE_IPV6=$(getMachineIpv6)
            fi
            gtValue="$MACHINE_IPV6"
        fi

        if [ "$gtValue" = "gtValue" ]; then
            log info "\\033[1m${type} 类型\\033[22m: 跳过该类型的记录"
            continue
        fi
        if [ "$gtValue" = "" ]; then
            log warn "\\033[1m${type} 类型\\033[22m: 获取到的真实 IP 地址为空，跳过此条记录"
            continue
        fi

        checkAndUpdateRecord "$recordId" "$rr" "$type" "$value" "$gtValue"
    done <<EOL
${records}
EOL
}

testutf8() {
    gtEnc=$(urlEncode "$1")
    if [ "$2" != "$gtEnc" ]; then
        echo "Something wrong with UTF-8 encoding"
        return 1
    fi
}

updateDns() {
    records=$(callDescribeSubDomainRecords "$subDomain")

    # 处理该子域名的每个记录
    while read -r record; do
        recordId=$(echon "$record" | cut -f 1)
        rr=$(echon "$record" | cut -f 2)
        type=$(echon "$record" | cut -f 3)
        value=$(echon "$record" | cut -f 4)

        if [ "$type" != "$matchType" ]; then
            continue
        fi

        log info "找到该域名的 ${matchType} 类型记录, ID 为 ${recordId}, 记录值为 ${value}"
        if [ "$newValue" = "$value" ]; then
            log info "不需要更新"
        else
            log info "准备更新记录值为 ${newValue}"
            callUpdateDomainRecord "$recordId" "$rr" "$matchType" "$newValue" || return 1
            updated=true
            log info "更新成功"
        fi

    done <<EOL
${records}
EOL

    if [ "$updated" != "true" ]; then
        log warn "未找到任何该域名的 ${matchType} 类型记录"
    fi
}

main() {
    # 做一个简单的测试，检查 urlEncode 函数能否正常工作
    if [ "$#" -eq 1 ] && [ "$1" = "testutf8" ]; then
        log info "准备执行 UTF-8 测试，仅当测试通过， urlEncode 函数才能正常工作"
        testutf8 "www.example.com" "www.example.com" || return 1
        testutf8 "测试.例子.中国" "%E6%B5%8B%E8%AF%95.%E4%BE%8B%E5%AD%90.%E4%B8%AD%E5%9B%BD" || return 1
        testutf8 "随便一句话, mixed with English, and-some_symbols." "%E9%9A%8F%E4%BE%BF%E4%B8%80%E5%8F%A5%E8%AF%9D%2C%20mixed%20with%20English%2C%20and-some_symbols." || return 1
        testutf8 "繁體中文也可。日本語も可。" "%E7%B9%81%E9%AB%94%E4%B8%AD%E6%96%87%E4%B9%9F%E5%8F%AF%E3%80%82%E6%97%A5%E6%9C%AC%E8%AA%9E%E3%82%82%E5%8F%AF%E3%80%82" || return 1
        testutf8 "www.café.gg" "www.caf%C3%A9.gg" || return 1
        log info "测试通过， urlEncode 可以正常工作"
        return
    fi

    readConfigFile

    if [ "$1" = "update" ]; then
        if [ "$#" -ne 4 ]; then
            log error "命令格式错误，正确的用法为： ${0} update <子域名> <记录类型> <新记录值>"
            return 1
        fi

        subDomain="$2"
        matchType="$3"
        newValue="$4"
        log info "准备把域名 \\033[4m「${subDomain}」\\033[24m 的所有 ${matchType} 类型记录的值更新为 ${newValue}"
        updateDns || return 2
        return
    fi

    if [ "$1" = "get" ]; then
        if [ "$#" -ne 2 ]; then
            log error "命令格式错误，正确用法为： ${0} get <子域名>"
            return 1
        fi

        log info "准备打印域名 \\033[4m「${2}」\\033[24m 的所有记录到 stdout"
        callDescribeSubDomainRecords "$2" || return 2
        return
    fi

    log info "准备正式跑 DDNS 逻辑"
    SUB_DOMAINS=$(echon "$SUB_DOMAINS" | tr ',' ' ')
    subDomainCount=0
    for subDomain in $SUB_DOMAINS; do
        subDomainCount=$((subDomainCount + 1))
        log info "-------------------------------------------------------------------------------"
        log info "开始处理域名#${subDomainCount}: \\033[4m${subDomain}\\033[24m"
        handleSubDomain "$subDomain"
    done
}

main "$@"
