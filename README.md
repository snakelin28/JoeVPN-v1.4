# JoeVPN Installer v1.4

一键在 **Lightsail / DMIT / 任意 Ubuntu·Debian VPS** 上部署 **Hysteria2 + VLESS Reality + AnyTLS**，
自带 BBR、IPv4/IPv6 转发、QUIC/TCP 缓冲优化、按内存自适应，并自动生成客户端配置和订阅。
v1.4 新增**流媒体 DNS 解锁**（原生 IP 解锁不了 Netflix / Disney+ 时用）。

针对 **Apple TV+ / Netflix / Disney+ / YouTube** 这类长时间、高码率、持续
UDP/TCP 流量做了内核层优化。

| 节点 | 端口 | 定位 |
|---|---|---|
| Reality | TCP 443 | 主力，借用真实网站证书伪装 |
| Hysteria2 | UDP 8443 | 拼速度，丢包/晚高峰线路最快 |
| AnyTLS | TCP 8443 | 备用 TCP 通道，抗 TLS-in-TLS 识别 |

> 下面命令里的仓库地址按 `snakelin28/JoeVPN-v1.4` 写。传到别的仓库名的话，
> 把 URL 和解压出来的目录名 `JoeVPN-v1.4-main` 一起换掉（目录名 = 仓库名 + `-main`）。

## 一键安装

### DMIT 等普通 VPS（root 登录，命令不加 sudo）

```bash
apt update && apt install -y curl
curl -fsSL https://github.com/snakelin28/JoeVPN-v1.4/archive/refs/heads/main.tar.gz | tar xz && cd JoeVPN-v1.4-main
nano config.conf      # 至少改 REALITY_SNI / REALITY_HANDSHAKE_SERVER；要解锁就填 UNLOCK_IP
bash install.sh
```

端口默认全开，不用配防火墙。

### Lightsail（ubuntu 用户，命令加 sudo）

1. 新建实例（Ubuntu 22.04/24.04）→ **立刻绑 Static IP**（DNS 解锁白名单认 IP，IP 一变就失效）
2. Networking → IPv4 Firewall 放行：**TCP 443 / UDP 8443 / TCP 8443 / TCP 6060**
3. 实例页点 **Connect using SSH**：

```bash
curl -fsSL https://github.com/snakelin28/JoeVPN-v1.4/archive/refs/heads/main.tar.gz | tar xz && cd JoeVPN-v1.4-main
nano config.conf
sudo bash install.sh
```

脚本会自动识别是不是 AWS：是才在结尾提醒开控制台防火墙，DMIT 等不会打印这段。

### 装完之后

- 终端里出现订阅二维码 → 小飞机 / Clash 扫码。扫不出就复制 vless:// / hysteria2:// / anytls:// 裸链接。
- 所有设备导入完：`systemctl stop joevpn-sub` 关掉订阅服务（要再导入时 `systemctl start joevpn-sub`）。
- `bash backup.sh`，把打印出来的几行（凭据 + SNI + 解锁设置）存进密码管理器。

安装中途 SSH 断了：重新连上，`cd JoeVPN-v1.4-main && bash install.sh` 再跑一次即可，凭据会复用。

## 流媒体 DNS 解锁（v1.4 新增）

### 先判断要不要

装脚本**之前**在 VPS 上跑 `bash <(curl -L -s check.unlock.media)`：

- `Netflix: Yes (Region: XX)` → 原生 IP 已解锁，**不用买**，`UNLOCK_IP` 留空
- `Originals Only` / Disney+ `No` → 买付费 DNS 解锁（如 nfdns，先买月付）

### 开启

1. 在解锁商家后台把**这台 VPS 的公网 IPv4** 加进白名单
2. `nano config.conf`，填商家给的 DNS 服务器 IP：
   ```bash
   UNLOCK_IP="103.x.x.x"
   ```
   商家给了域名列表的话，按它改 `UNLOCK_DOMAINS`（默认已含 Netflix + Disney+）
3. `bash install.sh`（凭据复用，客户端不用重新导入）
4. 测试：
   ```bash
   bash unlock-check.sh        # 跨国平台：Netflix / Disney+ / YouTube…
   bash unlock-check.sh 2      # 再加香港平台（3=日本 1=台湾 66=全部）
   ```

> ⚠ 别直接用 `check.unlock.media` 验证解锁：它用的是 VPS 系统 DNS，测的是原生 IP，
> 不经过 sing-box 的解锁规则。`unlock-check.sh` 通过 sing-box 的本机测试端口
> （只听 127.0.0.1）跑同一个检测，结果才和客户端一致。

### 原理和注意事项

- 只有 `UNLOCK_DOMAINS` 里的域名交给解锁 DNS 解析，其余流量照旧。
  **视频流域名（`nflxvideo.net` 等）不要加**，否则视频会绕到解锁商服务器，限速。
- 一个配置同时管 Reality / Hy2 / AnyTLS 三个节点。
- 解锁 DNS 不通时，Netflix / Disney+ **会直接打不开**，不会退回原生 IP（免得你以为解锁了其实只能看自制剧）。
  商家出问题时临时关掉：`UNLOCK_IP=""` 后重跑 `install.sh`。
- **换 VPS / IP 变了**：商家后台的白名单要同步改。
- **客户端要把域名发给服务器**（规则模式 / fake-ip，Clash 默认就是）。如果有人能看、有人只能看自制剧，
  通常是那个人的客户端在本地解析了域名，或者走了 IPv6。
- Disney+ 最好用和解锁地区一致的账号订阅。

## 从 v1.3 升级到 v1.4

