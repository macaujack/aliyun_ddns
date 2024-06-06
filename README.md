# 阿里云 DDNS 脚本

一个简单的、尽量可移植的小 shell 脚本，主要支持的功能如下：

- 调阿里云 Open API 的 [DescribeSubDomainRecords](https://api.aliyun.com/document/Alidns/2015-01-09/DescribeSubDomainRecords) 来查询解析记录
- 调阿里云 Open API 的 [UpdateDomainRecord](https://api.aliyun.com/document/Alidns/2015-01-09/UpdateDomainRecord) 来更新解析记录
- 支持 IPv4 和 IPv6
- 支持包括中文域名在内的国际域名（IDN）
- 可移植，因此可在类 Unix 系统上跑，包括 OpenWRT（已在 Ubuntu 20.04，OpenWRT 21.02，macOS 14.4.1 上测试过）

## 功能

首先下载 `main.sh` ；或者直接复制粘贴该脚本的内容到本地的一个文件里，然后 `chmod a+x` 那个文件。

首次执行 `./main.sh` 时，会在脚本目录下新建一个配置文件 `aliyun_ddns_config.sh`。把阿里云的 access key 等信息填好之后，再次执行 `./main.sh`，即可执行一次「检查当前 IP，若与解析记录不同则更新解析记录」的操作。如果要定时执行，需自行配置系统定时任务，定期执行此脚本。

执行 `./main.sh testutf8` 可测试 url encode 能否正常工作。根据阿里云 Open API 的[签名机制](https://help.aliyun.com/zh/sdk/product-overview/v3-request-structure-and-signature)，我们是需要 url encode 的。对于有国际域名（IDN）解析需求的用户来说，最好可以先执行此命令测一下当前环境对 UTF-8 的支持情况。

执行 `./main.sh get <子域名>` 可获取阿里云中一个给定子域名（用户需拥有该域名）的所有解析记录，如 `./main.sh get www.example.com`。

执行 `./main.sh update <子域名> <记录类型> <新记录值>` 可更新阿里云中一个给定子域名（用户需拥有该域名）的给定记录类型的所有记录（一种记录类型可能有多个记录）的值为给定的新记录值，如 `./main.sh update www.example.com AAAA fd17::1`，执行此命令即可把 `www.example.com` 的 AAAA 类型（IPv6 类型）的所有记录（一般只有 1 个）的记录值更新为 `fd17::1`。

## 依赖

本脚本依赖一些系统已有的程序，包括

- echo（应该是系统自带？）
- printf（应该是系统自带？）
- readlink（应该是系统自带？）
- dirname（应该是系统自带？）
- hexdump
- curl
- openssl

如系统里没有，需要先把依赖安装上，再执行脚本。

## 程序流程

伪代码如下：

```
foreach (subDomain in SUB_DOMAINS) {
    records := callDescribeSubDomainRecords // 调 API 获取所有解析记录

    foreach (record in records) {
        if (record.type == "A" && IPV4_DDNS == "true") {
            gtIp := 当前机器的实际 IPv4 地址
            if (record.value != gtIp) {
                调 API 更新该记录的值
            }
        }
        else if (record.type == "AAAA" && IPV6_DDNS == "true") {
            gtIp := 当前机器的实际 IPv6 地址
            if (record.value != gtIp) {
                调 API 更新该记录的值
            }
        }
    }
}
```

该脚本**不会新增**一个解析记录，也就是说，如果某个子域名本来就没有 AAAA 类型的记录，就算配置文件里 `IPV6_DDNS` 为 true，对该子域名来说也是不会有任何效果的。

## 自定义获取 IP

此脚本的配置文件是 `aliyun_ddns_config.sh`，这个所谓配置文件本质上也是一个 shell 脚本，`main.sh` 只不过 `source` 了一下这个配置脚本。

配置文件里有非必填项 `MACHINE_IPV4` 和 `MACHINE_IPV6`，这两个值是可以用命令来动态计算出来的。如果这两个值留空，那么脚本就会使用 `curl 4.ipw.cn` 和 `curl 6.ipw.cn` 两条命令来分别获取本机 IPv4 和 IPv6 地址。

以 IPv6 为例解释如何自定义获取 IP。当前，每个机器或者每个网口可能都有至少 2 个 公网（指 global unicast） IPv6 地址，其中有 1 个或多个**临时**地址，以及 1 个**永久**地址。临时地址可能一天一换；永久地址只要运营商分配的 IPv6 段的前缀不变，就不会变。当机器作为网络请求发起方时，机器会选用临时地址，这是为了隐私保护。但是当我们的机器要做一个服务器时（比如提供网页或者 SSH 服务器），一天一换的临时地址就用起来不方便，所有才会有一个永久地址。

在 DDNS 的情况下，假设每 10 分钟跑一次更新脚本，那么其实把域名解析到临时 IPv6 地址也没问题（`curl 6.ipw.cn` 获得的就是临时地址）。但是可能有一些情况或者有强迫症，就是想解析到永久地址，那么我们可以用 `ip` 和 `sed` 命令来实现。

首先调 `ip -6 addr`，能看到本机的若干网口的若干 IPv6 地址。我们找到我们需要的那个网口，比如我的 Ubuntu 机器上需要的是 `wlp4s0`，我的 macOS 机器上需要的是 `en0`，路由器（OpenWRT）上需要的是 `pppoe-wan`。

找到了我们需要的网口后，我们再调 `ip -6 addr show wlp4s0`，就能仅输出 `wlp4s0` 这个网口的信息了。

接下来我们用 `sed` 命令把永久地址抠出来。在我的 Ubuntu 机器上，所有临时地址的那一行后面都会有一个 `temporary`，而永久地址则会有一个 `mngtmpaddr`。此外，我的运营商是中国联通，中国联通的 IPv6 地址是 2408 开头的。用这些信息，我们可以写出如下命令

```
ip -6 addr show wlp4s0 | sed -nE 's/^.*inet6.*(2408[0-9a-f:]+).*mngtmpaddr.*$/\1/p
```

因此，在 `aliyun_ddns_config.sh` 中，我们要加上

```
MACHINE_IPV6=$(ip -6 addr show wlp4s0 | sed -nE 's/^.*inet6.*(2408[0-9a-f:]+).*mngtmpaddr.*$/\1/p)
```

## 遇到问题

麻烦在 GitHub 上开 issue，或者 email 联系作者 yanxfu@gmail.com 。
