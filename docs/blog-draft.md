# 从 iNode 到 systemd：用 Codex 把一台 Ubuntu Server 接进校园有线网

> Written by Codex.

我有一台 Maxtang/N100 小主机，装的是 Ubuntu Server 24.04。它没有桌面环境，也不打算装桌面。目标很简单：把它当成一台长期运行的实体服务器。

真正的问题也很快出现：校园网。

上海财经大学的有线网络使用 H3C/iNode 客户端认证。网络中心明确说不支持 Linux 客户端。Windows 下可以点一点 iNode，Ubuntu Server 上没有这个按钮。

这篇文章记录的是我用 Codex 一起完成的一次真实排障：从“机器没网、SSH 可能会断”开始，到最后把 802.1X 认证、DHCP、路由、DNS 和 systemd 自启动全部跑通。

## 第一原则：先保 SSH

最开始没有急着碰校园墙口。我们先用 R7000 笔记本给 N100 提供一条救命管理线：

- R7000 用 Wi-Fi 上网。
- R7000 有线口直连 N100 的一个网口。
- Windows ICS 给 N100 提供 `192.168.137.0/24`。
- N100 固定为 `192.168.137.2`。

这一步的意义不只是“让 apt 能用”。更重要的是：后面所有校园网实验都不能把 SSH 管理线弄断。

最后形成的双网口模型是：

- `enp2s0`：管理口，连接 R7000，保 SSH。
- `enp1s0`：校园口，连接墙口，做实验。

## 抓包比猜配置可靠

我们先尝试确认 SUFE 的 iNode 到底在干什么。

以前最容易误判的方向是：把它当成普通 PEAP/MSCHAPv2，然后写一段 `wpa_supplicant.conf`。抓包以后这个方向被排除了。

实际看到的是：

```text
EAP Request Identity
EAP Response Identity
EAP Request Type 7
EAP Response Type 7
EAP Success / Failure
```

核心不是 PEAP，而是 EAP Type 7。

## MAC 绑定是第一道门

一开始 Windows iNode 自己也失败了。抓包显示认证流程走到了 Type 7，但服务器直接返回 `EAP Failure`。

后来发现不是脚本问题，而是有线账号绑定了旧 MAC。把正确授权的 MAC 对齐后，Windows iNode 成功认证，抓包也拿到了完整成功流程。

这个阶段最大的教训是：协议正确不代表认证会成功，校园网的 MAC 绑定也会在 EAP 阶段直接拒绝。

## Type 7 其实很小

成功包显示，iNode 的 Type 7 响应结构非常直接：

```text
1 byte password length
password bytes
identity bytes
```

于是可以写一个最小 Python 脚本，用 raw socket 直接收发 EAPOL：

- 收到 Identity 请求，回复用户名。
- 收到 Type 7 请求，回复密码长度、密码、用户名。
- 收到 Success，继续运行。
- 收到 Failure，重新开始认证。

## DHCP 和路由也要小心

认证成功只是第一半。端口放行以后，还要 DHCP：

```text
DHCP Discover
DHCP Offer
DHCP Request
DHCP ACK
```

这里也有一个服务器场景下的坑：如果 DHCP 直接覆盖默认路由，SSH 管理路径可能变得不可控。

最后的路由策略是：

```text
default via campus-gateway dev enp1s0 metric 50
default via management-gateway dev enp2s0 metric 500
management-subnet dev enp2s0
```

这样 N100 平时走校园口出网，但 R7000 到 N100 的管理链路仍然是直连。

## 最后一个坑：不要一直发 EAPOL-Start

最初版本的脚本在认证状态处理上很粗糙。它能拿到 Success，但 DHCP 服务只是固定等几秒就开始跑。只要交换机授权慢一点，或者认证中途出现一次 Failure，后面的 DHCP 和路由就会变得很脆。

修正后的策略是：

- 未认证时，每 5 秒重试 `EAPOL-Start`。
- 一旦成功，就停止主动 Start。
- 只响应交换机发来的 Identity/Type 7。
- 如果收到 Failure，再回到未认证状态重新开始。
- 成功后写入 `/run/sufe-8021x-authenticated`，让 DHCP 服务等这个状态文件，而不是赌一个固定 sleep。
- DHCP 如果没拿到地址，就干净失败，不再继续写错误默认路由。

这才稳定。

## 还有一次误判：BBR3

中途我还怀疑过是不是开了 BBR3 加速导致网络怪异。后来查了一眼内核参数才发现，当前拥塞控制仍然是 `cubic`，可用算法里也没有 BBR。更重要的是，即便真的启用了 BBR，它也只是 TCP 拥塞控制，管不到 802.1X、DHCP 和 MAC 绑定。

这个小插曲挺典型：生产排障里最危险的不是不知道，而是很快给一个听起来合理的解释。Codex 在这里比较有用的一点是，它会把解释拉回证据：先看 `sysctl`，再看 EAPOL 和 DHCP 包。

## 为什么 Codex 在这里有用

这不是一次“让 AI 给我一串命令”的经历。

真正有用的是它一直在维护三个东西：

1. 不让 SSH 管理线断。
2. 每次只改一个变量，然后验证。
3. 把失败当证据，而不是当挫败。

我们经历了：

- 网线插反。
- Windows ICS 丢失 `192.168.137.1`。
- MAC 绑定不匹配。
- DHCP 成功但路由不对。
- DNS 路由不对。
- systemd 重启后服务时序不稳。
- EAPOL-Start 过于频繁导致延迟 Failure。

每一步都不是凭感觉解决的，而是抓包、日志、路由表、服务状态一点点收敛。

## 最终状态

重启后：

```text
sufe-8021x.service active/running
sufe-campus-dhcp.service active/exited
enp1s0 10.x.x.x/xx
enp2s0 192.168.137.2/24
default via campus-gateway dev enp1s0 metric 50
management host dev enp2s0
```

这台 N100 终于从“需要被救援的裸 Ubuntu Server”，变成了一台可以继续部署服务的实体服务器。

## 代码

公共脚本和操作指南整理在仓库中。真实账号、密码、MAC、pcap 都不会进入仓库。
