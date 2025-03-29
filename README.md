# Hysteria 2 一键脚本

> A powerful, lightning fast and censorship resistant proxy.
> 
> by Aperture Internet Laboratory <https://github.com/apernet>

一个适用于个人使用的 Hysteria 2 一键安装脚本。基于 Hysteria 2.6.1 版本。

## 功能特点

- 一键安装/卸载 Hysteria 2 服务
- 自动配置 Nginx 订阅服务
- 生成 Clash 和小火箭订阅链接
- 支持扫码导入配置（小火箭）
- 开机自启动

## 使用方法

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/xiaosuhuai/hysteria2-script/main/install.sh)
```

## 菜单选项

1. 全新安装
2. 卸载服务
3. 查询订阅
0. 退出脚本

## 客户端支持

推荐使用 Shadowrocket (小火箭)，简单好用。

其他支持的客户端：
- Stash (v2.5.0+)
- Loon (v3.1.3+)
- Surge (v5.8.0+)
- Streisand (v1.5.6+)
- Pharos Pro (v1.8.3+)
- Egern (v1.14.0+)

## 注意事项

- 仅支持 x86_64 或 aarch64 架构
- 需要 root 权限运行
- 使用自签证书，请在客户端中开启"跳过证书验证"

## 系统要求

- 支持的操作系统：Ubuntu、Debian、CentOS、RHEL
- 需要所选端口未被占用

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

## 使用说明

1. 运行脚本时，系统会提示你输入服务端口
   - 直接回车将使用默认端口443
   - 也可以输入1-65535之间的任意未被占用的端口
2. 然后会提示你输入访问密码
   - 如果直接回车，系统会自动生成一个随机密码
   - 也可以输入自定义的密码
3. 安装完成后会显示所有配置信息

## 配置信息

安装完成后，脚本会显示以下信息：

- 服务器 IP 地址
- 端口号（自定义或默认443）
- 访问密码（自定义或随机生成）
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

## 问题反馈

如果在使用过程中遇到任何问题，请在 GitHub Issues 中提出。

## 许可证

MIT License
