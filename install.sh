#!/bin/bash

# 检查是否为 root 用户
if [ "$EUID" -ne 0 ]; then
    echo "请使用 root 用户运行此脚本"
    exit 1
fi

# 显示菜单
show_menu() {
    echo -e "\n=== Hysteria 2 管理脚本 ==="
    echo "1. 全新安装"
    echo "2. 卸载服务"
    echo "3. 查询订阅"
    echo "0. 退出脚本"
    echo "------------------------"
}

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
        
        # 检查是否是 Hysteria 占用
        if pgrep -f "hysteria.*:$port" >/dev/null; then
            echo -e "\n检测到是 Hysteria 服务占用此端口"
            read -p "是否停止 Hysteria 服务并继续安装？[Y/n]: " stop_service
            if [[ $stop_service =~ ^[Yy]$ ]] || [[ -z $stop_service ]]; then
                echo "正在停止 Hysteria 服务..."
                systemctl stop hysteria-server
                sleep 2
                pkill -9 hysteria
                sleep 1
                if ! netstat -tuln | grep -q ":$port "; then
                    echo "端口已释放，继续安装..."
                    return 0
                fi
            fi
        fi
        return 1
    fi
    return 0
}

# 检查 Nginx 配置和服务状态的函数
check_nginx() {
    echo "检查 Nginx 配置和服务状态..."
    
    # 检查 Nginx 是否已安装
    if ! command -v nginx >/dev/null 2>&1; then
        echo "Nginx 未安装，正在安装..."
        apt update
        apt install -y nginx
    else
        echo "检测到已安装的 Nginx，将添加 Hysteria 订阅配置..."
    fi

    # 确保必要的目录存在
    mkdir -p /etc/nginx/conf.d
    mkdir -p /var/log/nginx
    
    # 备份现有的 Hysteria 订阅配置（如果存在）
    if [ -f "/etc/nginx/conf.d/hysteria-subscribe.conf" ]; then
        echo "备份现有的 Hysteria 订阅配置..."
        mv /etc/nginx/conf.d/hysteria-subscribe.conf /etc/nginx/conf.d/hysteria-subscribe.conf.bak
    fi
    
    # 检查 Nginx 配置语法
    echo "检查 Nginx 配置语法..."
    if ! nginx -t; then
        echo "现有 Nginx 配置存在语法错误，请手动检查修复后再运行脚本"
        return 1
    fi
    
    # 检查 Nginx 服务状态
    if ! systemctl is-active nginx >/dev/null 2>&1; then
        echo "Nginx 服务未运行，正在启动..."
        systemctl start nginx
    fi
    
    # 确保 Nginx 开机自启
    systemctl enable nginx
    
    # 最终状态检查
    if systemctl is-active nginx >/dev/null 2>&1; then
        echo "Nginx 服务正在运行"
    else
        echo "警告：Nginx 服务可能未正常运行，请检查日志"
        journalctl -u nginx --no-pager | tail -n 10
        return 1
    fi
}

