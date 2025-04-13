#!/bin/bash

# 检查是否为root用户
if [ "$EUID" -ne 0 ]; then
    echo "请使用root用户运行此脚本"
    exit 1
fi

# 检查Python3是否安装
if ! command -v python3 &> /dev/null; then
    echo "正在安装Python3..."
    apt update
    apt install -y python3
fi

# 创建临时目录
TMP_DIR=$(mktemp -d)
cd "$TMP_DIR" || exit 1

# 下载Python脚本
echo "下载安装脚本..."
curl -fsSL https://raw.githubusercontent.com/xiaosuhuai/hysteria2-script/main/install.py -o install.py

# 运行Python脚本
python3 install.py "$@"

# 清理
rm -rf "$TMP_DIR" 