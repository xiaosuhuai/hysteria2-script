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
    echo "4. 查询连接"
    echo "5. 更新域名证书"
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

# 检查域名解析是否正确
check_domain() {
    local domain=$1
    local expected_ip=$2
    local resolved_ip
    
    echo "正在检查域名 $domain 的解析..."
    
    # 尝试使用 dig 获取域名解析
    if command -v dig >/dev/null 2>&1; then
        resolved_ip=$(dig +short "$domain" | grep -v "\.$" | head -n 1)
    # 如果没有 dig，尝试使用 host
    elif command -v host >/dev/null 2>&1; then
        resolved_ip=$(host "$domain" | grep "has address" | head -n 1 | awk '{print $NF}')
    # 如果都没有，尝试使用 nslookup
    elif command -v nslookup >/dev/null 2>&1; then
        resolved_ip=$(nslookup "$domain" | grep -A1 "Name:" | grep "Address:" | tail -n 1 | awk '{print $NF}')
    else
        echo "错误：未找到 DNS 查询工具，请安装 dig、host 或 nslookup"
        return 1
    fi
    
    if [ -z "$resolved_ip" ]; then
        echo "错误：无法解析域名 $domain"
        return 1
    fi
    
    if [ "$resolved_ip" != "$expected_ip" ]; then
        echo "错误：域名 $domain 解析到的 IP ($resolved_ip) 与服务器 IP ($expected_ip) 不匹配"
        return 1
    fi
    
    echo "域名解析检查通过"
    return 0
}

# 申请 Let's Encrypt 证书
setup_ssl() {
    local domain=$1
    
    # 安装 certbot
    if ! command -v certbot >/dev/null 2>&1; then
        echo "正在安装 certbot..."
        apt update
        apt install -y certbot python3-certbot-nginx
    fi
    
    # 申请证书
    echo "正在申请 SSL 证书..."
    if certbot certonly --nginx -d "$domain" --non-interactive --agree-tos --email "admin@$domain" --expand; then
        echo "SSL 证书申请成功"
        # 复制证书到 Hysteria 目录
        cp "/etc/letsencrypt/live/$domain/fullchain.pem" /etc/hysteria/cert.crt
        cp "/etc/letsencrypt/live/$domain/privkey.pem" /etc/hysteria/private.key
        chmod 644 /etc/hysteria/cert.crt
        chmod 600 /etc/hysteria/private.key
        return 0
    else
        echo "SSL 证书申请失败"
        return 1
    fi
}

# 设置自动续期证书的 hook
setup_renewal_hook() {
    local domain=$1
    cat > /etc/letsencrypt/renewal-hooks/deploy/hysteria.sh << EOF
#!/bin/bash
cp "/etc/letsencrypt/live/$domain/fullchain.pem" /etc/hysteria/cert.crt
cp "/etc/letsencrypt/live/$domain/privkey.pem" /etc/hysteria/private.key
chmod 644 /etc/hysteria/cert.crt
chmod 600 /etc/hysteria/private.key
systemctl restart hysteria-server
EOF
    chmod +x /etc/letsencrypt/renewal-hooks/deploy/hysteria.sh
}

# 更新证书函数
update_cert() {
    if [ ! -f "/etc/hysteria/config.yaml" ]; then
        echo "未找到 Hysteria 配置文件，请先安装 Hysteria"
        return 1
    fi
    
    # 获取当前域名
    local current_domain=$(grep "sni:" /etc/hysteria/config.yaml | awk '{print $2}')
    if [ -z "$current_domain" ]; then
        echo "未找到配置的域名"
        return 1
    fi
    
    echo "当前域名: $current_domain"
    echo "正在更新证书..."
    
    if certbot renew --force-renewal -d "$current_domain"; then
        echo "证书更新成功"
        # 复制新证书
        cp "/etc/letsencrypt/live/$current_domain/fullchain.pem" /etc/hysteria/cert.crt
        cp "/etc/letsencrypt/live/$current_domain/privkey.pem" /etc/hysteria/private.key
        chmod 644 /etc/hysteria/cert.crt
        chmod 600 /etc/hysteria/private.key
        
        # 重启服务
        systemctl restart hysteria-server
        echo "服务已重启，新证书生效"
        return 0
    else
        echo "证书更新失败"
        return 1
    fi
}

