# SUFE Linux 802.1X

在 Ubuntu Server 上复现上海财经大学有线网络的 iNode/H3C 802.1X 认证流程。

这个仓库来自一次真实排障：一台 Maxtang/N100 小主机运行 Ubuntu Server 24.04，没有桌面环境，需要在保留 SSH 管理通道的同时，让第二个有线网口接入 SUFE 校园有线网。

## 适用场景

- 学校有线网使用 H3C/iNode 客户端认证。
- Linux 下普通 `wpa_supplicant` PEAP/MSCHAPv2 配置不可用。
- 机器有两个网口：
  - 管理口：连接另一台电脑或内网，用于 SSH 救援。
  - 校园口：连接 SUFE 有线墙口，做 802.1X 认证和 DHCP。
- 已确认账号、密码、MAC 使用是本人授权范围内的行为。

## 不适用场景

- 你没有账号或网口授权。
- 学校已经更换认证协议。
- 你只有单网口且没有其他可靠管理通道。
- 你希望绕过学校网络管理策略。

## 核心结论

抓包确认 SUFE 有线认证外层是 802.1X/EAPOL，关键认证类型是 EAP Type 7，不是普通 PEAP/MSCHAPv2。

本仓库里的最小认证器会：

1. 发送 `EAPOL-Start`。
2. 响应 `EAP Request Identity`。
3. 响应 `EAP Request Type 7`。
4. 持续处理交换机周期性保活认证。
5. 配合 DHCP 获取校园网 IPv4 地址。

## 快速开始

假设：

- 管理口是 `enp2s0`，地址为 `192.168.137.2/24`。
- 校园口是 `enp1s0`。
- 校园网关是 `10.64.0.1`。
- 你需要把校园口伪装成已授权 MAC。

复制文件：

```bash
sudo install -d -m 700 /etc/sufe-8021x
sudo install -m 0755 scripts/sufe_8021x_auth.py /usr/local/sbin/sufe_8021x_auth.py
sudo install -m 0755 scripts/sufe-campus-net.sh /usr/local/sbin/sufe-campus-net.sh
sudo install -m 0755 scripts/sufe-campus-dhcp-route.sh /usr/local/sbin/sufe-campus-dhcp-route.sh
sudo install -m 0644 systemd/sufe-8021x.service /etc/systemd/system/sufe-8021x.service
sudo install -m 0644 systemd/sufe-campus-dhcp.service /etc/systemd/system/sufe-campus-dhcp.service
```

创建私有配置：

```bash
sudo cp examples/sufe-8021x.env.example /etc/sufe-8021x/sufe-8021x.env
sudo chmod 600 /etc/sufe-8021x/sufe-8021x.env
sudo editor /etc/sufe-8021x/sufe-8021x.env
```

启动：

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now sufe-8021x.service
sudo systemctl enable --now sufe-campus-dhcp.service
```

验证：

```bash
systemctl status sufe-8021x.service sufe-campus-dhcp.service
ip -br addr show
ip route
ip route get 1.1.1.1
ping -c 2 223.5.5.5
resolvectl query github.com
```

期望看到：

- `sufe-8021x.service` 为 `active (running)`。
- `sufe-campus-dhcp.service` 为 `active (exited)`。
- 校园口拿到 `10.x.x.x` 地址。
- 默认路由优先走校园口，管理口保留较高 metric 的备用路由。

## 文件说明

- [scripts/sufe_8021x_auth.py](scripts/sufe_8021x_auth.py)：最小 EAPOL/Type 7 认证器。
- [scripts/sufe-campus-net.sh](scripts/sufe-campus-net.sh)：设置校园口 MAC、清空旧地址、拉起网口。
- [scripts/sufe-campus-dhcp-route.sh](scripts/sufe-campus-dhcp-route.sh)：运行 DHCP 并规范路由/DNS。
- [systemd/sufe-8021x.service](systemd/sufe-8021x.service)：长期运行的 802.1X 认证服务。
- [systemd/sufe-campus-dhcp.service](systemd/sufe-campus-dhcp.service)：DHCP 与路由服务。
- [examples/sufe-8021x.env.example](examples/sufe-8021x.env.example)：配置模板。
- [docs/troubleshooting.md](docs/troubleshooting.md)：排障手册。
- [docs/packet-analysis-notes.md](docs/packet-analysis-notes.md)：抓包分析笔记。
- [docs/blog-draft.md](docs/blog-draft.md)：博客初稿。

## 安全说明

不要提交真实配置：

- 账号
- 密码
- 绑定 MAC
- 原始 pcap
- iNode 日志

本仓库只保存公共脚本和模板。真实环境配置应只放在 `/etc/sufe-8021x/sufe-8021x.env`，并设置为 root-only 权限。

## License

MIT