# 卸载函数
uninstall_hysteria() {
    echo "开始卸载 Hysteria 2..."
    
    # 停止并禁用服务
    systemctl stop hysteria-server
    systemctl disable hysteria-server
    
    # 删除服务文件
    rm -f /etc/systemd/system/hysteria-server.service
    systemctl daemon-reload
    
    # 检查并杀死所有 hysteria 进程
    if pgrep hysteria >/dev/null; then
        echo "正在终止所有 Hysteria 进程..."
        pkill -9 hysteria
        sleep 2
    fi
    
    # 删除主程序
    rm -f /usr/local/bin/hysteria
    
    # 删除配置文件和证书
    rm -rf /etc/hysteria
    
    # 删除 Hysteria 相关的 Nginx 配置
    if [ -f "/etc/nginx/conf.d/hysteria-subscribe.conf" ]; then
        echo "删除 Hysteria 相关的 Nginx 配置..."
        rm -f /etc/nginx/conf.d/hysteria-subscribe.conf
        rm -f /etc/nginx/.htpasswd
        
        # 如果存在备份配置，则恢复
        if [ -f "/etc/nginx/conf.d/hysteria-subscribe.conf.bak" ]; then
            echo "恢复备份的 Nginx 配置..."
            mv /etc/nginx/conf.d/hysteria-subscribe.conf.bak /etc/nginx/conf.d/hysteria-subscribe.conf
        fi
        
        # 重新加载 Nginx 配置
        systemctl reload nginx
    fi
    
    # 删除查询脚本
    rm -f /usr/local/bin/hy2sub
    
    # 检查是否有残留进程
    if pgrep hysteria >/dev/null; then
        echo "警告：仍有 Hysteria 进程在运行，进程信息："
        ps aux | grep hysteria | grep -v grep
        echo "请手动终止这些进程"
    fi
    
    # 检查端口占用
    echo "检查常用端口占用情况..."
    for port in 443 80 8443 2083 2087 2096 8080 8880 9993; do
        if netstat -tuln | grep -q ":$port "; then
            echo "端口 $port 仍被占用，占用情况："
            netstat -tuln | grep ":$port "
            if lsof -i :$port >/dev/null 2>&1; then
                lsof -i :$port
            fi
        fi
    done
    
    echo "Hysteria 2 已完全卸载！"
    echo "Nginx 配置已清理，其他 Nginx 服务不受影响"
}

# 查询订阅信息函数
query_subscription() {
    if [ -f "/etc/hysteria/subscribe/info.txt" ]; then
        echo "=== Hysteria 2 订阅信息 ==="
        cat /etc/hysteria/subscribe/info.txt
        echo -e "\n配置文件位置："
        echo "Clash: /etc/hysteria/subscribe/clash.yaml"
        
        # 显示服务状态
        echo -e "\n=== 服务状态 ==="
        if systemctl is-active hysteria-server >/dev/null 2>&1; then
            echo "服务状态：运行中"
        else
            echo "服务状态：未运行"
        fi
        
        # 显示端口状态
        PORT=$(grep "listen:" /etc/hysteria/config.yaml | awk -F':' '{print $3}')
        if [ ! -z "$PORT" ]; then
            echo -e "\n=== 端口状态 ==="
            netstat -tuln | grep ":$PORT "
        fi
    else
        echo "未找到订阅信息，请确认是否已安装 Hysteria 2"
    fi
}

# 安装前清理检查函数
pre_install_check() {
    echo "执行安装前检查..."
    
    # 检查是否存在旧的 Hysteria 服务
    if systemctl is-active hysteria-server >/dev/null 2>&1; then
        echo "发现正在运行的 Hysteria 服务，正在停止..."
        systemctl stop hysteria-server
        systemctl disable hysteria-server
    fi
    
    # 检查并删除旧的配置文件
    if [ -d "/etc/hysteria" ]; then
        echo "发现旧的配置文件，正在清理..."
        rm -rf /etc/hysteria
    fi
    
    # 检查并删除旧的服务文件
    if [ -f "/etc/systemd/system/hysteria-server.service" ]; then
        echo "清理旧的服务文件..."
        rm -f /etc/systemd/system/hysteria-server.service
        systemctl daemon-reload
    fi
    
    # 检查并删除旧的 Nginx 配置
    if [ -f "/etc/nginx/conf.d/hysteria-subscribe.conf" ]; then
        echo "清理旧的 Nginx 配置..."
        rm -f /etc/nginx/conf.d/hysteria-subscribe.conf
        rm -f /etc/nginx/.htpasswd
        systemctl restart nginx
    fi
    
    # 检查并终止所有 hysteria 进程
    if pgrep hysteria >/dev/null; then
        echo "终止残留的 Hysteria 进程..."
        pkill -9 hysteria
        sleep 2
    fi
    
    echo "清理完成，准备开始安装..."
}

