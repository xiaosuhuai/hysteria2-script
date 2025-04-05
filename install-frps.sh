#!/bin/bash

# 颜色定义
GREEN="\033[0;32m"
YELLOW="\033[0;33m"
PLAIN="\033[0m"

# 检查是否为root用户
check_root() {
    if [ "$(id -u)" != "0" ]; then
        echo -e "请使用root用户运行此脚本"
        exit 1
    fi
}

# 检查系统类型
check_sys() {
    if [[ -f /etc/redhat-release ]]; then
        release="centos"
    elif cat /etc/issue | grep -q -E -i "debian"; then
        release="debian"
    elif cat /etc/issue | grep -q -E -i "ubuntu"; then
        release="ubuntu"
    elif cat /etc/issue | grep -q -E -i "centos|red hat|redhat"; then
        release="centos"
    elif cat /proc/version | grep -q -E -i "debian"; then
        release="debian"
    elif cat /proc/version | grep -q -E -i "ubuntu"; then
        release="ubuntu"
    elif cat /proc/version | grep -q -E -i "centos|red hat|redhat"; then
        release="centos"
    else
        echo -e "未检测到系统版本，请联系脚本作者"
        exit 1
    fi
}

# 安装必要的软件包
install_pkg() {
    if [[ ${release} == "centos" ]]; then
        yum install -y wget curl tar nginx
    else
        apt-get update
        apt-get install -y wget curl tar nginx
    fi
}

# 获取最新版本的frp
get_latest_version() {
    local latest_release_tag=$(curl -s https://api.github.com/repos/fatedier/frp/releases/latest | grep "tag_name" | cut -d'"' -f4)
    if [[ -z "$latest_release_tag" ]]; then
        echo -e "获取frp最新版本失败，请检查网络连接"
        exit 1
    fi
    echo "$latest_release_tag"
}

# 下载并安装frps
download_and_install() {
    local version=$1
    local arch="amd64"
    if [[ "$(uname -m)" == "aarch64" ]]; then
        arch="arm64"
    fi
    
    local filename="frp_${version:1}_linux_${arch}"
    local url="https://github.com/fatedier/frp/releases/download/${version}/${filename}.tar.gz"
    
    echo -e "${GREEN}开始下载 frp ${version}...${PLAIN}"
    wget -O frp.tar.gz ${url}
    if [[ $? -ne 0 ]]; then
        echo -e "下载失败，请检查网络连接"
        exit 1
    fi
    
    tar -xf frp.tar.gz
    cd ${filename}
    
    # 复制二进制文件
    cp frps /usr/bin/
    chmod +x /usr/bin/frps
    
    # 创建配置目录
    mkdir -p /etc/frp
    
    # 移动配置文件
    cp frps.ini /etc/frp/
    
    # 清理临时文件
    cd ..
    rm -rf ${filename}
    rm -f frp.tar.gz
}

# 配置frps
configure_frps() {
    echo -e "${YELLOW}配置frps参数：${PLAIN}"
    
    read -p "请输入frps绑定端口 [7000]: " bind_port
    bind_port=${bind_port:-7000}
    
    read -p "请输入HTTP穿透端口 [8080]: " vhost_http_port
    vhost_http_port=${vhost_http_port:-8080}
    
    read -p "请输入HTTPS穿透端口 [4430]: " vhost_https_port
    vhost_https_port=${vhost_https_port:-4430}
    
    read -p "请输入面板端口 [7500]: " dashboard_port
    dashboard_port=${dashboard_port:-7500}
    
    read -p "请输入面板用户名 [admin]: " dashboard_user
    dashboard_user=${dashboard_user:-admin}
    
    read -p "请输入面板密码 [admin]: " dashboard_pwd
    dashboard_pwd=${dashboard_pwd:-admin}
    
    read -p "请输入Token [随机生成]: " token
    if [[ -z "$token" ]]; then
        token=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)
    fi
    
    # 生成配置文件
    cat > /etc/frp/frps.ini << EOF
[common]
bind_port = ${bind_port}
vhost_http_port = ${vhost_http_port}
vhost_https_port = ${vhost_https_port}
dashboard_port = ${dashboard_port}
dashboard_user = ${dashboard_user}
dashboard_pwd = ${dashboard_pwd}
token = ${token}

# 日志配置
log_file = /var/log/frps.log
log_level = info
log_max_days = 3

# 连接池
max_pool_count = 50

# 允许的端口范围
allow_ports = 1-65535

# 心跳超时
heartbeat_timeout = 90
EOF
}

