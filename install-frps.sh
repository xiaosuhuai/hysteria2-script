#!/bin/bash

# 颜色定义
red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

# 检查是否为root用户
[[ $EUID -ne 0 ]] && echo -e "${red}错误：${plain} 必须使用root用户运行此脚本！\n" && exit 1

# 显示菜单
show_menu() {
    echo -e "
  ${green}FRP 管理脚本${plain}
  ${green}0.${plain} 退出脚本
  ${green}1.${plain} 安装 FRP
  ${green}2.${plain} 更新 FRP
  ${green}3.${plain} 卸载 FRP
  ${green}4.${plain} 查看 FRP 状态
  ${green}5.${plain} 查看 FRP 日志
  ${green}6.${plain} 重启 FRP
  ${green}7.${plain} 修改 FRP 配置
  ${green}8.${plain} 检查客户端连接
  ————————————————"
    echo && read -p "请输入选择 [0-8]: " num

    case "${num}" in
        0) exit 0
        ;;
        1) install_frp
        ;;
        2) update_frp
        ;;
        3) uninstall_frp
        ;;
        4) check_status
        ;;
        5) view_log
        ;;
        6) restart_frp
        ;;
        7) modify_config
        ;;
        8) check_client_status
        ;;
        *) echo -e "${red}请输入正确的数字 [0-8]${plain}"
        ;;
    esac
}

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

# 检查状态
check_status() {
    echo -e "检查 FRP 状态..."
    systemctl status frps
    echo
    echo -e "当前监听端口："
    netstat -tnlp | grep frps
    echo
    echo -e "当前连接状态："
    netstat -tnp | grep frps | grep ESTABLISHED
}

# 查看日志
view_log() {
    echo -e "FRP 日志最后 50 行："
    tail -n 50 /var/log/frps.log
}

# 重启服务
restart_frp() {
    echo -e "正在重启 FRP 服务..."
    systemctl restart frps
    if systemctl is-active --quiet frps; then
        echo -e "${green}FRP 重启成功！${plain}"
    else
        echo -e "${red}FRP 重启失败，请检查日志${plain}"
    fi
}

# 修改配置
modify_config() {
    echo -e "当前配置："
    cat /etc/frp/frps.ini
    echo -e "\n是否要修改配置？[y/n]"
    read -p "> " choice
    if [[ $choice == "y" || $choice == "Y" ]]; then
        nano /etc/frp/frps.ini
        echo -e "配置已修改，是否要重启服务？[y/n]"
        read -p "> " restart
        if [[ $restart == "y" || $restart == "Y" ]]; then
            restart_frp
        fi
    fi
}

