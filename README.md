# Hysteria 2 一键安装脚本

这是一个用于快速安装和管理 Hysteria 2 代理服务器的 Shell 脚本。Hysteria 2 是一个强大的、快速的、抗审查的代理工具。

## 功能特点

- ✨ 一键安装 Hysteria 2 服务器
- 🔄 自动配置 HTTPS 证书
- 🚀 支持自定义端口和配置
- 📊 内置连接状态监控
- 🔐 自动生成安全配置
- 📱 支持多种客户端订阅格式
- 🛡️ 自动配置防火墙规则

## 系统要求

- 操作系统：基于 Debian/Ubuntu 的 Linux 系统
- 需要 root 权限
- 需要一个域名（可选，但推荐使用）

## 快速开始

### 安装

使用以下命令一键安装：

```bash
wget -N https://raw.githubusercontent.com/xiaosuhuai/hysteria2-script/main/install.sh && bash install.sh
```

或者使用 curl：

```bash
curl -fsSL https://raw.githubusercontent.com/xiaosuhuai/hysteria2-script/main/install.sh -o install.sh && bash install.sh
```

### 使用说明

安装完成后，脚本提供以下功能：

1. 安装 Hysteria 2
2. 卸载 Hysteria 2
3. 查询 Hysteria 2 订阅
4. 查询 Hysteria 2 连接
5. 更新域名证书

## 客户端支持

支持的客户端包括：
- Shadowrocket (v2.2.35+)
- Stash (v2.5.0+)
- Loon (v3.1.3+)
- Surge (v5.8.0+)
- Streisand (v1.5.6+)
- Pharos Pro (v1.8.3+)
- Egern (v1.14.0+)

## 配置文件位置

- 主配置文件：`/etc/hysteria/config.yaml`
- 证书文件：`/etc/hysteria/cert.crt` 和 `/etc/hysteria/private.key`
- 订阅配置：`/etc/hysteria/subscribe/`

## 常用命令

```bash
# 查看订阅信息
hy2sub

# 查看连接状态
hy2stat

# 查看客户端连接
hy2client
```

## 安全说明

- 脚本会自动配置防火墙规则
- 支持 HTTPS 证书自动申请和续期
- 建议使用域名并启用 HTTPS 以提高安全性

## 问题排查

如果遇到问题，请检查：
1. 确保端口未被其他服务占用
2. 检查防火墙配置
3. 确保域名解析正确（如果使用域名）
4. 查看服务日志：`journalctl -u hysteria-server`

## 许可证

MIT License

## 致谢

- [Hysteria](https://github.com/apernet/hysteria) - 感谢 Hysteria 团队开发的优秀代理工具
- 所有为这个项目做出贡献的开发者 