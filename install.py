#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import os
import sys
import subprocess
import socket
import json
import base64
import random
import string
import locale
from pathlib import Path
from typing import Optional

def safe_input(prompt: str) -> str:
    """安全的输入函数，处理编码问题"""
    try:
        return input(prompt)
    except UnicodeDecodeError:
        # 如果发生编码错误，尝试使用系统默认编码
        sys_encoding = locale.getpreferredencoding()
        if sys.version_info[0] < 3:
            return input(prompt.encode(sys_encoding)).decode(sys_encoding)
        else:
            return input(prompt)
    except Exception as e:
        # 如果还是失败，返回空字符串
        print(f"输入错误: {e}")
        return ""

class HysteriaInstaller:
    def __init__(self):
        self.workspace_dir = Path("/etc/hysteria")
        self.subscribe_dir = self.workspace_dir / "subscribe"
        self.config_file = self.workspace_dir / "config.yaml"
        self.cert_file = self.workspace_dir / "cert.crt"
        self.key_file = self.workspace_dir / "private.key"
        
    def check_root(self) -> bool:
        return os.geteuid() == 0

    def get_public_ip(self) -> str:
        try:
            import urllib.request
            with urllib.request.urlopen('https://api.ipify.org') as response:
                return response.read().decode('utf-8')
        except:
            return safe_input("请手动输入服务器公网IP: ")

    def check_port(self, port: int) -> bool:
        try:
            sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            result = sock.connect_ex(('127.0.0.1', port))
            sock.close()
            return result == 0
        except:
            return False

    def install_dependencies(self):
        packages = ["curl", "openssl", "nginx", "certbot"]
        subprocess.run(["apt", "update"], check=True)
        subprocess.run(["apt", "install", "-y"] + packages, check=True)
        
        # 移除默认的 Nginx 配置
        default_conf = Path("/etc/nginx/sites-enabled/default")
        if default_conf.exists():
            default_conf.unlink()

    def check_service_status(self) -> bool:
        try:
            result = subprocess.run(
                ["systemctl", "is-active", "hysteria-server"],
                capture_output=True,
                text=True
            )
            return result.stdout.strip() == "active"
        except:
            return False

    def setup_firewall(self, port: int):
        print(f"配置防火墙规则 (TCP/UDP: {port}, 80, 443)...")
        try:
            subprocess.run(["ufw", "allow", f"{port}/tcp"], check=True)
            subprocess.run(["ufw", "allow", f"{port}/udp"], check=True)
            subprocess.run(["ufw", "allow", "80/tcp"], check=True)
            subprocess.run(["ufw", "allow", "443/tcp"], check=True)
            subprocess.run(["ufw", "--force", "enable"], check=True)
            print("防火墙配置完成")
        except:
            print("警告: 防火墙配置可能未完全成功，请手动检查")

    def generate_random_password(self, length: int = 16) -> str:
        chars = string.ascii_letters + string.digits
        return ''.join(random.choice(chars) for _ in range(length))

    def create_config_yaml(self, port: int, password: str, domain: Optional[str] = None):
        config = {
            "listen": f":{port}",
            "auth": {
                "type": "password",
                "password": password
            },
            "tls": {
                "cert": str(self.cert_file),
                "key": str(self.key_file)
            }
        }
        
        if domain:
            config["tls"]["sni"] = domain

        self.workspace_dir.mkdir(parents=True, exist_ok=True)
        with open(self.config_file, 'w') as f:
            json.dump(config, f, indent=2)

    def setup_ssl(self, domain: str) -> bool:
        try:
            subprocess.run([
                "certbot", "certonly", "--nginx",
                "-d", domain,
                "--non-interactive",
                "--agree-tos",
                f"--email", f"admin@{domain}",
                "--expand"
            ], check=True)
            
            cert_path = Path(f"/etc/letsencrypt/live/{domain}")
            import shutil
            shutil.copy2(cert_path / "fullchain.pem", self.cert_file)
            shutil.copy2(cert_path / "privkey.pem", self.key_file)
            os.chmod(self.cert_file, 0o644)
            os.chmod(self.key_file, 0o600)
            return True
        except:
            return False

    def generate_self_signed_cert(self, ip: str):
        print("正在生成自签名证书...")
        try:
            # 确保目录存在
            self.workspace_dir.mkdir(parents=True, exist_ok=True)
            print(f"工作目录已创建: {self.workspace_dir}")
            
            subprocess.run([
                "openssl", "req", "-x509",
                "-nodes",
                "-newkey", "rsa:2048",
                "-days", "365",
                "-keyout", str(self.key_file),
                "-out", str(self.cert_file),
                "-subj", f"/CN={ip}"
            ], check=True, capture_output=True, text=True)
            
            os.chmod(self.cert_file, 0o644)
            os.chmod(self.key_file, 0o600)
            print("证书生成成功")
            
        except subprocess.CalledProcessError as e:
            print(f"生成证书时出错: {e.stderr}")
            raise
        except Exception as e:
            print(f"发生错误: {e}")
            raise

    def create_systemd_service(self):
        # 确保目录存在
        self.workspace_dir.mkdir(parents=True, exist_ok=True)
        
        service_content = """[Unit]
Description=Hysteria Server
After=network.target

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
"""
        with open("/etc/systemd/system/hysteria-server.service", 'w') as f:
            f.write(service_content)

    def generate_clash_config(self) -> str:
        # 读取配置文件获取服务器信息
        with open(self.config_file, 'r') as f:
            config = json.load(f)
        
        port = int(config['listen'].replace(':', ''))
        password = config['auth']['password']
        
        # 获取服务器地址
        server_ip = self.get_public_ip()
        
        return f"""mixed-port: 7890
allow-lan: true
mode: rule
log-level: info

proxies:
  - name: "Hysteria2"
    type: hysteria2
    server: {server_ip}
    port: {port}
    password: "{password}"
    sni: {server_ip}
    skip-cert-verify: true

proxy-groups:
  - name: "PROXY"
    type: select
    proxies:
      - Hysteria2
      - DIRECT

rules:
  - MATCH,PROXY"""

    def setup_nginx(self, subscribe_path: str):
        print("配置 Nginx...")
        
        # 删除所有已存在的配置
        conf_dir = Path("/etc/nginx/conf.d")
        sites_enabled_dir = Path("/etc/nginx/sites-enabled")
        
        # 清理 conf.d 目录
        if conf_dir.exists():
            for conf in conf_dir.glob("*.conf"):
                conf.unlink()
        
        # 清理 sites-enabled 目录
        if sites_enabled_dir.exists():
            for conf in sites_enabled_dir.glob("*"):
                conf.unlink()
        
        # 创建主配置
        main_config = """user www-data;
worker_processes auto;
pid /run/nginx.pid;

events {
    worker_connections 768;
    multi_accept on;
}

http {
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    types_hash_max_size 2048;
    server_tokens off;

    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    access_log /var/log/nginx/access.log combined buffer=512k flush=1m;
    error_log /var/log/nginx/error.log warn;

    gzip on;
    gzip_vary on;
    gzip_proxied any;
    gzip_comp_level 6;
    gzip_types text/plain text/css application/json application/x-javascript text/xml application/xml application/xml+rss text/javascript;

    include /etc/nginx/conf.d/*.conf;
}"""
        
        Path("/etc/nginx/nginx.conf").write_text(main_config)
        
        # 创建订阅配置
        subscribe_config = f"""server {{
    listen 80;
    listen [::]:80;
    server_name _;
    
    charset utf-8;
    
    access_log /var/log/nginx/subscribe-access.log combined buffer=512k flush=1m;
    error_log /var/log/nginx/subscribe-error.log warn;
    
    root /etc/hysteria/subscribe;
    
    # Clash 配置
    location /{subscribe_path}/clash {{
        alias /etc/hysteria/subscribe/clash.yaml;
        default_type text/plain;
        add_header Content-Type 'text/plain; charset=utf-8';
        add_header Cache-Control 'no-store, no-cache, must-revalidate, proxy-revalidate, max-age=0';
        add_header Pragma 'no-cache';
        add_header Expires '0';
    }}
    
    location = /404.html {{
        internal;
        return 404 "404 Not Found";
    }}
}}"""
        
        # 创建配置文件
        nginx_conf = Path("/etc/nginx/conf.d/hysteria-subscribe.conf")
        nginx_conf.write_text(subscribe_config)
        
        # 确保订阅目录存在并创建订阅文件
        subscribe_dir = Path("/etc/hysteria/subscribe")
        subscribe_dir.mkdir(parents=True, exist_ok=True)
        
        # 生成并保存 Clash 配置
        clash_config = self.generate_clash_config()
        clash_file = subscribe_dir / "clash.yaml"
        clash_file.write_text(clash_config)
        
        # 设置正确的权限
        os.system(f"chown -R www-data:www-data {subscribe_dir}")
        os.system(f"chmod -R 755 {subscribe_dir}")
        os.system(f"find {subscribe_dir} -type f -exec chmod 644 {{}} \\;")
        
        # 创建日志目录并设置权限
        log_dir = Path("/var/log/nginx")
        log_dir.mkdir(parents=True, exist_ok=True)
        os.system(f"chown -R www-data:www-data {log_dir}")
        
        # 测试配置并重启
        try:
            subprocess.run(["nginx", "-t"], check=True, capture_output=True)
            subprocess.run(["systemctl", "restart", "nginx"], check=True)
            print("Nginx 配置完成")
        except subprocess.CalledProcessError as e:
            print(f"Nginx 配置错误: {e.stderr.decode()}")
            raise

    def setup_subscription(self, server_ip: str, port: int, password: str, domain: Optional[str] = None):
        # 确保目录存在
        self.workspace_dir.mkdir(parents=True, exist_ok=True)
        self.subscribe_dir.mkdir(parents=True, exist_ok=True)
        
        subscribe_path = os.urandom(16).hex()
        protocol = "https" if domain else "http"
        host = domain if domain else server_ip
        
        config = f"""mixed-port: 7890
allow-lan: true
mode: rule
proxies:
  - name: "Hysteria2-{host}"
    type: hysteria2
    server: {host}
    port: {port}
    password: "{password}"
    sni: {host}
    skip-cert-verify: true

proxy-groups:
  - name: PROXY
    type: select
    proxies:
      - "Hysteria2-{host}"
      - DIRECT

rules:
  - MATCH,PROXY"""

        with open(self.subscribe_dir / "clash.yaml", "w") as f:
            f.write(config)

        # 配置 Nginx
        self.setup_nginx(subscribe_path)

        base_url = f"{protocol}://{host}/{subscribe_path}/clash"
        with open(self.subscribe_dir / "info.txt", "w") as f:
            f.write(f"Clash订阅：{base_url}\n")
            f.write(f"Shadowrocket订阅：sub://{base64.b64encode(base_url.encode()).decode()}")

    def show_completion_info(self, server_ip: str, port: int, password: str, domain: Optional[str] = None):
        print("\n=== 安装完成 ===")
        print(f"服务器: {domain or server_ip}")
        print(f"端口: {port}")
        print(f"密码: {password}")
        
        # 显示订阅信息
        info_file = self.subscribe_dir / "info.txt"
        if info_file.exists():
            print("\n=== 订阅信息 ===")
            print(info_file.read_text())
        
        # 检查服务状态
        if self.check_service_status():
            print("\n✅ 服务状态: 运行中")
        else:
            print("\n❌ 警告: 服务可能未正常运行")
            print("请检查服务状态: systemctl status hysteria-server")
        
        print("\n=== 客户端配置 ===")
        print("1. 使用订阅链接（推荐）")
        print("   - Clash Meta")
        print("   - Shadowrocket")
        print("2. 手动配置")
        print(f"   - 地址: {domain or server_ip}")
        print(f"   - 端口: {port}")
        print(f"   - 密码: {password}")
        print(f"   - SNI: {domain or server_ip}")
        print("   - 跳过证书验证: 是")
        
        print("\n=== 其他信息 ===")
        print("1. 配置文件: /etc/hysteria/config.yaml")
        print("2. 服务控制:")
        print("   systemctl start/stop/restart hysteria-server")
        print("3. 查看日志:")
        print("   journalctl -u hysteria-server -n 50")

    def install(self):
        if not self.check_root():
            print("请使用root用户运行此脚本")
            return

        try:
            print("开始安装 Hysteria 2...")
            
            server_ip = self.get_public_ip()
            print(f"服务器IP: {server_ip}")
            
            self.install_dependencies()
            
            use_domain = safe_input("是否使用域名？[y/N]: ").lower() == 'y'
            domain = safe_input("请输入域名: ").strip() if use_domain else None
            
            port = int(safe_input("请设置端口 [443]: ") or "443")
            if self.check_port(port):
                print("端口已被占用")
                return
            
            password = safe_input("请设置密码 [随机生成]: ").strip() or self.generate_random_password()
            if not password.strip():
                password = self.generate_random_password()
                print(f"已生成随机密码: {password}")
            
            self.setup_firewall(port)
            
            if domain:
                print("配置SSL证书...")
                if not self.setup_ssl(domain):
                    print("SSL证书配置失败")
                    return
            else:
                print("生成自签名证书...")
                self.generate_self_signed_cert(server_ip)
            
            print("安装 Hysteria 2...")
            subprocess.run("curl -fsSL https://get.hy2.sh/ | bash", shell=True, check=True)
            
            print("创建配置文件...")
            self.create_config_yaml(port, password, domain)
            
            print("创建系统服务...")
            self.create_systemd_service()
            
            print("启动服务...")
            subprocess.run(["systemctl", "daemon-reload"], check=True)
            subprocess.run(["systemctl", "enable", "hysteria-server"], check=True)
            subprocess.run(["systemctl", "restart", "hysteria-server"], check=True)
            
            print("生成订阅信息...")
            self.setup_subscription(server_ip, port, password, domain)
            
            self.show_completion_info(server_ip, port, password, domain)
            
        except Exception as e:
            print(f"\n安装过程中出错: {e}")
            print("如果问题持续存在，请检查以下内容：")
            print("1. 确保所有必需的端口未被占用")
            print("2. 检查系统防火墙设置")
            print("3. 确保有足够的磁盘空间")
            print("4. 查看详细日志: journalctl -u hysteria-server")

    def uninstall(self):
        print("开始卸载 Hysteria 2...")
        
        # 停止并禁用服务
        subprocess.run(["systemctl", "stop", "hysteria-server"], check=False)
        subprocess.run(["systemctl", "disable", "hysteria-server"], check=False)
        
        # 清理 Nginx 配置
        nginx_configs = [
            Path("/etc/nginx/conf.d/hysteria-subscribe.conf"),
            Path("/etc/nginx/sites-enabled/hysteria-subscribe"),
            Path("/etc/nginx/sites-available/hysteria-subscribe")
        ]
        
        # 删除所有 Nginx 相关配置
        for config in nginx_configs:
            if config.exists():
                config.unlink()
        
        # 清理主要文件和目录
        files_to_remove = [
            "/etc/systemd/system/hysteria-server.service",
            "/etc/systemd/system/hysteria-server@.service",
            "/usr/local/bin/hysteria",
            str(self.workspace_dir),
            "/var/log/nginx/subscribe-access.log",
            "/var/log/nginx/subscribe-error.log"
        ]
        
        for file in files_to_remove:
            path = Path(file)
            if path.is_file():
                path.unlink(missing_ok=True)
            elif path.is_dir():
                import shutil
                shutil.rmtree(path, ignore_errors=True)
        
        # 恢复 Nginx 默认配置
        default_conf = """server {
    listen 80 default_server;
    listen [::]:80 default_server;
    root /var/www/html;
    index index.html index.htm index.nginx-debian.html;
    server_name _;
    location / {
        try_files $uri $uri/ =404;
    }
}"""
        
        nginx_default = Path("/etc/nginx/sites-enabled/default")
        nginx_default.write_text(default_conf)
        
        # 重启 Nginx
        try:
            subprocess.run(["nginx", "-t"], check=True, capture_output=True)
            subprocess.run(["systemctl", "restart", "nginx"], check=True)
        except:
            print("警告: Nginx 重启失败，请手动检查配置")
        
        # 重新加载 systemd
        subprocess.run(["systemctl", "daemon-reload"], check=True)
        
        print("\n清理完成！以下文件和目录已被删除：")
        print("1. Hysteria 2 主程序")
        print("2. 配置文件和证书")
        print("3. 系统服务文件")
        print("4. Nginx 配置和日志")
        print("5. 订阅文件和目录")

    def main(self):
        if not self.check_root():
            print("请使用root用户运行此脚本")
            return

        while True:
            print("\n=== Hysteria 2 管理 ===")
            print("1. 安装")
            print("2. 卸载")
            print("0. 退出")
            
            choice = safe_input("请选择 [0-2]: ").strip()
            
            if choice == "1":
                self.install()
            elif choice == "2":
                if safe_input("确认卸载？[y/N]: ").lower() == 'y':
                    self.uninstall()
            elif choice == "0":
                break
            else:
                print("无效的选项")

if __name__ == "__main__":
    # 设置默认编码为 UTF-8
    if sys.stdout.encoding != 'UTF-8':
        sys.stdout = open(sys.stdout.fileno(), mode='w', encoding='UTF-8', buffering=1)
    if sys.stderr.encoding != 'UTF-8':
        sys.stderr = open(sys.stderr.fileno(), mode='w', encoding='UTF-8', buffering=1)
    
    installer = HysteriaInstaller()
    installer.main() 