# 更新 FRP
update_frp() {
    echo -e "正在检查最新版本..."
    local latest_ver=$(get_latest_version)
    local current_ver=$(frps -v 2>/dev/null | awk '{print $3}')
    
    if [ -z "$current_ver" ]; then
        echo -e "${yellow}未检测到已安装的版本，将进行全新安装${plain}"
        install_frp
        return
    fi
    
    echo -e "当前版本：${current_ver}"
    echo -e "最新版本：${latest_ver}"
    
    if [ "$latest_ver" = "$current_ver" ]; then
        echo -e "${green}已经是最新版本${plain}"
        return
    fi
    
    echo -e "开始更新..."
    install_frp
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

# 检查端口
check_ports() {
    echo -n "检查端口 5443... "
    if lsof -i:5443 >/dev/null 2>&1; then
        echo -e "${red}端口被占用${plain}"
        return 1
    fi
    echo -e "${green}可用${plain}"

    echo -n "检查端口 6443... "
    if lsof -i:6443 >/dev/null 2>&1; then
        echo -e "${red}端口被占用${plain}"
        return 1
    fi
    echo -e "${green}可用${plain}"
    return 0
}

# 验证服务
verify_service() {
    echo -n "验证服务状态... "
    if ! systemctl is-active --quiet frps; then
        echo -e "${red}服务未正常运行${plain}"
        echo "查看详细错误信息："
        systemctl status frps
        return 1
    fi
    echo -e "${green}运行正常${plain}"
    return 0
}

# 安装frp
install_frp() {
    version=$(get_latest_version)
    echo -e "${green}开始安装 FRP ${version}...${plain}"
    
    # 获取公网IP
    PUBLIC_IP=$(curl -s ip.sb || curl -s ifconfig.me || curl -s api.ipify.org)
    if [ -z "${PUBLIC_IP}" ]; then
        echo -e "${red}无法获取公网IP地址${plain}"
        exit 1
    fi

    # 选择安装模式
    echo -e "\n请选择安装模式："
    echo -e "${green}1.${plain} HTTP 模式（使用域名访问）"
    echo -e "${green}2.${plain} TCP 模式（使用IP直接访问）"
    read -p "请输入 [1-2]: " install_mode

    # 生成随机密码
    DASHBOARD_PWD=$(generate_password)
    TOKEN=$(generate_password)

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

    cp frps /usr/bin/
    mkdir -p /etc/frp

    if [ "$install_mode" = "1" ]; then
        # HTTP模式配置
        cat > /etc/frp/frps.ini << EOF
[common]
bind_port = 7000
vhost_http_port = 8080
dashboard_port = 7500
dashboard_user = admin
dashboard_pwd = ${DASHBOARD_PWD}
token = ${TOKEN}
log_file = /var/log/frps.log
log_level = info
log_max_days = 3
tcp_mux = true
subdomain_host = suhuai.top
EOF

        # HTTP模式客户端配置示例
        cat > /etc/frp/config_info.txt << EOF
==================== 配置信息 ====================
服务器地址：${PUBLIC_IP}
主要端口：7000
HTTP端口：8080
Dashboard：http://${PUBLIC_IP}:7500
Dashboard用户名：admin
Dashboard密码：${DASHBOARD_PWD}
Token：${TOKEN}
================================================

客户端配置示例（HTTP模式）：
serverAddr = "${PUBLIC_IP}"
serverPort = 7000
auth.method = "token"
auth.token = "${TOKEN}"
loginFailExit = false

[[proxies]]
name = "nas-ui"
type = "http"
localIP = "192.168.3.9"
localPort = 5666
subdomain = "nas"

重要提示：
1. 使用域名访问：http://nas.suhuai.top:8080
2. 所有配置信息已保存到：/etc/frp/config_info.txt
3. 请确保已将域名 nas.suhuai.top 解析到服务器IP：${PUBLIC_IP}
EOF
    else
        # TCP模式配置
        cat > /etc/frp/frps.ini << EOF
[common]
bind_port = 7000
dashboard_port = 7500
dashboard_user = admin
dashboard_pwd = ${DASHBOARD_PWD}
token = ${TOKEN}
log_file = /var/log/frps.log
log_level = info
log_max_days = 3
tcp_mux = true
EOF

        # 保存TCP模式配置信息
        cat > /etc/frp/config_info.txt << EOF
==================== 配置信息 ====================
服务器地址：${PUBLIC_IP}
主要端口：7000
Dashboard：http://${PUBLIC_IP}:7500
Dashboard用户名：admin
Dashboard密码：${DASHBOARD_PWD}
Token：${TOKEN}
================================================

客户端配置示例（TCP模式）：
serverAddr = "${PUBLIC_IP}"
serverPort = 7000
auth.method = "token"
auth.token = "${TOKEN}"
loginFailExit = false

[[proxies]]
name = "nas-ui"
type = "tcp"
localIP = "192.168.3.9"
localPort = 5666
remotePort = 25666

重要提示：
1. 使用IP直接访问：http://${PUBLIC_IP}:25666
2. 所有配置信息已保存到：/etc/frp/config_info.txt
3. 使用TCP模式访问更简单，无需额外配置
EOF
    fi

    # 创建服务
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

    echo -e "${green}FRP 安装完成！${plain}"
    cat /etc/frp/config_info.txt

    echo -e "\n${yellow}重要提示：${plain}"
    if [ "$install_mode" = "1" ]; then
        echo -e "1. 使用域名访问：${green}http://nas.suhuai.top:8080${plain}"
        echo -e "2. 所有配置信息已保存到：${green}/etc/frp/config_info.txt${plain}"
        echo -e "3. 请确保已将域名 ${green}nas.suhuai.top${plain} 解析到服务器IP：${green}${PUBLIC_IP}${plain}"
    else
        echo -e "1. 使用IP直接访问：${green}http://${PUBLIC_IP}:25666${plain}"
        echo -e "2. 所有配置信息已保存到：${green}/etc/frp/config_info.txt${plain}"
        echo -e "3. 使用TCP模式访问更简单，无需额外配置"
    fi
}

# 检查客户端连接状态
check_client_status() {
    echo -e "\n${yellow}检查客户端连接状态：${plain}"
    if curl -s "http://127.0.0.1:6443/api/proxy/tcp" -u "admin:${DASHBOARD_PWD}" | grep -q "name.*nas-ui"; then
        echo -e "${green}NAS UI 已连接${plain}"
    else
        echo -e "${yellow}NAS UI 未连接${plain}"
        echo "请检查客户端配置是否正确"
    fi
}

# 显示菜单
show_menu 