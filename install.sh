#!/bin/bash

# 检查是否为 root 用户
if [ "$EUID" -ne 0 ]; then
    echo "请使用 root 用户运行此脚本"
    exit 1
fi

# 设置变量
HYSTERIA_VERSION="v2.6.1"
SERVER_IP=$(curl -s https://api.ipify.org) # 自动获取服务器公网IP
echo "检测到服务器IP: $SERVER_IP"

# 提示用户输入端口
read -p "请设置服务端口 (直接回车默认443): " USER_PORT
if [ -z "$USER_PORT" ]; then
    USER_PORT="443"
    echo "使用默认端口: 443"
else
    # 检查端口是否为数字且在有效范围内
    if ! [[ "$USER_PORT" =~ ^[0-9]+$ ]] || [ "$USER_PORT" -lt 1 ] || [ "$USER_PORT" -gt 65535 ]; then
        echo "错误：端口必须是1-65535之间的数字"
        exit 1
    fi
    # 检查端口是否已被占用
    if netstat -tuln | grep -q ":$USER_PORT "; then
        echo "错误：端口 $USER_PORT 已被占用"
        exit 1
    fi
fi

# 提示用户输入密码
read -p "请设置访问密码 (如果直接回车将生成随机密码): " USER_PASSWORD
if [ -z "$USER_PASSWORD" ]; then
    # 生成随机密码 (16位字母数字组合)
    USER_PASSWORD=$(openssl rand -base64 12)
    echo "已生成随机密码: $USER_PASSWORD"
fi

# 安装必要的软件包
apt update
apt install -y curl openssl net-tools

# 配置防火墙
echo "配置防火墙规则..."
# 检查是否安装了 UFW
if command -v ufw >/dev/null 2>&1; then
    # 配置 UFW
    ufw allow ${USER_PORT}/tcp
    ufw allow ${USER_PORT}/udp
    # 如果 UFW 未启用，启用它
    if ! ufw status | grep -q "Status: active"; then
        ufw --force enable
    fi
    echo "UFW 防火墙规则已配置"
else
    # 使用 iptables
    iptables -I INPUT -p tcp --dport ${USER_PORT} -j ACCEPT
    iptables -I INPUT -p udp --dport ${USER_PORT} -j ACCEPT
    # 保存 iptables 规则
    if command -v iptables-save >/dev/null 2>&1; then
        if [ -d "/etc/iptables" ]; then
            iptables-save > /etc/iptables/rules.v4
        else
            iptables-save > /etc/iptables.rules
        fi
    fi
    echo "iptables 防火墙规则已配置"
fi

# 对于 CentOS/RHEL 系统，配置 firewalld
if command -v firewall-cmd >/dev/null 2>&1; then
    firewall-cmd --permanent --add-port=${USER_PORT}/tcp
    firewall-cmd --permanent --add-port=${USER_PORT}/udp
    firewall-cmd --reload
    echo "firewalld 防火墙规则已配置"
fi

# 创建证书目录
mkdir -p /etc/hysteria

# 生成自签名证书
openssl req -x509 -nodes -newkey rsa:2048 -days 365 \
    -keyout /etc/hysteria/private.key -out /etc/hysteria/cert.crt \
    -subj "/CN=${SERVER_IP}"

# 设置证书权限
chmod 644 /etc/hysteria/cert.crt
chmod 600 /etc/hysteria/private.key

# 下载并安装 Hysteria 2
curl -Lo hysteria https://github.com/apernet/hysteria/releases/download/$HYSTERIA_VERSION/hysteria-linux-amd64
chmod +x hysteria
mv hysteria /usr/local/bin/

# 创建配置文件
cat > /etc/hysteria/config.yaml << EOF
listen: :${USER_PORT}

auth:
  type: password
  password: ${USER_PASSWORD}

masquerade:
  type: proxy
  proxy:
    url: https://news.ycombinator.com/
    rewriteHost: true

log:
  level: info

tls:
  cert: /etc/hysteria/cert.crt
  key: /etc/hysteria/private.key
EOF

# 创建 systemd 服务
cat > /etc/systemd/system/hysteria-server.service << EOF
[Unit]
Description=Hysteria Server Service (config.yaml)
Documentation=https://hysteria.network/
After=network.target nss-lookup.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/hysteria server --config /etc/hysteria/config.yaml
WorkingDirectory=/etc/hysteria
Restart=on-failure
RestartSec=10
LimitNOFILE=infinity

[Install]
WantedBy=multi-user.target
EOF

# 启动服务
systemctl daemon-reload
systemctl enable hysteria-server
systemctl start hysteria-server

# 检查服务状态
systemctl status hysteria-server

# 生成 Hysteria 2 URI
HY2_URI="hy2://${SERVER_IP}:${USER_PORT}?insecure=1&password=${USER_PASSWORD}#Hysteria2"
echo -e "\nHysteria 2 安装完成！"
echo "请检查服务状态确保正常运行。"
echo "配置文件位置：/etc/hysteria/config.yaml"
echo -e "\n=== 连接信息 ==="
echo "服务器IP：$SERVER_IP"
echo "端口：${USER_PORT}"
echo "密码：${USER_PASSWORD}"
echo -e "\n=== 防火墙状态 ==="
# 检查防火墙端口状态
if command -v ufw >/dev/null 2>&1; then
    ufw status | grep ${USER_PORT}
elif command -v firewall-cmd >/dev/null 2>&1; then
    firewall-cmd --list-ports | grep ${USER_PORT}
else
    iptables -L | grep ${USER_PORT}
fi
echo -e "\n=== 订阅链接 ==="
echo "$HY2_URI"
echo -e "\n提示：由于使用自签名证书，客户端需要设置 insecure=1"

# 保存订阅链接到文件
echo "$HY2_URI" > /etc/hysteria/subscription.txt
echo "订阅链接已保存到：/etc/hysteria/subscription.txt" 