新旧目录名不同（`JoeVPN-v1.3-main` / `JoeVPN-v1.4-main`），不会互相覆盖。
用 `migrate.sh` 把旧的凭据和设置搬过来，节点和订阅链接都不变：

```bash
cd ~
curl -fsSL https://github.com/snakelin28/JoeVPN-v1.4/archive/refs/heads/main.tar.gz | tar xz && cd JoeVPN-v1.4-main
bash migrate.sh ~/JoeVPN-v1.3-main/config.conf     # Lightsail 前面加 sudo；旧目录名以实际为准
nano config.conf                                    # 要解锁就填 UNLOCK_IP
bash install.sh
```

装完客户端里**不用**重新导入：IP、凭据、订阅路径都没变。

## 换 VPS（复用同一套节点，客户端只需换 IP / 重新扫码）

新机器上先下载、**先不装**：

```bash
curl -fsSL https://github.com/snakelin28/JoeVPN-v1.4/archive/refs/heads/main.tar.gz | tar xz && cd JoeVPN-v1.4-main
nano config.conf      # 把密码管理器里存的那几行填回去
bash install.sh
```

> 想换全新凭据：什么都不填直接装。
> 用了 DNS 解锁：记得把新 IP 加进商家白名单。

## ⚠ 仓库是公开的

- 仓库里的 `config.conf` 凭据字段**永远保持为空**，`UNLOCK_IP` 也留空。
- 服务器上跑完后的 `config.conf` 已写入凭据，**不要**从服务器往 GitHub 推任何东西。
- 改脚本只在本地干净副本里改，再上传到 GitHub。

## 目录

| 文件/目录 | 作用 |
|---|---|
| `install.sh` | 一键安装（编排全流程） |
| `unlock-check.sh` | 经过 sing-box 测流媒体解锁（v1.4） |
| `migrate.sh` | 把旧版 config.conf 的凭据/设置搬进新版（v1.4） |
| `update.sh` | 只升级 sing-box 内核 |
| `uninstall.sh` | 卸载 |
| `backup.sh` | 打包配置+证书+凭据 |
| `restore.sh` | 从备份恢复 |
| `config.conf` | 所有可配置参数 + 凭据 |
| `lib/` | 各功能模块（`unlock.sh` 为 v1.4 新增） |
| `templates/` | 服务端/客户端配置模板 |
| `clients/` | 生成的客户端配置输出 |

## AnyTLS 说明

- **不需要域名**：复用 Hysteria2 的那张自签证书，客户端跳过证书验证（订阅/链接里已自动设好）。
- **需要 sing-box ≥ 1.12**：脚本装的是最新版，满足。
- **不想要 AnyTLS**：`config.conf` 里 `ENABLE_ANYTLS=0`，重跑 `install.sh`。
- **客户端要够新**：小飞机、Clash Verge Rev、mihomo、sing-box 的较新版本才认 `anytls`。

## 内存自适应

| 档位 | 内存 | 处理 |
|---|---|---|
| small | <1GB (512MB) | QUIC/TCP 缓冲上限 16MB，自动建 2G swap，低 swappiness |
| medium | 1–2GB | 缓冲上限 25MB |
| large | 2GB+ | 缓冲上限 32MB |

## 重要提醒（脚本管不到的部分）

- **Lightsail**：控制台防火墙手动放行 `TCP 443` + `UDP 8443` + `TCP 8443` + `TCP 6060`；绑 **Static IP**。
- **Reality SNI**：默认 `www.cloudflare.com` 被用烂了，换成离 VPS 近、支持 TLS 1.3 + h2、不常见的网站。测试：
  ```bash
  openssl s_client -connect 域名:443 -tls1_3 -alpn h2 -servername 域名 </dev/null 2>&1 | grep -E 'TLSv1.3|ALPN|Verify return'
  ```
- Clash 端必须用新内核（Clash.Meta / mihomo / Verge Rev / Stash）才认 hysteria2 / reality / anytls。
- 备份文件含全部凭据，存密码管理器或加密盘，别放公开网盘/Gist。

## 自托管订阅服务

安装完自动在 `SUB_PORT`(默认 6060)起一个订阅服务，生成 YAML 订阅链接 + 终端二维码。

- 随机 32 位路径防扫描，链接形如 `http://IP:6060/<随机串>/JoeVPN.yaml`
- 同一路径下还有 base64 版 `http://IP:6060/<随机串>/sub.txt`，小飞机对 YAML 解析不全时改用这条
- 换 VPS / 公网 IP 变了，订阅链接会变，需重新导入
- 链接含凭据且走明文 HTTP，别外传；导入完建议 `systemctl stop joevpn-sub`

> 裸链接(links.txt)始终可本地导入，不依赖订阅服务。

## 更新日志

- **v1.4**：新增流媒体 DNS 解锁（`UNLOCK_IP` / `UNLOCK_DOMAINS`，sing-box resolve 路由规则，
  三个节点通用）；新增 `unlock-check.sh`（经过 sing-box 本机测试端口跑解锁检测）和 `migrate.sh`
  （旧版配置迁移）；自动识别 AWS，非 AWS 不再打印 Lightsail 防火墙提醒；root 登录的机器
  提示不再带 sudo；README 去掉仓库名占位符；backup.sh 备份内容加入 SNI 和解锁设置。
- **v1.3**：新增 AnyTLS 节点（TCP 8443，复用自签证书）；订阅服务同时发布 base64 `sub.txt`。
- **v1.2**：Hysteria2 + VLESS Reality，自托管订阅 + 二维码。
