# VPN 工具一键安装脚本

这个仓库包含两个强大的网络工具的一键安装脚本：
1. Hysteria 2 - 强大的代理工具
2. FRP - 高性能的内网穿透工具

## Hysteria 2 安装

### 功能特点

- 一键安装/卸载 Hysteria 2 服务
- 自动配置 Nginx 订阅服务
- 生成 Clash 和小火箭订阅链接
- 支持扫码导入配置（小火箭）
- 开机自启动

### 安装命令

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/xiaosuhuai/vpn/main/install.sh)
```

### 支持的客户端
- Shadowrocket (小火箭)（推荐）
- Stash (v2.5.0+)
- Loon (v3.1.3+)
- Surge (v5.8.0+)
- Streisand (v1.5.6+)
- Pharos Pro (v1.8.3+)
- Egern (v1.14.0+)

## FRP 服务端安装

### 功能特点

- 一键安装/配置 FRP 服务端
- 自动获取最新版本
- 自动配置系统服务
- 自动配置防火墙规则
- 支持 Web 管理面板
- 支持 HTTPS 反向代理（基于 Nginx）
- 开机自启动
- 低内存占用（适合小内存VPS）

### 安装命令

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/xiaosuhuai/vpn/main/install-frps.sh)
```

### 内网穿透配置示例

1. HTTP 服务穿透：
```ini
[web]
type = http
local_ip = 127.0.0.1
local_port = 80
custom_domains = web.yourdomain.com
```

2. HTTPS 服务穿透：
```ini
[web-https]
type = https
local_ip = 127.0.0.1
local_port = 443
custom_domains = secure.yourdomain.com
```

3. TCP 服务穿透（如 SSH）：
```ini
[ssh]
type = tcp
local_ip = 127.0.0.1
local_port = 22
remote_port = 6000
```

## 手动安装方法

1. 克隆仓库：
```bash
git clone https://github.com/xiaosuhuai/vpn.git
```

2. 进入目录：
```bash
cd vpn
```

3. 选择要安装的工具：
```bash
# 安装 Hysteria 2
bash install.sh

# 或安装 FRP 服务端
bash install-frps.sh
```

## 系统要求

- 支持的操作系统：Ubuntu、Debian、CentOS
- 最低配置要求：
  - CPU: 1核
  - 内存: 512MB 及以上
  - 硬盘: 10GB 及以上
- 需要 root 权限运行
- 需要所选端口未被占用

## Hysteria 2 配置

- 配置文件：`/etc/hysteria/config.yaml`
- 证书文件：`/etc/hysteria/cert.crt`
- 私钥文件：`/etc/hysteria/private.key`
- 订阅目录：`/etc/hysteria/subscribe/`

### 服务管理
```bash
systemctl start/stop/restart hysteria-server
systemctl status hysteria-server
```

## FRP 配置

- 主配置文件：`/etc/frp/frps.ini`
- 服务文件：`/etc/systemd/system/frps.service`
- 日志文件：`/var/log/frps.log`
- Nginx 配置：`/etc/nginx/conf.d/frp-panel.conf`

### 服务管理
```bash
# FRP 服务管理
systemctl start/stop/restart frps
systemctl status frps

# Nginx 服务管理
systemctl start/stop/restart nginx
systemctl status nginx
```

### SSL 证书配置
如果需要配置 HTTPS，可以使用以下方法：

1. 使用 Let's Encrypt：
```bash
apt install certbot python3-certbot-nginx
certbot --nginx -d your.domain.com
```

2. 使用自签名证书：
```bash
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /etc/nginx/cert.key -out /etc/nginx/cert.crt
```

## 注意事项

1. 两个服务可以共存，但请注意：
   - 使用不同的端口
   - 合理分配系统资源
   - 正确配置防火墙规则
2. 安装前请确保：
   - 系统已安装基本工具（curl、wget、tar）
   - 所需端口未被占用
   - 有足够的系统资源
3. 内存优化建议：
   - 启用 swap 分区（建议 2GB）
   - 调整系统 TCP 参数优化网络性能
   - 使用 Nginx 压缩功能减少带宽占用

## 问题反馈

如果在使用过程中遇到任何问题，请在 GitHub Issues 中提出。

## 许可证

MIT License