# 安装函数
install_hysteria() {
    # 执行安装前检查
    pre_install_check
    
    # 设置变量
    SERVER_IP=$(curl -s https://api.ipify.org) # 自动获取服务器公网IP
    echo "检测到服务器IP: $SERVER_IP"

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
        if check_port "$USER_PORT"; then
            break
        else
            echo "建议："
            echo "1. 使用其他未被占用的端口"
            echo "2. 常用端口参考："
            echo "   8443, 9443, 2083, 2087, 2096, 8080, 8880, 9993"
            read -p "是否尝试其他端口？[Y/n]: " retry
            if [[ $retry =~ ^[Nn]$ ]]; then
                return 1
            fi
        fi
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
    apt install -y curl openssl net-tools lsof nginx apache2-utils qrencode

    # 检查 Nginx 状态
    check_nginx

    # 配置防火墙
    echo "配置防火墙规则..."
    # 检查是否安装了 UFW
    if command -v ufw >/dev/null 2>&1; then
        # 配置 UFW
        ufw allow ${USER_PORT}/tcp
        ufw allow ${USER_PORT}/udp
        ufw allow 80/tcp
        # 如果 UFW 未启用，启用它
        if ! ufw status | grep -q "Status: active"; then
            ufw --force enable
        fi
        echo "UFW 防火墙规则已配置"
    else
        # 使用 iptables
        iptables -I INPUT -p tcp --dport ${USER_PORT} -j ACCEPT
        iptables -I INPUT -p udp --dport ${USER_PORT} -j ACCEPT
        iptables -I INPUT -p tcp --dport 80 -j ACCEPT
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
        firewall-cmd --permanent --add-port=80/tcp
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
        return 1
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
        return 1
    fi

    # 生成订阅链接
    SUBSCRIBE_PATH=$(openssl rand -hex 16)
    VMESS_NAME="Hysteria2-${SERVER_IP}"

    # 生成订阅密码
    SUBSCRIBE_USER="user_$(openssl rand -hex 4)"
    SUBSCRIBE_PASS=$(openssl rand -base64 8)

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

    # 创建订阅目录
    mkdir -p /etc/hysteria/subscribe
    echo "$CLASH_CONFIG" > /etc/hysteria/subscribe/clash.yaml

    # 配置 Nginx
    cat > /etc/nginx/conf.d/hysteria-subscribe.conf << EOF
server {
    listen 80;
    server_name _;
    
    # 添加访问日志以便调试
    access_log /var/log/nginx/hysteria-subscribe-access.log;
    error_log /var/log/nginx/hysteria-subscribe-error.log;

    location /${SUBSCRIBE_PATH}/clash {
        auth_basic "Subscribe Authentication";
        auth_basic_user_file /etc/nginx/.htpasswd;
        default_type text/plain;
        add_header Content-Type 'text/plain; charset=utf-8';
        return 200 '${CLASH_CONFIG}';
    }
}
EOF

    # 测试 Nginx 配置
    if ! nginx -t; then
        echo "Nginx 配置测试失败，请检查配置文件"
        return 1
    fi

    # 重启 Nginx
    systemctl restart nginx
    
    # 验证 Nginx 是否成功重启
    if ! systemctl is-active nginx >/dev/null 2>&1; then
        echo "警告：Nginx 重启失败，正在尝试修复..."
        systemctl start nginx
        if ! systemctl is-active nginx >/dev/null 2>&1; then
            echo "错误：Nginx 服务无法启动，请检查日志：journalctl -u nginx"
            return 1
        fi
    fi

    # 测试订阅文件是否可访问
    echo "测试订阅链接可访问性..."
    if ! curl -s -I "http://localhost/${SUBSCRIBE_PATH}/clash" | grep -q "401 Unauthorized"; then
        echo "警告：订阅链接可能无法正常访问，请检查 Nginx 配置"
        echo "Nginx 错误日志："
        tail -n 10 /var/log/nginx/error.log
    else
        echo "订阅链接测试正常（需要认证）"
    fi

    # 保存订阅信息
    cat > /etc/hysteria/subscribe/info.txt << EOF
订阅用户名：${SUBSCRIBE_USER}
订阅密码：${SUBSCRIBE_PASS}
Clash 订阅链接：http://${SERVER_IP}/${SUBSCRIBE_PATH}/clash

注意：目前 QuantumultX 不支持 Hysteria2 协议
EOF

    # 创建查询脚本
    cat > /usr/local/bin/hy2sub << 'EOF'
#!/bin/bash

if [ -f "/etc/hysteria/subscribe/info.txt" ]; then
    echo "=== Hysteria 2 订阅信息 ==="
    cat /etc/hysteria/subscribe/info.txt
    echo -e "\n配置文件位置："
    echo "Clash: /etc/hysteria/subscribe/clash.yaml"
    
    # 获取订阅链接
    SUBSCRIBE_LINK=$(grep "Clash 订阅链接：" /etc/hysteria/subscribe/info.txt | cut -d' ' -f2)
    
    if [ ! -z "$SUBSCRIBE_LINK" ]; then
        echo -e "\n=== 订阅二维码 ==="
        echo "扫描下方二维码可直接导入配置："
        qrencode -t ANSIUTF8 "$SUBSCRIBE_LINK"
    fi
else
    echo "未找到订阅信息，请确认是否已安装 Hysteria 2"
fi
EOF

    chmod +x /usr/local/bin/hy2sub

    echo -e "\nHysteria 2 安装完成！"
    echo "配置文件位置：/etc/hysteria/config.yaml"
    echo -e "\n=== 连接信息 ==="
    echo "服务器IP：$SERVER_IP"
    echo "端口：${USER_PORT}"
    echo "密码：${USER_PASSWORD}"
    
    echo -e "\n=== 订阅信息 ==="
    echo "订阅用户名：$SUBSCRIBE_USER"
    echo "订阅密码：$SUBSCRIBE_PASS"
    echo -e "\n=== 订阅链接 ==="
    echo "Clash 订阅链接：http://${SERVER_IP}/${SUBSCRIBE_PATH}/clash"
    echo -e "\n=== 订阅二维码 ==="
    echo "扫描下方二维码可直接导入配置："
    SUBSCRIBE_LINK="http://${SERVER_IP}/${SUBSCRIBE_PATH}/clash"
    qrencode -t ANSIUTF8 "$SUBSCRIBE_LINK"
    
    echo -e "\n提示："
    echo "1. 订阅链接需要使用用户名和密码认证"
    echo "2. 由于使用自签名证书，客户端需要开启跳过证书验证"
    echo "3. 订阅信息已保存到：/etc/hysteria/subscribe/"
    echo "4. 使用 'hy2sub' 命令可随时查看订阅信息"
    echo "5. 注意：目前 QuantumultX 不支持 Hysteria2 协议"
    echo -e "\n=== iOS 客户端支持 ==="
    echo "支持的客户端（版本要求）："
    echo "1. Shadowrocket (v2.2.35+) - 推荐，性价比高"
    echo "2. Stash (v2.5.0+)"
    echo "3. Loon (v3.1.3+)"
    echo "4. Surge (v5.8.0+)"
    echo "5. Streisand (v1.5.6+)"
    echo "6. Pharos Pro (v1.8.3+)"
    echo "7. Egern (v1.14.0+)"
}

# 主菜单循环
while true; do
    show_menu
    read -p "请输入选项 [0-3]: " choice
    
    case $choice in
        1)
            echo "开始全新安装..."
            install_hysteria
            ;;
        2)
            echo "即将卸载 Hysteria 2..."
            read -p "确定要卸载吗？(y/n): " confirm
            if [[ $confirm =~ ^[Yy]$ ]]; then
                uninstall_hysteria
            fi
            ;;
        3)
            query_subscription
            ;;
        0)
            echo "退出脚本..."
            exit 0
            ;;
        *)
            echo "无效的选项，请重新选择"
            ;;
    esac
    
    echo -e "\n按回车键继续..."
    read
done 