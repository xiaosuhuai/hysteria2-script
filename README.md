# Hysteria 2 一键安装脚本

这是一个用于快速安装和配置 Hysteria 2 服务器的一键安装脚本。

## 功能特点

- 自动安装最新版本的 Hysteria 2
- 自动配置防火墙规则（支持 UFW、iptables 和 firewalld）
- 自动生成自签名 SSL 证书
- 自动配置 systemd 服务
- 生成客户端配置和订阅链接

## 系统要求

- 支持的操作系统：Ubuntu、Debian、CentOS、RHEL
- 需要 root 权限
- 需要 443 端口未被占用

## 快速开始

### 方法 1：直接运行（推荐）

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/xiaosuhuai/hysteria2-script/main/install.sh)
```

### 方法 2：手动安装

1. 克隆仓库：
```bash
git clone https://github.com/xiaosuhuai/hysteria2-script.git
```

2. 进入目录：
```bash
cd hysteria2-script
```

3. 运行安装脚本：
```bash
bash install.sh
```

## 配置信息

安装完成后，脚本会显示以下信息：

- 服务器 IP 地址
- 端口号（默认 443）
- 访问密码
- 订阅链接

所有配置文件都保存在 `/etc/hysteria/` 目录下：

- 配置文件：`/etc/hysteria/config.yaml`
- 证书文件：`/etc/hysteria/cert.crt`
- 私钥文件：`/etc/hysteria/private.key`
- 订阅链接：`/etc/hysteria/subscription.txt`

## 服务管理

```bash
# 启动服务
systemctl start hysteria-server

# 停止服务
systemctl stop hysteria-server

# 重启服务
systemctl restart hysteria-server

# 查看服务状态
systemctl status hysteria-server

# 查看服务日志
journalctl -u hysteria-server
```

## 注意事项

1. 脚本使用自签名证书，客户端需要设置 `insecure=1`
2. 默认使用 443 端口，请确保该端口未被其他服务占用
3. 请妥善保管生成的配置信息和密码

## 问题反馈

如果在使用过程中遇到任何问题，请在 GitHub Issues 中提出。

## 许可证

MIT License 