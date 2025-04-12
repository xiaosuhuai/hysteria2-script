#!/bin/bash

# 颜色定义
red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

# 检查是否为root用户
[[ $EUID -ne 0 ]] && echo -e "${red}错误：${plain} 必须使用root用户运行此脚本！\n" && exit 1

# 生成随机密码
generate_password() {
    openssl rand -base64 12 | tr -dc 'a-zA-Z0-9' | head -c 12
}

# 获取系统架构
arch=$(arch)

# 获取最新版本的frp
get_latest_version() {
    latest_version=$(curl -s https://api.github.com/repos/fatedier/frp/releases/latest | grep -o '"tag_name": ".*"' | sed 's/"tag_name": "//g' | sed 's/"//g')
    if [ -z "$latest_version" ]; then
        echo -e "${red}获取版本信息失败，请检查网络连接${plain}"
        exit 1
    fi
    echo "$latest_version"
}

# 卸载frp
uninstall_frp() {
    echo -e "${yellow}正在卸载 FRP...${plain}"
    systemctl stop frps
    systemctl disable frps
    rm -f /etc/systemd/system/frps.service
    rm -f /usr/bin/frps
    rm -rf /etc/frp
    systemctl daemon-reload
    echo -e "${green}FRP 已成功卸载！${plain}"
    exit 0
}

# 安装frp
install_frp() {
    version=$(get_latest_version)
    echo -e "${green}开始安装 FRP ${version}...${plain}"
    
    # 生成随机密码
    DASHBOARD_PWD=$(generate_password)
    FRP_TOKEN=$(generate_password)
    
    case "$arch" in
        x86_64|amd64)
            arch="amd64"
            ;;
        aarch64|arm64)
            arch="arm64"
            ;;
        *)
            echo -e "${red}不支持的架构: ${arch}${plain}" && exit 1
            ;;
    esac
    
    if ! wget -N --no-check-certificate https://github.com/fatedier/frp/releases/download/${version}/frp_${version:1}_linux_${arch}.tar.gz; then
        echo -e "${red}下载 FRP 失败，请检查网络连接${plain}"
        exit 1
    fi
    
    tar zxvf frp_${version:1}_linux_${arch}.tar.gz
    cd frp_${version:1}_linux_${arch} || exit
    
    # 复制二进制文件
    cp frps /usr/bin/
    mkdir -p /etc/frp
    
    # 创建frps配置文件
    cat > /etc/frp/frps.ini << EOL
[common]
bind_port = 5443
vhost_http_port = 8080
dashboard_port = 6443
dashboard_user = admin
dashboard_pwd = ${DASHBOARD_PWD}
token = ${FRP_TOKEN}
subdomain_host = suhuai.top
log_file = /var/log/frps.log
log_level = info
log_max_days = 3
tcp_mux = true
EOL
    
    # 创建systemd服务
    cat > /etc/systemd/system/frps.service << EOL
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
EOL
    
    # 设置权限
    chmod +x /usr/bin/frps
    
    # 启动服务
    systemctl daemon-reload
    systemctl enable frps
    systemctl start frps
    
    # 检查服务状态
    if ! systemctl is-active --quiet frps; then
        echo -e "${red}FRP 服务启动失败，请检查日志${plain}"
        exit 1
    fi
    
    # 清理安装文件
    cd ..
    rm -rf frp_${version:1}_linux_${arch}.tar.gz frp_${version:1}_linux_${arch}
    
    # 获取公网IP
    PUBLIC_IP=$(curl -s ip.sb)
    
    echo -e "${green}FRP 安装完成！${plain}"
    echo -e "==================== 配置信息 ===================="
    echo -e "服务器地址：${green}${PUBLIC_IP}${plain}"
    echo -e "主要端口：${green}5443${plain}"
    echo -e "HTTP端口：${green}8080${plain}"
    echo -e "Dashboard：${green}http://${PUBLIC_IP}:6443${plain}"
    echo -e "Dashboard用户名：${green}admin${plain}"
    echo -e "Dashboard密码：${green}${DASHBOARD_PWD}${plain}"
    echo -e "Token：${green}${FRP_TOKEN}${plain}"
    echo -e "================================================"
    echo -e "\n客户端配置示例 (frpc.toml):"
    echo -e "${green}serverAddr = \"${PUBLIC_IP}\"
serverPort = 5443
auth.method = \"token\"
auth.token = \"${FRP_TOKEN}\"
loginFailExit = false

[[proxies]]
name = \"nas-ui\"
type = \"http\"
localIP = \"192.168.3.9\"
localPort = 5666
customDomains = [\"nas.suhuai.top\"]${plain}"
    echo -e "\n访问地址：${green}http://nas.suhuai.top:8080${plain}"
    echo -e "\n使用以下命令管理 FRP 服务："
    echo -e "启动：${green}systemctl start frps${plain}"
    echo -e "停止：${green}systemctl stop frps${plain}"
    echo -e "重启：${green}systemctl restart frps${plain}"
    echo -e "状态：${green}systemctl status frps${plain}"
    echo -e "配置文件：${green}/etc/frp/frps.ini${plain}"
    echo -e "卸载：${yellow}bash $0 uninstall${plain}"
    
    # 保存配置信息到文件
    echo -e "\n配置信息已保存到：${green}/etc/frp/config_info.txt${plain}"
    cat > /etc/frp/config_info.txt << EOL
FRP 配置信息
==========================================
服务器地址：${PUBLIC_IP}
主要端口：5443
HTTP端口：8080
Dashboard：http://${PUBLIC_IP}:6443
Dashboard用户名：admin
Dashboard密码：${DASHBOARD_PWD}
Token：${FRP_TOKEN}
==========================================

客户端配置 (frpc.toml):
serverAddr = "${PUBLIC_IP}"
serverPort = 5443
auth.method = "token"
auth.token = "${FRP_TOKEN}"
loginFailExit = false

[[proxies]]
name = "nas-ui"
type = "http"
localIP = "192.168.3.9"
localPort = 5666
customDomains = ["nas.suhuai.top"]

访问地址：http://nas.suhuai.top:8080
EOL
}

# 根据参数执行操作
case "$1" in
    uninstall)
        uninstall_frp
        ;;
    *)
        install_frp
        ;;
esac 