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
————————————————
"
    echo && read -p "请输入选择 [0-7]: " num
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
        *) echo -e "${red}请输入正确的数字 [0-7]${plain}"
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
    systemctl status frps | cat
    echo -e "\n当前监听端口："
    netstat -tnlp | grep frps
    echo -e "\n当前连接状态："
    netstat -anp | grep frps | grep ESTABLISHED
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
vhost_http_port = 80
dashboard_port = 6443
dashboard_user = admin
dashboard_pwd = ${DASHBOARD_PWD}
token = ${FRP_TOKEN}
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
DefaultDependencies=no
EOL

    # 创建 SysV init 脚本
    cat > /etc/init.d/frps << EOL
#!/bin/sh
### BEGIN INIT INFO
# Provides:          frps
# Required-Start:    \$network \$remote_fs \$syslog
# Required-Stop:     \$network \$remote_fs \$syslog
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: FRP Server Service
# Description:       Start or stop the FRP Server.
### END INIT INFO

NAME=frps
DAEMON=/usr/bin/\$NAME
PIDFILE=/var/run/\$NAME.pid
CONFIG=/etc/frp/frps.ini

[ -x "\$DAEMON" ] || exit 0

case "\$1" in
    start)
        \$DAEMON -c \$CONFIG
        ;;
    stop)
        killall \$NAME
        ;;
    restart)
        \$0 stop
        \$0 start
        ;;
    status)
        if pgrep \$NAME >/dev/null; then
            echo "\$NAME is running"
        else
            echo "\$NAME is not running"
        fi
        ;;
    *)
        echo "Usage: \$0 {start|stop|restart|status}"
        exit 1
        ;;
esac

exit 0
EOL

    # 设置权限
    chmod +x /usr/bin/frps
    chmod +x /etc/init.d/frps
    
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
    echo -e "HTTP端口：${green}80${plain}"
    echo -e "Dashboard：${green}http://${PUBLIC_IP}:6443${plain}"
    echo -e "Dashboard用户名：${green}admin${plain}"
    echo -e "Dashboard密码：${green}${DASHBOARD_PWD}${plain}"
    echo -e "Token：${green}${FRP_TOKEN}${plain}"
    echo -e "================================================"
    echo -e "\n配置示例 (使用域名):"
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
subdomain = \"nas\"${plain}"

    echo -e "\n配置示例 (直接使用IP):"
    echo -e "${green}serverAddr = \"${PUBLIC_IP}\"
serverPort = 5443
auth.method = \"token\"
auth.token = \"${FRP_TOKEN}\"
loginFailExit = false

[[proxies]]
name = \"nas-ui\"
type = \"tcp\"
localIP = \"192.168.3.9\"
localPort = 5666
remotePort = 25666${plain}"

    # 保存配置信息到文件
    cat > /etc/frp/config_info.txt << EOL
FRP 配置信息
==========================================
服务器地址：${PUBLIC_IP}
主要端口：5443
HTTP端口：80
Dashboard：http://${PUBLIC_IP}:6443
Dashboard用户名：admin
Dashboard密码：${DASHBOARD_PWD}
Token：${FRP_TOKEN}
==========================================

方案一：使用域名访问
--------------------
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
subdomain = "nas"

访问地址：http://nas.suhuai.top

方案二：直接使用IP访问（推荐）
----------------------------
客户端配置 (frpc.toml):
serverAddr = "${PUBLIC_IP}"
serverPort = 5443
auth.method = "token"
auth.token = "${FRP_TOKEN}"
loginFailExit = false

[[proxies]]
name = "nas-ui"
type = "tcp"
localIP = "192.168.3.9"
localPort = 5666
remotePort = 25666

访问地址：http://${PUBLIC_IP}:25666

注意事项：
1. 使用IP方案优点：
   - 无需配置域名
   - 直接访问，速度更快
   - 配置更简单
   - 无需额外DNS设置

2. 确保本地服务在 localIP:localPort 正常运行
3. 确保服务器防火墙已开放相应端口
EOL

    echo -e "\n${yellow}重要提示：${plain}"
    echo -e "1. 使用IP直接访问：${green}http://${PUBLIC_IP}:25666${plain}"
    echo -e "2. 所有配置信息已保存到：${green}/etc/frp/config_info.txt${plain}"
    echo -e "3. 使用IP方式访问更简单，无需额外配置"
}

# 显示菜单
show_menu 