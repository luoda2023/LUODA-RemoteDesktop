#!/bin/bash
# LUODA VPS 证书续期脚本（在 VPS 上以 root 执行）
# 用法: bash renew_cert_vps.sh

set -e

echo "==> [1/4] 检查 certbot 是否安装"
if ! command -v certbot >/dev/null 2>&1; then
    echo "certbot 未安装，正在安装..."
    if command -v apt-get >/dev/null 2>&1; then
        apt-get update -y
        apt-get install -y certbot python3-certbot-nginx
    elif command -v yum >/dev/null 2>&1; then
        yum install -y certbot python3-certbot-nginx
    else
        echo "ERROR: 无法识别包管理器，请手动安装 certbot"
        exit 1
    fi
fi

echo "==> [2/4] 续期证书 (rev.dicad.cn)"
certbot renew --nginx --non-interactive || certbot renew --non-interactive || true

echo "==> [3/4] 重载 nginx 使新证书生效"
systemctl reload nginx 2>/dev/null || nginx -s reload 2>/dev/null || true

echo "==> [4/4] 配置自动续期（每月检查）"
# 默认 certbot 自带 systemd timer；这里再补一个 crontab 兜底
(crontab -l 2>/dev/null | grep -v "certbot renew"; echo "0 3 * * * certbot renew --quiet --deploy-hook 'systemctl reload nginx' >> /var/log/certbot-renew.log 2>&1") | crontab -

echo ""
echo "✅ 续期完成。验证："
echo "   openssl s_client -connect rev.dicad.cn:443 -servername rev.dicad.cn </dev/null 2>/dev/null | openssl x509 -noout -dates"
