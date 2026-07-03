# LUODA 服务器 Ed25519 密钥对

## 文件说明

- `id_ed25519` — HBBS 服务器的私钥（用于 TLS 加密通信和服务器身份验证）
- `id_ed25519.pub` — HBBS 服务器的公钥（`OQnLEvt6xjfPCUc1ozpTUiAxijwnn624zy0GH9IxX90=`）

## 用途

这两个文件是 LUODA 中继服务器（HBBS）的 Ed25519 密钥对，部署在 VPS 服务器（47.114.75.115）的 Docker 容器中使用。

## 关键约束

**⚠️ 禁止删除或更换这两个文件！** 否则会导致：
1. HBBS 容器重启时自动生成**新密钥对**，所有客户端的密钥匹配关系将失效
2. 客户端连接时出现 **KEY 不匹配（LICENSE_MISMATCH）** 错误
3. 所有已配对的设备需要重新确认密钥

## Docker 部署

这两个文件必须通过 **bind mount 只读挂载** 到容器内，防止 HBBS 自动重新生成：

```yaml
volumes:
  - ./server-keys/id_ed25519:/data/id_ed25519:ro
  - ./server-keys/id_ed25519.pub:/data/id_ed25519.pub:ro
```

## 历史记录

- 2026-07-02 之前：服务器使用此密钥对，客户端连接正常
- 2026-07-02 03:24 UTC：Docker 容器重启，volume 为空，HBBS 自动生成了**新密钥对**
- 2026-07-03：发现 KEY 不匹配问题，手动恢复为旧密钥对

## 验证方法

容器启动后，检查日志确认使用正确的公钥：

```bash
docker logs luoda | grep "Key:"
# 应输出: Key: OQnLEvt6xjfPCUc1ozpTUiAxijwnn624zy0GH9IxX90=
```
