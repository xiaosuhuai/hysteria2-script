#!/bin/bash

# 颜色定义
RED="\033[0;31m"
GREEN="\033[0;32m"
YELLOW="\033[0;33m"
PLAIN="\033[0m"

# 检查是否为root用户
check_root() {
    if [ "$(id -u)" != "0" ]; then
        echo -e "${RED}错误: 必须使用root用户运行此脚本！${PLAIN}"
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
        echo -e "${RED}未检测到系统版本，请联系脚本作者！${PLAIN}" && exit 1
    fi
}

# 安装必要的软件包
install_pkg() {
    if [[ ${release} == "centos" ]]; then
        yum install -y wget curl tar
    else
        apt-get update
        apt-get install -y wget curl tar
    fi
}

# 获取最新版本的frp
get_latest_version() {
    local latest_release_tag=$(curl -s https://api.github.com/repos/fatedier/frp/releases/latest | grep "tag_name" | cut -d'"' -f4)
    if [[ -z "$latest_release_tag" ]]; then
        echo -e "${RED}获取frp最新版本失败，请检查网络连接！${PLAIN}"
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
        echo -e "${RED}下载失败，请检查网络连接！${PLAIN}"
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
    # 获取用户输入
    echo -e "${YELLOW}请配置frps参数：${PLAIN}"
    
    read -p "请输入frps绑定端口 [7000]: " bind_port
    bind_port=${bind_port:-7000}
    
    read -p "请输入HTTP穿透端口 [8080]: " vhost_http_port
    vhost_http_port=${vhost_http_port:-8080}
    
    read -p "请输入HTTPS穿透端口 [4430]: " vhost_https_port
    vhost_https_port=${vhost_https_port:-4430}
    
    read -p "请输入Dashboard端口 [7500]: " dashboard_port
    dashboard_port=${dashboard_port:-7500}
    
    read -p "请输入Dashboard用户名 [admin]: " dashboard_user
    dashboard_user=${dashboard_user:-admin}
    
    read -p "请输入Dashboard密码 [admin]: " dashboard_pwd
    dashboard_pwd=${dashboard_pwd:-admin}
    
    read -p "请输入frps Token [随机生成]: " token
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
    elif command -v firewall-cmd >/dev/null 2>&1; then
        firewall-cmd --permanent --add-port=${bind_port}/tcp
        firewall-cmd --permanent --add-port=${vhost_http_port}/tcp
        firewall-cmd --permanent --add-port=${vhost_https_port}/tcp
        firewall-cmd --permanent --add-port=${dashboard_port}/tcp
        firewall-cmd --reload
    fi
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
}

# 主函数
main() {
    check_root
    check_sys
    install_pkg
    
    local version=$(get_latest_version)
    download_and_install ${version}
    configure_frps
    create_service
    configure_firewall
    show_config
}

main 