# 安装函数
install_hysteria() {
    # 执行安装前检查
    pre_install_check
    
    # 设置变量
    SERVER_IP=$(curl -s https://api.ipify.org) # 自动获取服务器公网IP
    echo "检测到服务器IP: $SERVER_IP"

    # 询问是否使用域名
    read -p "是否使用域名？[y/N]: " USE_DOMAIN
    if [[ $USE_DOMAIN =~ ^[Yy]$ ]]; then
        while true; do
            read -p "请输入您的域名: " DOMAIN
            if [ -z "$DOMAIN" ]; then
                echo "域名不能为空，请重新输入"
                continue
            fi
            
            # 检查域名解析
            if check_domain "$DOMAIN" "$SERVER_IP"; then
                break
            else
                echo "请确保域名已正确解析到服务器IP后再继续"
                read -p "是否重新输入域名？[Y/n]: " retry_domain
                if [[ $retry_domain =~ ^[Nn]$ ]]; then
                    echo "将使用服务器IP继续安装"
                    DOMAIN=""
                    break
                fi
            fi
        done
    fi

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

    # 询问用户是否使用HTTPS
    if [ -z "$DOMAIN" ]; then
        echo "提示：订阅链接使用HTTP更易于客户端导入，HTTPS可能会因自签名证书导致导入失败"
        read -p "是否为订阅链接启用HTTPS? (自签名证书可能导致导入问题) [y/N]: " USE_HTTPS_CHOICE
        if [[ $USE_HTTPS_CHOICE =~ ^[Yy]$ ]]; then
            echo "将为订阅链接启用HTTPS..."
            echo "警告：如果订阅导入失败，请尝试关闭证书验证或重新安装并选择HTTP"
            USE_HTTPS="true"
        else
            echo "将使用HTTP协议用于订阅链接..."
            USE_HTTPS="false"
        fi
    else
        USE_HTTPS="true"
    fi

    # 安装必要的软件包
    apt update
    apt install -y curl openssl net-tools lsof nginx apache2-utils qrencode ifstat iftop dnsutils

    # 检查 Nginx 状态
    check_nginx

    # 如果使用域名，设置SSL证书
    if [ ! -z "$DOMAIN" ]; then
        if ! setup_ssl "$DOMAIN"; then
            echo "SSL证书配置失败，退出安装"
            return 1
        fi
        setup_renewal_hook "$DOMAIN"
    else
        # 生成自签名证书
        openssl req -x509 -nodes -newkey rsa:2048 -days 365 \
            -keyout /etc/hysteria/private.key -out /etc/hysteria/cert.crt \
            -subj "/CN=${SERVER_IP}"
        
        chmod 644 /etc/hysteria/cert.crt
        chmod 600 /etc/hysteria/private.key
    fi

    # 配置防火墙
    echo "配置防火墙规则..."
    # 检查是否安装了 UFW
    if command -v ufw >/dev/null 2>&1; then
        # 配置 UFW
        ufw allow ${USER_PORT}/tcp
        ufw allow ${USER_PORT}/udp
        ufw allow 80/tcp
        ufw allow 443/tcp
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
        iptables -I INPUT -p tcp --dport 443 -j ACCEPT
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
        firewall-cmd --permanent --add-port=443/tcp
        firewall-cmd --reload
        echo "firewalld 防火墙规则已配置"
    fi

    # 创建证书目录
    mkdir -p /etc/hysteria

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

    # 如果使用域名，添加SNI配置
    if [ ! -z "$DOMAIN" ]; then
        echo "  sni: ${DOMAIN}" >> /etc/hysteria/config.yaml
    fi

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
    
    # 根据用户选择决定是否使用HTTPS
    if [ "$USE_HTTPS" = "true" ] && [ -f "/etc/hysteria/cert.crt" ] && [ -f "/etc/hysteria/private.key" ]; then
        echo "配置HTTPS..."
        PROTOCOL="https"
        # 复制证书到Nginx目录
        cp /etc/hysteria/cert.crt /etc/nginx/cert.crt
        cp /etc/hysteria/private.key /etc/nginx/private.key
        chmod 644 /etc/nginx/cert.crt
        chmod 600 /etc/nginx/private.key
    else
        if [ "$USE_HTTPS" = "true" ]; then
            echo "未找到SSL证书或配置失败，回退到HTTP协议..."
        else
            echo "按照用户选择，使用HTTP协议..."
        fi
        USE_HTTPS="false"
        PROTOCOL="http"
    fi
    
    BASE_SUBSCRIBE_URL="${PROTOCOL}://${SERVER_IP}/${SUBSCRIBE_PATH}/clash"

    # 直接使用订阅链接，不再包含用户名和密码
    FULL_SUBSCRIBE_URL="${PROTOCOL}://${SERVER_IP}/${SUBSCRIBE_PATH}/clash"
    
    # Base64 编码处理订阅地址（用于小火箭）
    BASE64_URL=$(echo -n "${FULL_SUBSCRIBE_URL}" | base64 | tr -d '\n')
    
    # 使用特殊格式以确保客户端兼容性
    if [ "$PROTOCOL" = "https" ]; then
        SHADOWROCKET_URL="sub://${BASE64_URL}#Hysteria2-${SERVER_IP}-HTTPS"
    else
        SHADOWROCKET_URL="sub://${BASE64_URL}#Hysteria2-${SERVER_IP}"
    fi

    # 生成Clash配置文件头部
    CLASH_CONFIG_HEADER=$(cat << EOF
mixed-port: 7890
allow-lan: true
mode: rule
log-level: info
external-controller: 127.0.0.1:9090

dns:
  enable: true
  listen: 0.0.0.0:53
  enhanced-mode: fake-ip
  nameserver:
    - 223.5.5.5
    - 119.29.29.29
    - 114.114.114.114

proxies:
  - name: "$VMESS_NAME"
    type: hysteria2
    server: ${SERVER_IP}
    port: ${USER_PORT}
    password: "${USER_PASSWORD}"
    sni: ${SERVER_IP}
    skip-cert-verify: true
EOF
)

    # 下载ACL4SSR的规则配置
    echo "正在获取ACL4SSR规则..."
    
    # 检查是否存在curl工具
    if ! command -v curl &> /dev/null; then
        apt update
        apt install -y curl
    fi
    
    # 下载clash规则配置
    CLASH_RULES=$(curl -s https://raw.githubusercontent.com/ACL4SSR/ACL4SSR/master/Clash/config/ACL4SSR_Online_Mini.ini | grep -v "^\[" | grep -v "^;" | grep -v "^$")
    
    # 如果下载失败，使用备用方案
    if [ -z "$CLASH_RULES" ]; then
        echo "无法从GitHub获取规则，使用备用配置..."
        
        # 使用备用的简化规则
        CLASH_RULES=$(cat << EOF
proxy-groups:
  - name: 🚀 节点选择
    type: select
    proxies:
      - "$VMESS_NAME"
      - DIRECT
  - name: 🌍 国外网站
    type: select
    proxies:
      - 🚀 节点选择
      - DIRECT
  - name: 📲 电报信息
    type: select
    proxies:
      - 🚀 节点选择
      - DIRECT
  - name: 🎬 国外媒体
    type: select
    proxies:
      - 🚀 节点选择
      - DIRECT
  - name: 📹 YouTube
    type: select
    proxies:
      - 🚀 节点选择
      - DIRECT
  - name: 🎥 Netflix
    type: select
    proxies:
      - 🚀 节点选择
      - DIRECT
  - name: 🌏 国内网站
    type: select
    proxies:
      - DIRECT
      - 🚀 节点选择
  - name: 🐟 漏网之鱼
    type: select
    proxies:
      - 🚀 节点选择
      - DIRECT

rules:
  - DOMAIN-SUFFIX,t.me,📲 电报信息
  - DOMAIN-SUFFIX,telegram.org,📲 电报信息
  - IP-CIDR,91.108.4.0/22,📲 电报信息
  - IP-CIDR,91.108.8.0/22,📲 电报信息
  - IP-CIDR,91.108.12.0/22,📲 电报信息
  - IP-CIDR,91.108.16.0/22,📲 电报信息
  - IP-CIDR,91.108.56.0/22,📲 电报信息
  - IP-CIDR,149.154.160.0/20,📲 电报信息
  - DOMAIN-KEYWORD,youtube,📹 YouTube
  - DOMAIN-SUFFIX,youtube.com,📹 YouTube
  - DOMAIN-SUFFIX,googlevideo.com,📹 YouTube
  - DOMAIN-KEYWORD,netflix,🎥 Netflix
  - DOMAIN-SUFFIX,netflix.com,🎥 Netflix
  - DOMAIN-SUFFIX,netflix.net,🎥 Netflix
  - DOMAIN-SUFFIX,google.com,🌍 国外网站
  - DOMAIN-SUFFIX,gmail.com,🌍 国外网站
  - DOMAIN-SUFFIX,facebook.com,🌍 国外网站
  - DOMAIN-SUFFIX,twitter.com,🌍 国外网站
  - DOMAIN-SUFFIX,instagram.com,🌍 国外网站
  - DOMAIN-SUFFIX,wikipedia.org,🌍 国外网站
  - DOMAIN-SUFFIX,reddit.com,🌍 国外网站
  - DOMAIN-SUFFIX,spotify.com,🎬 国外媒体
  - DOMAIN-SUFFIX,disney.com,🎬 国外媒体
  - DOMAIN-SUFFIX,hbo.com,🎬 国外媒体
  - DOMAIN-SUFFIX,hulu.com,🎬 国外媒体
  - GEOIP,CN,🌏 国内网站
  - MATCH,🐟 漏网之鱼
EOF
        )
    else
        # 处理下载的规则，提取出proxy-groups和rules部分
        echo "成功获取ACL4SSR规则，正在处理..."
        
        # 获取完整规则配置
        ACL4SSR_CONFIG=$(curl -s https://raw.githubusercontent.com/ACL4SSR/ACL4SSR/master/Clash/config/ACL4SSR_Online_Mini_MultiMode.ini)
        
        # 构建规则
        CLASH_RULES=$(cat << EOF
proxy-groups:
  - name: 🚀 节点选择
    type: select
    proxies:
      - "$VMESS_NAME"
      - DIRECT
  - name: ♻️ 自动选择
    type: url-test
    url: http://www.gstatic.com/generate_204
    interval: 300
    tolerance: 50
    proxies:
      - "$VMESS_NAME"
  - name: 🌍 国外媒体
    type: select
    proxies:
      - 🚀 节点选择
      - ♻️ 自动选择
      - 🎯 全球直连
  - name: 📲 电报信息
    type: select
    proxies:
      - 🚀 节点选择
      - 🎯 全球直连
  - name: Ⓜ️ 微软服务
    type: select
    proxies:
      - 🎯 全球直连
      - 🚀 节点选择
  - name: 🍎 苹果服务
    type: select
    proxies:
      - 🚀 节点选择
      - 🎯 全球直连
  - name: 📢 谷歌FCM
    type: select
    proxies:
      - 🚀 节点选择
      - 🎯 全球直连
  - name: 🎯 全球直连
    type: select
    proxies:
      - DIRECT
  - name: 🛑 全球拦截
    type: select
    proxies:
      - REJECT
      - DIRECT
  - name: 🍃 应用净化
    type: select
    proxies:
      - REJECT
      - DIRECT
  - name: 🐟 漏网之鱼
    type: select
    proxies:
      - 🚀 节点选择
      - 🎯 全球直连
      
rules:
  - DOMAIN-SUFFIX,acl4.ssr,🎯 全球直连
  - DOMAIN-SUFFIX,ip6-localhost,🎯 全球直连
  - DOMAIN-SUFFIX,ip6-loopback,🎯 全球直连
  - DOMAIN-SUFFIX,local,🎯 全球直连
  - DOMAIN-SUFFIX,localhost,🎯 全球直连
  - IP-CIDR,10.0.0.0/8,🎯 全球直连,no-resolve
  - IP-CIDR,100.64.0.0/10,🎯 全球直连,no-resolve
  - IP-CIDR,127.0.0.0/8,🎯 全球直连,no-resolve
  - IP-CIDR,172.16.0.0/12,🎯 全球直连,no-resolve
  - IP-CIDR,192.168.0.0/16,🎯 全球直连,no-resolve
  - IP-CIDR,198.18.0.0/16,🎯 全球直连,no-resolve
  - IP-CIDR6,::1/128,🎯 全球直连,no-resolve
  - IP-CIDR6,fc00::/7,🎯 全球直连,no-resolve
  - IP-CIDR6,fe80::/10,🎯 全球直连,no-resolve
  - IP-CIDR6,fd00::/8,🎯 全球直连,no-resolve
  - DOMAIN-SUFFIX,msftconnecttest.com,🎯 全球直连
  - DOMAIN-SUFFIX,msftncsi.com,🎯 全球直连
  - DOMAIN,api.steampowered.com,🎯 全球直连
  - DOMAIN,download.jetbrains.com,🎯 全球直连
  - DOMAIN-KEYWORD,1drv,Ⓜ️ 微软服务
  - DOMAIN-KEYWORD,microsoft,Ⓜ️ 微软服务
  - DOMAIN-SUFFIX,aadrm.com,Ⓜ️ 微软服务
  - DOMAIN-SUFFIX,acompli.com,Ⓜ️ 微软服务
  - DOMAIN-SUFFIX,aspnetcdn.com,Ⓜ️ 微软服务
  - DOMAIN-SUFFIX,assets-yammer.com,Ⓜ️ 微软服务
  - DOMAIN-SUFFIX,azure.com,Ⓜ️ 微软服务
  - DOMAIN-SUFFIX,azure.net,Ⓜ️ 微软服务
  - DOMAIN-SUFFIX,azureedge.net,Ⓜ️ 微软服务
  - DOMAIN-SUFFIX,azurerms.com,Ⓜ️ 微软服务
  - DOMAIN-SUFFIX,bing.com,Ⓜ️ 微软服务
  - DOMAIN-SUFFIX,cloudapp.net,Ⓜ️ 微软服务
  - DOMAIN-SUFFIX,cloudappsecurity.com,Ⓜ️ 微软服务
  - DOMAIN-SUFFIX,edgesuite.net,Ⓜ️ 微软服务
  - DOMAIN-SUFFIX,gfx.ms,Ⓜ️ 微软服务
  - DOMAIN-SUFFIX,hotmail.com,Ⓜ️ 微软服务
  - DOMAIN-SUFFIX,live.com,Ⓜ️ 微软服务
  - DOMAIN-SUFFIX,live.net,Ⓜ️ 微软服务
  - DOMAIN-SUFFIX,lync.com,Ⓜ️ 微软服务
  - DOMAIN-SUFFIX,msappproxy.net,Ⓜ️ 微软服务
  - DOMAIN-SUFFIX,msauth.net,Ⓜ️ 微软服务
  - DOMAIN-SUFFIX,msauthimages.net,Ⓜ️ 微软服务
  - DOMAIN-SUFFIX,msecnd.net,Ⓜ️ 微软服务
  - DOMAIN-SUFFIX,msedge.net,Ⓜ️ 微软服务
  - DOMAIN-SUFFIX,msft.net,Ⓜ️ 微软服务
  - DOMAIN-SUFFIX,msftauth.net,Ⓜ️ 微软服务
  - DOMAIN-SUFFIX,msftauthimages.net,Ⓜ️ 微软服务
  - DOMAIN-SUFFIX,msftidentity.com,Ⓜ️ 微软服务
  - DOMAIN-SUFFIX,msidentity.com,Ⓜ️ 微软服务
  - DOMAIN-SUFFIX,msn.com,Ⓜ️ 微软服务
  - DOMAIN-SUFFIX,msocdn.com,Ⓜ️ 微软服务
  - DOMAIN-SUFFIX,msocsp.com,Ⓜ️ 微软服务
  - DOMAIN-SUFFIX,mstea.ms,Ⓜ️ 微软服务
  - DOMAIN-SUFFIX,o365weve.com,Ⓜ️ 微软服务
  - DOMAIN-SUFFIX,oaspapps.com,Ⓜ️ 微软服务
  - DOMAIN-SUFFIX,office.com,Ⓜ️ 微软服务
  - DOMAIN-SUFFIX,office.net,Ⓜ️ 微软服务
  - DOMAIN-SUFFIX,office365.com,Ⓜ️ 微软服务
  - DOMAIN-SUFFIX,officeppe.net,Ⓜ️ 微软服务
  - DOMAIN-SUFFIX,omniroot.com,Ⓜ️ 微软服务
  - DOMAIN-SUFFIX,onedrive.com,Ⓜ️ 微软服务
  - DOMAIN-SUFFIX,onenote.com,Ⓜ️ 微软服务
  - DOMAIN-SUFFIX,onenote.net,Ⓜ️ 微软服务
  - DOMAIN-SUFFIX,onestore.ms,Ⓜ️ 微软服务
  - DOMAIN-SUFFIX,outlook.com,Ⓜ️ 微软服务
  - DOMAIN-SUFFIX,outlookmobile.com,Ⓜ️ 微软服务
  - DOMAIN-SUFFIX,phonefactor.net,Ⓜ️ 微软服务
  - DOMAIN-SUFFIX,public-trust.com,Ⓜ️ 微软服务
  - DOMAIN-SUFFIX,sfbassets.com,Ⓜ️ 微软服务
  - DOMAIN-SUFFIX,sfx.ms,Ⓜ️ 微软服务
  - DOMAIN-SUFFIX,sharepoint.com,Ⓜ️ 微软服务
  - DOMAIN-SUFFIX,sharepointonline.com,Ⓜ️ 微软服务
  - DOMAIN-SUFFIX,skype.com,Ⓜ️ 微软服务
  - DOMAIN-SUFFIX,skypeassets.com,Ⓜ️ 微软服务
  - DOMAIN-SUFFIX,skypeforbusiness.com,Ⓜ️ 微软服务
  - DOMAIN-SUFFIX,staffhub.ms,Ⓜ️ 微软服务
  - DOMAIN-SUFFIX,svc.ms,Ⓜ️ 微软服务
  - DOMAIN-SUFFIX,sway-cdn.com,Ⓜ️ 微软服务
  - DOMAIN-SUFFIX,sway-extensions.com,Ⓜ️ 微软服务
  - DOMAIN-SUFFIX,sway.com,Ⓜ️ 微软服务
  - DOMAIN-SUFFIX,trafficmanager.net,Ⓜ️ 微软服务
  - DOMAIN-SUFFIX,uservoice.com,Ⓜ️ 微软服务
  - DOMAIN-SUFFIX,virtualearth.net,Ⓜ️ 微软服务
  - DOMAIN-SUFFIX,visualstudio.com,Ⓜ️ 微软服务
  - DOMAIN-SUFFIX,windows-ppe.net,Ⓜ️ 微软服务
  - DOMAIN-SUFFIX,windows.com,Ⓜ️ 微软服务
  - DOMAIN-SUFFIX,windows.net,Ⓜ️ 微软服务
  - DOMAIN-SUFFIX,windowsazure.com,Ⓜ️ 微软服务
  - DOMAIN-SUFFIX,windowsupdate.com,Ⓜ️ 微软服务
  - DOMAIN-SUFFIX,wunderlist.com,Ⓜ️ 微软服务
  - DOMAIN-SUFFIX,yammer.com,Ⓜ️ 微软服务
  - DOMAIN-SUFFIX,yammerusercontent.com,Ⓜ️ 微软服务
  - DOMAIN,apple.comscoreresearch.com,🍎 苹果服务
  - DOMAIN-KEYWORD,apple.com.akadns,🍎 苹果服务
  - DOMAIN-KEYWORD,icloud.com.akadns,🍎 苹果服务
  - DOMAIN-SUFFIX,aaplimg.com,🍎 苹果服务
  - DOMAIN-SUFFIX,apple-cloudkit.com,🍎 苹果服务
  - DOMAIN-SUFFIX,apple.co,🍎 苹果服务
  - DOMAIN-SUFFIX,apple.com,🍎 苹果服务
  - DOMAIN-SUFFIX,apple.com.cn,🍎 苹果服务
  - DOMAIN-SUFFIX,appstore.com,🍎 苹果服务
  - DOMAIN-SUFFIX,cdn-apple.com,🍎 苹果服务
  - DOMAIN-SUFFIX,crashlytics.com,🍎 苹果服务
  - DOMAIN-SUFFIX,icloud-content.com,🍎 苹果服务
  - DOMAIN-SUFFIX,icloud.com,🍎 苹果服务
  - DOMAIN-SUFFIX,icloud.com.cn,🍎 苹果服务
  - DOMAIN-SUFFIX,itunes.com,🍎 苹果服务
  - DOMAIN-SUFFIX,me.com,🍎 苹果服务
  - DOMAIN-SUFFIX,mzstatic.com,🍎 苹果服务
  - IP-CIDR,17.0.0.0/8,🍎 苹果服务,no-resolve
  - IP-CIDR,63.92.224.0/19,🍎 苹果服务,no-resolve
  - IP-CIDR,65.199.22.0/23,🍎 苹果服务,no-resolve
  - IP-CIDR,139.178.128.0/18,🍎 苹果服务,no-resolve
  - IP-CIDR,144.178.0.0/19,🍎 苹果服务,no-resolve
  - IP-CIDR,144.178.36.0/22,🍎 苹果服务,no-resolve
  - IP-CIDR,144.178.48.0/20,🍎 苹果服务,no-resolve
  - IP-CIDR,192.35.50.0/24,🍎 苹果服务,no-resolve
  - IP-CIDR,198.183.17.0/24,🍎 苹果服务,no-resolve
  - IP-CIDR,205.180.175.0/24,🍎 苹果服务,no-resolve
  - DOMAIN-SUFFIX,t.me,📲 电报信息
  - DOMAIN-SUFFIX,tdesktop.com,📲 电报信息
  - DOMAIN-SUFFIX,telegra.ph,📲 电报信息
  - DOMAIN-SUFFIX,telegram.me,📲 电报信息
  - DOMAIN-SUFFIX,telegram.org,📲 电报信息
  - DOMAIN-SUFFIX,telesco.pe,📲 电报信息
  - IP-CIDR,91.108.0.0/16,📲 电报信息,no-resolve
  - IP-CIDR,109.239.140.0/24,📲 电报信息,no-resolve
  - IP-CIDR,149.154.160.0/20,📲 电报信息,no-resolve
  - IP-CIDR6,2001:67c:4e8::/48,📲 电报信息,no-resolve
  - IP-CIDR6,2001:b28:f23d::/48,📲 电报信息,no-resolve
  - IP-CIDR6,2001:b28:f23f::/48,📲 电报信息,no-resolve
  - DOMAIN-SUFFIX,googlephotos.com,🌍 国外媒体
  - DOMAIN-SUFFIX,youtube.com,🌍 国外媒体
  - DOMAIN-SUFFIX,ytimg.com,🌍 国外媒体
  - DOMAIN-SUFFIX,1drv.com,Ⓜ️ 微软服务
  - DOMAIN-SUFFIX,1drv.ms,Ⓜ️ 微软服务
  - DOMAIN-SUFFIX,blob.core.windows.net,Ⓜ️ 微软服务
  - DOMAIN-SUFFIX,livefilestore.com,Ⓜ️ 微软服务
  - DOMAIN-SUFFIX,onedrive.com,Ⓜ️ 微软服务
  - DOMAIN-SUFFIX,storage.live.com,Ⓜ️ 微软服务
  - DOMAIN-SUFFIX,storage.msn.com,Ⓜ️ 微软服务
  - DOMAIN-KEYWORD,1drv,Ⓜ️ 微软服务
  - DOMAIN-KEYWORD,onedrive,Ⓜ️ 微软服务
  - DOMAIN-KEYWORD,skydrive,Ⓜ️ 微软服务
  - DOMAIN,c.amazon-adsystem.com,🛑 全球拦截
  - DOMAIN-SUFFIX,ad.gt,🛑 全球拦截
  - DOMAIN-SUFFIX,adsense.com,🛑 全球拦截
  - DOMAIN-SUFFIX,adinplay.com,🛑 全球拦截
  - DOMAIN-SUFFIX,adnxs.com,🛑 全球拦截
  - DOMAIN-SUFFIX,adsafeprotected.com,🛑 全球拦截
  - DOMAIN-SUFFIX,adservice.google.com,🛑 全球拦截
  - DOMAIN-SUFFIX,adthrive.com,🛑 全球拦截
  - DOMAIN-SUFFIX,adyoulike.com,🛑 全球拦截
  - DOMAIN-SUFFIX,anyclip.com,🛑 全球拦截
  - DOMAIN-SUFFIX,assets.adobedtm.com,🛑 全球拦截
  - DOMAIN-SUFFIX,chartbeat.com,🛑 全球拦截
  - DOMAIN-SUFFIX,doubleclick.net,🛑 全球拦截
  - DOMAIN-SUFFIX,googlesyndication.com,🛑 全球拦截
  - DOMAIN-SUFFIX,imasdk.googleapis.com,🛑 全球拦截
  - DOMAIN-SUFFIX,indexww.com,🛑 全球拦截
  - DOMAIN-SUFFIX,mfadsrvr.com,🛑 全球拦截
  - DOMAIN-SUFFIX,permutive.com,🛑 全球拦截
  - DOMAIN-SUFFIX,playwire.com,🛑 全球拦截
  - DOMAIN-SUFFIX,taboola.com,🛑 全球拦截
  - DOMAIN-SUFFIX,tv2.dk,🛑 全球拦截
  - DOMAIN-SUFFIX,adcolony.com,🍃 应用净化
  - DOMAIN-SUFFIX,adjust.com,🍃 应用净化
  - DOMAIN-SUFFIX,airpr.com,🍃 应用净化
  - DOMAIN-SUFFIX,hotjar.com,🍃 应用净化
  - DOMAIN-SUFFIX,hotjar.io,🍃 应用净化
  - DOMAIN-SUFFIX,hs-analytics.net,🍃 应用净化
  - DOMAIN-SUFFIX,hubspot.com,🍃 应用净化
  - DOMAIN-SUFFIX,intercom.io,🍃 应用净化
  - DOMAIN-SUFFIX,ushareit.com,🍃 应用净化
  - GEOIP,CN,🎯 全球直连
  - MATCH,🐟 漏网之鱼
EOF
        )
    fi

    # 合并配置文件头部和规则
    CLASH_CONFIG="${CLASH_CONFIG_HEADER}

${CLASH_RULES}"

    # 创建订阅目录
    mkdir -p /etc/hysteria/subscribe
    echo "$CLASH_CONFIG" > /etc/hysteria/subscribe/clash.yaml

    # 配置 Nginx
    if [ ! -z "$DOMAIN" ]; then
        cat > /etc/nginx/conf.d/hysteria-subscribe.conf << EOF
server {
    listen 80;
    server_name ${DOMAIN};
    
    # 将HTTP请求重定向到HTTPS
    location / {
        return 301 https://\$server_name\$request_uri;
    }
}

server {
    listen 443 ssl;
    server_name ${DOMAIN};
    
    ssl_certificate /etc/letsencrypt/live/${DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${DOMAIN}/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    
    location /${SUBSCRIBE_PATH}/clash {
        alias /etc/hysteria/subscribe/clash.yaml;
        default_type text/plain;
        add_header Content-Type 'text/plain; charset=utf-8';
    }
}
EOF
    else
        cat > /etc/nginx/conf.d/hysteria-subscribe.conf << EOF
server {
    listen 80;
    server_name ${SERVER_IP};
    charset utf-8;
    
    access_log /var/log/nginx/hysteria-subscribe-access.log;
    error_log /var/log/nginx/hysteria-subscribe-error.log;

    location /${SUBSCRIBE_PATH}/clash {
        # 移除基本身份验证，使用随机路径作为安全措施
        alias /etc/hysteria/subscribe/clash.yaml;
        default_type text/plain;
        add_header Content-Type 'text/plain; charset=utf-8';
    }
}
EOF
    fi

    # 移除默认的 Nginx 配置
    rm -f /etc/nginx/sites-enabled/default
    rm -f /etc/nginx/sites-available/default

    # 简化主配置文件
    cat > /etc/nginx/nginx.conf << EOF
user www-data;
worker_processes auto;
pid /run/nginx.pid;

events {
    worker_connections 768;
}

http {
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    types_hash_max_size 2048;

    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers on;

    access_log /var/log/nginx/access.log;
    error_log /var/log/nginx/error.log;

    gzip on;

    include /etc/nginx/conf.d/*.conf;
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
    echo "注意：Nginx 日志中的 'signal process started' 是正常的重启信息，不是错误"
    
    if curl -s -I -k -u "${SUBSCRIBE_USER}:${SUBSCRIBE_PASS}" "${PROTOCOL}://${SERVER_IP}/${SUBSCRIBE_PATH}/clash" | grep -q "200 OK"; then
        echo "订阅链接测试正常（HTTP 状态码：200）"
        if curl -s -k -u "${SUBSCRIBE_USER}:${SUBSCRIBE_PASS}" "${PROTOCOL}://${SERVER_IP}/${SUBSCRIBE_PATH}/clash" | grep -q "proxies:"; then
            echo "配置文件内容验证正常"
        fi
    else
        # 尝试使用内部 IP 测试
        if curl -s -I -k -u "${SUBSCRIBE_USER}:${SUBSCRIBE_PASS}" "${PROTOCOL}://localhost/${SUBSCRIBE_PATH}/clash" | grep -q "200 OK"; then
            echo "本地测试正常，但使用公网 IP 时可能有问题"
            echo "建议：确认防火墙已开放 80 端口" 
            if [ "$USE_HTTPS" = "true" ]; then
                echo "以及 443 端口，且没有其他网络限制"
            else 
                echo "且没有其他网络限制"
            fi
        else
            echo "警告：订阅链接可能无法正常访问，请检查 Nginx 配置"
            echo "Nginx 错误日志："
            tail -n 10 /var/log/nginx/error.log
        fi
    fi

    # 保存订阅信息
    cat > /etc/hysteria/subscribe/info.txt << EOF
=== 订阅链接 ===
Clash订阅：${PROTOCOL}://${SERVER_IP}/${SUBSCRIBE_PATH}/clash
小火箭订阅：sub://${BASE64_URL}#Hysteria2-${SERVER_IP}
EOF

    # 创建查询脚本
    cat > /usr/local/bin/hy2sub << 'EOF'
#!/bin/bash

if [ -f "/etc/hysteria/subscribe/info.txt" ]; then
    echo "=== Hysteria 2 订阅信息 ==="
    cat /etc/hysteria/subscribe/info.txt
    
    # 获取订阅链接
    SUBSCRIBE_LINK=$(grep "小火箭订阅：" /etc/hysteria/subscribe/info.txt | cut -d'：' -f2)
    
    if [ ! -z "$SUBSCRIBE_LINK" ]; then
        echo -e "\n=== 订阅二维码 ==="
        echo "小火箭扫码订阅："
        qrencode -t ANSIUTF8 -s 1 "$SUBSCRIBE_LINK"
    fi
else
    echo "未找到订阅信息，请确认是否已安装 Hysteria 2"
fi
EOF

    chmod +x /usr/local/bin/hy2sub

    # 创建连接查询脚本
    cat > /usr/local/bin/hy2stat << 'EOF'
#!/bin/bash

# 显示头部信息
echo "=== Hysteria 2 连接状态 ==="

# 检查 Hysteria 服务是否运行
if ! systemctl is-active hysteria-server >/dev/null 2>&1; then
    echo "Hysteria 服务未运行，无法查询连接数据"
    exit 1
fi

# 获取 Hysteria 使用的端口
PORT=$(grep "listen:" /etc/hysteria/config.yaml | awk -F':' '{print $3}')
if [ -z "$PORT" ]; then
    echo "无法从配置文件获取端口信息"
    exit 1
fi

echo "正在查询端口 $PORT 的连接情况..."

# 统计总连接数
TOTAL_CONN=$(netstat -anp | grep -c ":$PORT ")
# 统计不同的IP地址数量（即客户端数量）
UNIQUE_IPS=$(netstat -anp | grep ":$PORT " | awk '{print $5}' | cut -d: -f1 | sort | uniq | wc -l)
# 获取连接列表
CONN_LIST=$(netstat -anp | grep ":$PORT " | awk '{print $5}' | cut -d: -f1 | sort | uniq -c | sort -nr)

echo "当前活跃连接总数: $TOTAL_CONN"
echo "当前连接的客户端数: $UNIQUE_IPS"

# 显示详细的连接列表
if [ ! -z "$CONN_LIST" ]; then
    echo -e "\n=== 连接客户端列表 ==="
    echo "数量 IP地址"
    echo "$CONN_LIST"
fi

# 显示系统负载
echo -e "\n=== 系统负载 ==="
uptime

# 显示网络流量统计（如果安装了ifstat）
if command -v ifstat >/dev/null 2>&1; then
    echo -e "\n=== 实时网络流量 (KB/s) ==="
    ifstat -t 1 1
else
    echo -e "\n提示: 安装 ifstat 可以查看实时网络流量统计"
    echo "运行: apt-get install ifstat 或 yum install ifstat"
fi

# 显示详细的连接状态（如果安装了ss命令）
if command -v ss >/dev/null 2>&1; then
    echo -e "\n=== 详细连接状态 ==="
    ss -tnp state established "( sport = :$PORT or dport = :$PORT )" | head -n 20
    if [ $(ss -tnp state established "( sport = :$PORT or dport = :$PORT )" | wc -l) -gt 20 ]; then
        echo "... (仅显示前20条记录)"
    fi
fi

# 获取该端口的总流量（如果安装了iftop）
if command -v iftop >/dev/null 2>&1; then
    echo -e "\n=== 端口 $PORT 流量监控 ==="
    echo "请手动运行以下命令查看实时流量："
    echo "iftop -nNP -f 'port $PORT'"
fi

# 如果是高级模式，显示更多信息
if [ "$1" = "-a" ] || [ "$1" = "--advanced" ]; then
    echo -e "\n=== 连接耗时统计 ==="
    if command -v ss >/dev/null 2>&1; then
        echo "连接时长："
        ss -tnpo state established "( sport = :$PORT or dport = :$PORT )" | grep -oP 'timer:\(\w+,\K[^,]+' | sort -n | uniq -c
    fi
    
    echo -e "\n=== 系统资源使用情况 ==="
    if command -v top >/dev/null 2>&1; then
        top -bn1 | head -n 12
    fi
    
    echo -e "\n=== Hysteria 进程状态 ==="
    ps aux | grep -v grep | grep hysteria
fi

# 帮助信息
if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    echo -e "\n使用方法:"
    echo "  hy2stat             - 显示基本连接统计"
    echo "  hy2stat -a          - 显示高级连接统计（包括连接时长和系统资源）"
    echo "  hy2stat -m          - 持续监控连接状态（每5秒更新一次）"
    echo "  hy2stat -h          - 显示帮助信息"
    echo ""
fi

# 如果是监控模式，持续显示状态
if [ "$1" = "-m" ] || [ "$1" = "--monitor" ]; then
    echo -e "\n正在启动监控模式（每5秒更新一次）...\n"
    echo "按 Ctrl+C 退出监控"
    
    while true; do
        clear
        date
        echo "=== Hysteria 2 连接状态 (实时监控) ==="
        echo "当前活跃连接总数: $(netstat -anp | grep -c ":$PORT ")"
        echo "当前连接的客户端数: $(netstat -anp | grep ":$PORT " | awk '{print $5}' | cut -d: -f1 | sort | uniq | wc -l)"
        
        # 显示连接列表
        CONN_LIST=$(netstat -anp | grep ":$PORT " | awk '{print $5}' | cut -d: -f1 | sort | uniq -c | sort -nr)
        if [ ! -z "$CONN_LIST" ]; then
            echo -e "\n=== 连接客户端列表 ==="
            echo "数量 IP地址"
            echo "$CONN_LIST"
        fi
        
        # 显示网络流量
        if command -v ifstat >/dev/null 2>&1; then
            echo -e "\n=== 实时网络流量 (KB/s) ==="
            ifstat -t 1 1
        fi
        
        sleep 4
    done
fi
EOF

    chmod +x /usr/local/bin/hy2stat
    
    # 创建客户端 IP 查询脚本
    cat > /usr/local/bin/hy2client << 'EOF'
#!/bin/bash

# 显示头部信息
echo "=== Hysteria 2 客户端连接 ==="

# 检查 Hysteria 服务是否运行
if ! systemctl is-active hysteria-server >/dev/null 2>&1; then
    echo "Hysteria 服务未运行，无法查询连接数据"
    exit 1
fi

# 获取 Hysteria 使用的端口
PORT=$(grep "listen:" /etc/hysteria/config.yaml | awk -F':' '{print $3}')
if [ -z "$PORT" ]; then
    echo "无法从配置文件获取端口信息"
    exit 1
fi

echo "正在查询与端口 $PORT 建立连接的客户端..."

# 使用 netstat 查找所有连接到服务端口的客户端 IP
CLIENT_IPS=$(netstat -anp | grep "ESTABLISHED" | grep ":$PORT" | awk '{print $5}' | grep -v ":$PORT" | cut -d: -f1 | sort | uniq)

# 统计客户端数量和每个客户端的连接数
echo -e "\n=== 客户端连接情况 ==="
echo "端口 $PORT 的客户端连接总数: $(echo "$CLIENT_IPS" | wc -l)"
echo -e "\n客户端 IP 地址列表:"
for IP in $CLIENT_IPS; do
    CONN_COUNT=$(netstat -anp | grep "ESTABLISHED" | grep ":$PORT" | grep "$IP" | wc -l)
    echo "$IP - $CONN_COUNT 个连接"
done

# 使用 ss 命令获取更详细的信息（如果可用）
if command -v ss >/dev/null 2>&1; then
    echo -e "\n=== 详细客户端连接信息 ==="
    ss -tn state established "( dport = :$PORT )" | head -n 20
    if [ $(ss -tn state established "( dport = :$PORT )" | wc -l) -gt 20 ]; then
        echo "... (仅显示前20条记录)"
    fi
fi

# 按客户端 IP 显示连接时长（如果 ss 命令支持）
if command -v ss >/dev/null 2>&1 && ss --help 2>&1 | grep -q "\-o"; then
    echo -e "\n=== 客户端连接时长 ==="
    for IP in $CLIENT_IPS; do
        echo -e "\n客户端 IP: $IP"
        ss -tno state established "( dport = :$PORT )" | grep "$IP" | awk '{print $1, $2, $3, $4, $5}' | head -n 5
        if [ $(ss -tno state established "( dport = :$PORT )" | grep "$IP" | wc -l) -gt 5 ]; then
            echo "... (更多记录未显示)"
        fi
    done
fi

# 监控模式
if [ "$1" = "-m" ] || [ "$1" = "--monitor" ]; then
    echo -e "\n启动客户端监控模式。每10秒更新一次。按 Ctrl+C 退出。"
    
    while true; do
        clear
        date
        echo "=== Hysteria 2 客户端实时监控 ==="
        
        CLIENT_IPS=$(netstat -anp | grep "ESTABLISHED" | grep ":$PORT" | awk '{print $5}' | grep -v ":$PORT" | cut -d: -f1 | sort | uniq)
        
        echo "当前连接的客户端数: $(echo "$CLIENT_IPS" | wc -l)"
        echo -e "\n客户端 IP 地址列表:"
        for IP in $CLIENT_IPS; do
            CONN_COUNT=$(netstat -anp | grep "ESTABLISHED" | grep ":$PORT" | grep "$IP" | wc -l)
            echo "$IP - $CONN_COUNT 个连接"
        done
        
        sleep 10
    done
fi

# 帮助信息
if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    echo -e "\n使用方法:"
    echo "  hy2client         - 显示客户端连接信息"
    echo "  hy2client -m      - 持续监控客户端连接（每10秒更新一次）"
    echo "  hy2client -h      - 显示此帮助信息"
fi
EOF

    chmod +x /usr/local/bin/hy2client

    echo -e "\nHysteria 2 安装完成！"
    if [ ! -z "$DOMAIN" ]; then
        echo "域名：$DOMAIN"
        echo "证书位置：/etc/hysteria/cert.crt"
        echo "证书自动续期已配置"
    fi
    echo "配置文件位置：/etc/hysteria/config.yaml"
    echo -e "\n=== 连接信息 ==="
    echo "服务器IP：$SERVER_IP"
    echo "端口：${USER_PORT}"
    echo "密码：${USER_PASSWORD}"
    
    echo -e "\n=== 订阅信息 ==="
    echo "订阅用户名：$SUBSCRIBE_USER"
    echo "订阅密码：$SUBSCRIBE_PASS"
    
    echo -e "\n=== 订阅链接 ==="
    echo "Clash订阅：${BASE_SUBSCRIBE_URL}"
    echo "小火箭订阅：${SHADOWROCKET_URL}"
    
    echo -e "\n=== 订阅二维码 ==="
    echo "小火箭扫码订阅："
    qrencode -t ANSIUTF8 -s 1 "$SHADOWROCKET_URL"
    
    echo -e "\n提示："
    echo "1. 推荐使用 Shadowrocket 客户端，简单好用"
    echo "2. 如需分享，请使用 Clash 订阅链接，对方需手动输入用户名和密码"
    echo "3. 订阅信息已保存到：/etc/hysteria/subscribe/"
    echo "4. 使用 'hy2sub' 命令可随时查看订阅信息"
    echo "5. 使用 'hy2stat' 命令可随时查看连接状态"
    echo "6. 使用 'hy2client' 命令可查看客户端连接情况"
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

# 查询当前连接数函数
query_connections() {
    echo "=== Hysteria 2 连接状态 ==="
    
    # 检查 Hysteria 服务是否运行
    if ! systemctl is-active hysteria-server >/dev/null 2>&1; then
        echo "Hysteria 服务未运行，无法查询连接数据"
        return 1
    fi
    
    # 获取 Hysteria 使用的端口
    PORT=$(grep "listen:" /etc/hysteria/config.yaml | awk -F':' '{print $3}')
    if [ -z "$PORT" ]; then
        echo "无法从配置文件获取端口信息"
        return 1
    fi
    
    echo "正在查询端口 $PORT 的连接情况..."
    
    # 统计总连接数
    TOTAL_CONN=$(netstat -anp | grep -c ":$PORT ")
    # 统计不同的IP地址数量（即客户端数量）
    UNIQUE_IPS=$(netstat -anp | grep ":$PORT " | awk '{print $5}' | cut -d: -f1 | sort | uniq | wc -l)
    # 获取连接列表
    CONN_LIST=$(netstat -anp | grep ":$PORT " | awk '{print $5}' | cut -d: -f1 | sort | uniq -c | sort -nr)
    
    echo "当前活跃连接总数: $TOTAL_CONN"
    echo "当前连接的客户端数: $UNIQUE_IPS"
    
    # 显示最近的连接日志
    echo -e "\n=== 最近连接日志 ==="
    if [ -f "/var/log/syslog" ]; then
        grep "hysteria" /var/log/syslog | grep "connection" | tail -n 10
    elif [ -f "/var/log/messages" ]; then
        grep "hysteria" /var/log/messages | grep "connection" | tail -n 10
    else
        journalctl -u hysteria-server | grep "connection" | tail -n 10
    fi
    
    # 显示详细的连接列表
    if [ ! -z "$CONN_LIST" ]; then
        echo -e "\n=== 连接客户端列表 ==="
        echo "数量 IP地址"
        echo "$CONN_LIST"
    fi
    
    # 显示系统负载
    echo -e "\n=== 系统负载 ==="
    uptime
    
    # 显示网络流量统计（如果安装了ifstat）
    if command -v ifstat >/dev/null 2>&1; then
        echo -e "\n=== 实时网络流量 (KB/s) ==="
        ifstat -t 1 1
    else
        echo -e "\n提示: 安装 ifstat 可以查看实时网络流量统计"
        echo "运行: apt-get install ifstat 或 yum install ifstat"
    fi
}

# 主菜单循环
while true; do
    show_menu
    read -p "请输入选项 [0-5]: " choice
    
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
        4)
            query_connections
            ;;
        5)
            update_cert
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
