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
from pathlib import Path
from typing import Optional

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
            return input("请手动输入服务器公网IP: ")

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

    def setup_firewall(self, port: int):
        try:
            subprocess.run(["ufw", "allow", f"{port}/tcp"], check=True)
            subprocess.run(["ufw", "allow", f"{port}/udp"], check=True)
            subprocess.run(["ufw", "allow", "80/tcp"], check=True)
            subprocess.run(["ufw", "allow", "443/tcp"], check=True)
            subprocess.run(["ufw", "--force", "enable"], check=True)
        except:
            pass

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
            shutil.copy2(cert_path / "fullchain.pem", self.cert_file)
            shutil.copy2(cert_path / "privkey.pem", self.key_file)
            os.chmod(self.cert_file, 0o644)
            os.chmod(self.key_file, 0o600)
            return True
        except:
            return False

    def generate_self_signed_cert(self, ip: str):
        subprocess.run([
            "openssl", "req", "-x509",
            "-nodes",
            "-newkey", "rsa:2048",
            "-days", "365",
            "-keyout", str(self.key_file),
            "-out", str(self.cert_file),
            "-subj", f"/CN={ip}"
        ], check=True)
        
        os.chmod(self.cert_file, 0o644)
        os.chmod(self.key_file, 0o600)

    def create_systemd_service(self):
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

    def setup_subscription(self, server_ip: str, port: int, password: str, domain: Optional[str] = None):
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

        self.subscribe_dir.mkdir(parents=True, exist_ok=True)
        with open(self.subscribe_dir / "clash.yaml", "w") as f:
            f.write(config)

        base_url = f"{protocol}://{host}/{subscribe_path}/clash"
        with open(self.subscribe_dir / "info.txt", "w") as f:
            f.write(f"Clash订阅：{base_url}\n")
            f.write(f"Shadowrocket订阅：sub://{base64.b64encode(base_url.encode()).decode()}")

    def install(self):
        if not self.check_root():
            print("请使用root用户运行此脚本")
            return

        print("开始安装 Hysteria 2...")
        
        server_ip = self.get_public_ip()
        print(f"服务器IP: {server_ip}")
        
        self.install_dependencies()
        
        use_domain = input("是否使用域名？[y/N]: ").lower() == 'y'
        domain = input("请输入域名: ").strip() if use_domain else None
        
        port = int(input("请设置端口 [443]: ") or "443")
        if self.check_port(port):
            print("端口已被占用")
            return
        
        password = input("请设置密码 [随机生成]: ").strip() or self.generate_random_password()
        
        self.setup_firewall(port)
        
        if domain:
            if not self.setup_ssl(domain):
                print("SSL证书配置失败")
                return
        else:
            self.generate_self_signed_cert(server_ip)
        
        subprocess.run("curl -fsSL https://get.hy2.sh/ | bash", shell=True, check=True)
        
        self.create_config_yaml(port, password, domain)
        self.create_systemd_service()
        
        subprocess.run(["systemctl", "daemon-reload"], check=True)
        subprocess.run(["systemctl", "enable", "hysteria-server"], check=True)
        subprocess.run(["systemctl", "restart", "hysteria-server"], check=True)
        
        self.setup_subscription(server_ip, port, password, domain)
        
        print("\n=== 安装完成 ===")
        print(f"服务器: {domain or server_ip}")
        print(f"端口: {port}")
        print(f"密码: {password}")
        print("\n订阅信息已保存到: /etc/hysteria/subscribe/info.txt")

    def uninstall(self):
        print("开始卸载 Hysteria 2...")
        
        subprocess.run(["systemctl", "stop", "hysteria-server"], check=False)
        subprocess.run(["systemctl", "disable", "hysteria-server"], check=False)
        
        files_to_remove = [
            "/etc/systemd/system/hysteria-server.service",
            "/usr/local/bin/hysteria",
            self.workspace_dir
        ]
        
        for file in files_to_remove:
            path = Path(file)
            if path.is_file():
                path.unlink()
            elif path.is_dir():
                import shutil
                shutil.rmtree(path)
        
        subprocess.run(["systemctl", "daemon-reload"], check=True)
        print("卸载完成")

    def main(self):
        if not self.check_root():
            print("请使用root用户运行此脚本")
            return

        while True:
            print("\n=== Hysteria 2 管理 ===")
            print("1. 安装")
            print("2. 卸载")
            print("0. 退出")
            
            choice = input("请选择 [0-2]: ").strip()
            
            if choice == "1":
                self.install()
            elif choice == "2":
                if input("确认卸载？[y/N]: ").lower() == 'y':
                    self.uninstall()
            elif choice == "0":
                break
            else:
                print("无效的选项")

if __name__ == "__main__":
    installer = HysteriaInstaller()
    installer.main() 