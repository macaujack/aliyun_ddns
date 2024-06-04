#!/bin/sh

# Echo 这个脚本所处的目录，最后不包含这个脚本的文件名
getScriptDir() {
    script=$(readlink -f "$0")
    scriptDir=$(dirname "$script")
    echo "$scriptDir"
}

echo2() {
    echo "$@" 1>&2
}

main() {
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

main

# echo "hello world" | tr -d '\n' | hexdump -ve '/1 "_%02x"' | tr '_' '%'
