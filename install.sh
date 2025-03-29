#!/bin/bash

# 检查是否为 root 用户
if [ "$EUID" -ne 0 ]; then
    echo "请使用 root 用户运行此脚本"
    exit 1
fi

# 设置变量
SERVER_IP=$(curl -s https://api.ipify.org) # 自动获取服务器公网IP
echo "检测到服务器IP: $SERVER_IP"

# 检查并显示端口占用情况的函数
check_port() {
    local port=$1
    echo "检查端口 $port 占用情况..."
    if netstat -tuln | grep -q ":$port "; then
        echo "端口 $port 已被占用，占用情况如下："
        netstat -tuln | grep ":$port "
        if lsof -i :$port >/dev/null 2>&1; then
            echo "占用进程信息："
            lsof -i :$port
        fi
        return 1
    fi
    return 0
}

# 提示用户输入端口
while true; do
    read -p "请设置服务端口 (直接回车默认443): " USER_PORT
    if [ -z "$USER_PORT" ]; then
        USER_PORT="443"
        echo "使用默认端口: 443"
    fi

    # 检查端口是否为数字且在有效范围内
    if ! [[ "$USER_PORT" =~ ^[0-9]+$ ]] || [ "$USER_PORT" -lt 1 ] || [ "$USER_PORT" -gt 65535 ]; then
        echo "错误：端口必须是1-65535之间的数字"
        continue
    fi

    # 检查端口占用
    if ! check_port "$USER_PORT"; then
        echo "建议："
        echo "1. 使用其他未被占用的端口"
        echo "2. 或者停止占用该端口的服务："
        echo "   systemctl stop 服务名"
        echo "3. 常用端口参考："
        echo "   8443, 9443, 2083, 2087, 2096, 8080, 8880, 9993"
        read -p "是否尝试其他端口？[Y/n]: " retry
        if [[ $retry =~ ^[Nn]$ ]]; then
            exit 1
        fi
        continue
    fi
    break
done

# 提示用户输入密码
read -p "请设置访问密码 (如果直接回车将生成随机密码): " USER_PASSWORD
if [ -z "$USER_PASSWORD" ]; then
    # 生成随机密码 (16位字母数字组合)
    USER_PASSWORD=$(openssl rand -base64 12)
    echo "已生成随机密码: $USER_PASSWORD"
fi

# 安装必要的软件包
apt update
apt install -y curl openssl net-tools lsof nginx apache2-utils

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

# 安装 Hysteria 2
echo "安装 Hysteria 2..."
curl -fsSL https://get.hy2.sh/ | bash

# 验证安装
if ! command -v hysteria >/dev/null 2>&1; then
    echo "错误：Hysteria 2 安装失败"
    exit 1
fi

echo "验证 Hysteria 2 版本..."
hysteria version

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
systemctl stop hysteria-server >/dev/null 2>&1
sleep 2
systemctl start hysteria-server

# 等待服务启动
echo "等待服务启动..."
sleep 5

# 检查服务状态（使用非交互式方式）
echo -e "\n=== 服务状态 ==="
if systemctl is-active hysteria-server >/dev/null 2>&1; then
    echo "Hysteria 服务已成功启动并正在运行"
else
    echo "警告：Hysteria 服务未能正常启动，错误日志如下："
    journalctl -u hysteria-server -n 10 --no-pager
    echo -e "\n可能的解决方案："
    echo "1. 检查端口 ${USER_PORT} 是否被其他服务占用"
    echo "2. 检查系统防火墙设置"
    echo "3. 查看完整日志：journalctl -u hysteria-server -n 50"
fi

# 生成订阅链接
SUBSCRIBE_PATH=$(openssl rand -hex 16)
VMESS_NAME="Hysteria2-${SERVER_IP}"

# 生成订阅密码
SUBSCRIBE_USER="user_$(openssl rand -hex 4)"
SUBSCRIBE_PASS=$(openssl rand -base64 8)
echo "订阅用户名：$SUBSCRIBE_USER"
echo "订阅密码：$SUBSCRIBE_PASS"

# 创建认证文件
htpasswd -bc /etc/nginx/.htpasswd "$SUBSCRIBE_USER" "$SUBSCRIBE_PASS"

# 生成配置文件
CLASH_CONFIG=$(cat << EOF
proxies:
  - name: "$VMESS_NAME"
    type: hysteria2
    server: ${SERVER_IP}
    port: ${USER_PORT}
    password: "${USER_PASSWORD}"
    sni: ${SERVER_IP}
    skip-cert-verify: true

proxy-groups:
  - name: "🚀 节点选择"
    type: select
    proxies:
      - "$VMESS_NAME"
      - DIRECT

rules:
  - MATCH,🚀 节点选择
EOF
)

QUANX_CONFIG="hysteria2=${SERVER_IP}:${USER_PORT}, password=${USER_PASSWORD}, skip-cert-verify=true, sni=${SERVER_IP}, tag=Hysteria2-${SERVER_IP}"

# 创建订阅目录
mkdir -p /etc/hysteria/subscribe
echo "$CLASH_CONFIG" > /etc/hysteria/subscribe/clash.yaml
echo "$QUANX_CONFIG" > /etc/hysteria/subscribe/quanx.conf

# 配置 Nginx
cat > /etc/nginx/conf.d/hysteria-subscribe.conf << EOF
server {
    listen 80;
    server_name _;

    location /${SUBSCRIBE_PATH}/clash {
        auth_basic "Subscribe Authentication";
        auth_basic_user_file /etc/nginx/.htpasswd;
        alias /etc/hysteria/subscribe/clash.yaml;
        default_type text/plain;
        add_header Content-Type 'text/plain; charset=utf-8';
    }

    location /${SUBSCRIBE_PATH}/quanx {
        auth_basic "Subscribe Authentication";
        auth_basic_user_file /etc/nginx/.htpasswd;
        alias /etc/hysteria/subscribe/quanx.conf;
        default_type text/plain;
        add_header Content-Type 'text/plain; charset=utf-8';
    }
}
EOF

# 重启 Nginx
systemctl restart nginx

echo -e "\nHysteria 2 安装完成！"
echo "配置文件位置：/etc/hysteria/config.yaml"
echo -e "\n=== 连接信息 ==="
echo "服务器IP：$SERVER_IP"
echo "端口：${USER_PORT}"
echo "密码：${USER_PASSWORD}"
echo -e "\n=== 防火墙状态 ==="
# 检查防火墙端口状态
if command -v ufw >/dev/null 2>&1; then
    ufw allow 80/tcp
    ufw status | grep -E "${USER_PORT}|80"
elif command -v firewall-cmd >/dev/null 2>&1; then
    firewall-cmd --permanent --add-port=80/tcp
    firewall-cmd --reload
    firewall-cmd --list-ports | grep -E "${USER_PORT}|80"
else
    iptables -I INPUT -p tcp --dport 80 -j ACCEPT
    iptables -L | grep -E "${USER_PORT}|80"
fi

echo -e "\n=== 订阅信息 ==="
echo "订阅用户名：$SUBSCRIBE_USER"
echo "订阅密码：$SUBSCRIBE_PASS"
echo -e "\n=== 订阅链接 ==="
echo "Clash 订阅链接：http://${SERVER_IP}/${SUBSCRIBE_PATH}/clash"
echo "QuantumultX 订阅链接：http://${SERVER_IP}/${SUBSCRIBE_PATH}/quanx"
echo -e "\n提示："
echo "1. 订阅链接需要使用用户名和密码认证"
echo "2. 由于使用自签名证书，客户端需要开启跳过证书验证"
echo "3. 订阅信息已保存到：/etc/hysteria/subscribe/"

# 保存订阅信息
cat > /etc/hysteria/subscribe/info.txt << EOF
订阅用户名：${SUBSCRIBE_USER}
订阅密码：${SUBSCRIBE_PASS}
Clash 订阅链接：http://${SERVER_IP}/${SUBSCRIBE_PATH}/clash
QuantumultX 订阅链接：http://${SERVER_IP}/${SUBSCRIBE_PATH}/quanx
EOF

# 创建查询脚本
cat > /usr/local/bin/hy2sub << 'EOF'
#!/bin/bash

if [ -f "/etc/hysteria/subscribe/info.txt" ]; then
    echo "=== Hysteria 2 订阅信息 ==="
    cat /etc/hysteria/subscribe/info.txt
    echo -e "\n配置文件位置："
    echo "Clash: /etc/hysteria/subscribe/clash.yaml"
    echo "QuantumultX: /etc/hysteria/subscribe/quanx.conf"
else
    echo "未找到订阅信息，请确认是否已安装 Hysteria 2"
fi
EOF

chmod +x /usr/local/bin/hy2sub

echo -e "\n=== 查询命令 ==="
echo "使用 'hy2sub' 命令可随时查看订阅信息"

# 显示服务管理命令
echo -e "\n=== 服务管理命令 ==="
echo "启动服务：systemctl start hysteria-server"
echo "停止服务：systemctl stop hysteria-server"
echo "重启服务：systemctl restart hysteria-server"
echo "查看状态：systemctl status hysteria-server"
echo "查看日志：journalctl -u hysteria-server -n 50" 