# 配置Nginx
configure_nginx() {
    # 创建Nginx配置
    cat > /etc/nginx/conf.d/frps.conf << EOF
server {
    listen 80;
    server_name _;

    location / {
        proxy_pass http://127.0.0.1:${dashboard_port};
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

    # 移除默认配置
    rm -f /etc/nginx/sites-enabled/default

    # 测试配置
    nginx -t

    # 重启Nginx
    systemctl restart nginx
}

# 创建systemd服务
create_service() {
    cat > /etc/systemd/system/frps.service << EOF
[Unit]
Description=Frp Server Service
After=network.target

[Service]
Type=simple
User=root
Restart=on-failure
RestartSec=5s
ExecStart=/usr/bin/frps -c /etc/frp/frps.ini
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable frps
    systemctl start frps
}

# 配置防火墙
configure_firewall() {
    echo -e "${GREEN}配置防火墙规则...${PLAIN}"
    
    if command -v ufw >/dev/null 2>&1; then
        ufw allow ${bind_port}/tcp
        ufw allow ${vhost_http_port}/tcp
        ufw allow ${vhost_https_port}/tcp
        ufw allow ${dashboard_port}/tcp
        ufw allow 80/tcp
        ufw allow 443/tcp
    elif command -v firewall-cmd >/dev/null 2>&1; then
        firewall-cmd --permanent --add-port=${bind_port}/tcp
        firewall-cmd --permanent --add-port=${vhost_http_port}/tcp
        firewall-cmd --permanent --add-port=${vhost_https_port}/tcp
        firewall-cmd --permanent --add-port=${dashboard_port}/tcp
        firewall-cmd --permanent --add-port=80/tcp
        firewall-cmd --permanent --add-port=443/tcp
        firewall-cmd --reload
    fi
}

# 配置系统优化
optimize_system() {
    # 设置系统最大打开文件数
    cat > /etc/security/limits.d/frps.conf << EOF
* soft nofile 1048576
* hard nofile 1048576
EOF

    # 优化内核参数
    cat > /etc/sysctl.d/local.conf << EOF
# 最大连接数
net.core.somaxconn = 2048

# TCP连接参数
net.ipv4.tcp_max_syn_backlog = 8192
net.ipv4.tcp_fin_timeout = 30
net.ipv4.tcp_keepalive_time = 300
net.ipv4.tcp_keepalive_probes = 3
net.ipv4.tcp_keepalive_intvl = 30

# 开启端口重用
net.ipv4.tcp_tw_reuse = 1
EOF

    sysctl --system
}

# 显示配置信息
show_config() {
    echo -e "\n${GREEN}frps 安装完成！${PLAIN}"
    echo -e "\n${YELLOW}配置信息：${PLAIN}"
    echo -e "服务器IP：$(curl -s ip.sb)"
    echo -e "frps端口：${bind_port}"
    echo -e "HTTP端口：${vhost_http_port}"
    echo -e "HTTPS端口：${vhost_https_port}"
    echo -e "面板地址：http://$(curl -s ip.sb):${dashboard_port}"
    echo -e "面板用户：${dashboard_user}"
    echo -e "面板密码：${dashboard_pwd}"
    echo -e "Token：${token}"
    echo -e "\n${YELLOW}frpc客户端配置示例：${PLAIN}"
    echo -e "[common]
server_addr = $(curl -s ip.sb)
server_port = ${bind_port}
token = ${token}

[web]
type = http
local_ip = 127.0.0.1
local_port = 80
custom_domains = your_domain.com"

    echo -e "\n${YELLOW}服务管理命令：${PLAIN}"
    echo -e "启动：systemctl start frps"
    echo -e "停止：systemctl stop frps"
    echo -e "重启：systemctl restart frps"
    echo -e "状态：systemctl status frps"
    echo -e "查看日志：journalctl -u frps"
}

# 主函数
main() {
    check_root
    check_sys
    install_pkg
    
    local version=$(get_latest_version)
    download_and_install ${version}
    configure_frps
    configure_nginx
    create_service
    configure_firewall
    optimize_system
    show_config
    
    echo -e "\n${GREEN}安装完成，服务已启动${PLAIN}"
    echo -e "如果需要配置HTTPS访问，请使用以下命令安装SSL证书："
    echo -e "apt install certbot python3-certbot-nginx"
    echo -e "certbot --nginx -d your.domain.com"
}

main 