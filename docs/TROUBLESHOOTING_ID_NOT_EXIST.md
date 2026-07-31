# 排查：本地用 ID 连接 VPS 提示「ID 不存在」

## 背景机制

LUODA 的 ID 连接依赖一台 **rendezvous 信令服务器（luoda-server / hbbs）**：

1. **被控端**（VPS 上的 LUODA）启动后，必须把自己的 ID 通过 UDP `RegisterPeer` 注册到 hbbs，hbbs 在内存在线表里记下 `ID -> 被控端地址`。
2. **控制端**（本地电脑）用 ID 连接时，向 hbbs 发 `PunchHoleRequest{id}`，hbbs 查在线表：
   - 查到 -> 返回被控端地址，开始打洞/直连；
   - **查不到 -> 返回 `ID_NOT_EXIST`，控制端报「ID 不存在」**（`src/client.rs`，错误码定义 `libs/hbb_common/protos/rendezvous.proto`）。

> ⚠️ `ID_NOT_EXIST` 的判定逻辑在 **服务端（hbbs）**，不在本客户端仓库。本客户端只能接收并展示该错误。

## 常见误解：VPS 上「IP:端口 登录成功」≠ ID 已可查询

VPS 日志里的「登录成功」可能只表示 **被控端与 hbbs 的连接/握手通了**，并不代表 ID 已经进入 hbbs 的在线表。只有当被控端完成 **密钥确认（key confirmed）** 后，才会真正发送 `RegisterPeer{id}` 把 ID 登记为可查询的在线 peer（见 `src/rendezvous_mediator.rs` 的 `register_peer`）。

如果密钥握手未完成（UDP 丢包、PK mismatch 等），被控端会一直停在 `RegisterPk` 握手阶段，**ID 永远不会登记到 hbbs**，控制端就会持续看到「ID 不存在」。

## 排查步骤

### 1. 确认被控端（VPS）真的完成了 ID 注册

在 VPS 上查看 LUODA 日志，搜索以下关键行：

- ✅ `rendezvous peer registration acknowledged` —— **ID 已成功注册到 hbbs**（看到这行才说明可被查询）
- ⚠️ `id not registered yet; sending RegisterPk handshake only` —— 仍在握手阶段，**ID 未登记**（这是问题根因）
- ⚠️ `identity confirmed; peer registration sent` —— 密钥刚确认，已补发注册

如果只看到握手相关日志、迟迟没有 `rendezvous peer registration acknowledged`，说明 ID 没注册成功，需要排查 UDP 到 hbbs 的连通性。

### 2. 确认两端连的是同一台 hbbs

控制端和被控端必须注册到 / 查询同一台 rendezvous 服务器，否则必然「ID 不存在」。

默认服务器：`rev.dicad.cn:21116`（解析到 VPS `47.114.75.115`）。

检查两端配置项 `custom-rendezvous-server` 是否一致：

- 配置文件位置：`%AppData%\LUODA\config\LUODA.toml`（Windows）
- 应为空（用默认 `rev.dicad.cn`）或显式写 `rev.dicad.cn`

> 注意：代码会自动忽略 `127.0.0.1` / `localhost` / 内网地址这类调试残留值（`config.rs` 的 `is_loopback_or_test_server`），回退到默认服务器。

### 3. 确认 hbbs（luoda-server）在线表查询逻辑

在 VPS 上检查 hbbs 容器日志：

```bash
# 查看 hbbs 容器日志，搜索被控端 ID 是否注册成功
docker logs <hbbs容器名> 2>&1 | grep <被控端ID>

# 确认 hbbs 监听正常（21116 UDP/TCP 用于 rendezvous）
netstat -ulnp | grep 21116
```

- 若 hbbs 日志里能看到被控端的注册记录，但控制端仍报「ID 不存在」，可能是 **hbbs 在线表过期或被控端注册后掉线**（hbbs 靠心跳保活，默认 15 秒无心跳会摘除）。
- 若 hbbs 完全没有该 ID 的注册记录，则是被控端没注册上来（回到步骤 1）。

### 4. 确认 UDP 21116 可达

被控端通过 UDP 向 hbbs 注册。若 VPS 防火墙/安全组放行了 TCP 但没放行 UDP，会导致握手包能到、注册包丢失：

```bash
# 在 VPS 上确认 UDP 21116 放行（阿里云需在安全组同时放行 TCP+UDP 21116-21119）
# 在本地测试 UDP 可达性（hbbs 默认会在 UDP 收到包后回包）
```

阿里云/腾讯云 VPS 需在**安全组**同时放行：
- TCP 21116, 21117, 21118, 21119
- **UDP 21116**（最易遗漏，rendezvous 注册走 UDP）

## 客户端侧已做的改进（v2.2.1）

本版本对「ID 不存在」做了客户端侧优化（缓解瞬时未注册的场景，但根因在服务端）：

1. **重试**：控制端收到 `ID_NOT_EXIST` 后会自动重试 2 次（间隔 2 秒），避免被控端正处于注册过程中时误报。
2. **诊断信息**：最终失败时错误信息会附带当前查询的 rendezvous 服务器地址和本地 ID，便于判断是否连错服务器。
3. **注册提速**：被控端在尚未成功注册或刚从失败恢复时，将注册重发间隔从 15 秒缩短到 5 秒，缩短「ID 不可查询」窗口。
4. **诊断日志**：被控端 `register_peer` 现在会明确区分「发送握手（ID 未登记）」与「发送注册（ID 已登记）」并输出密钥确认状态。

## 仍提示「ID 不存在」时的最终建议

如果上述排查都正常仍报错，根因在 **luoda-server（hbbs）服务端**的在线表管理，需要检查/重启 hbbs 服务，或确认被控端 LUODA 进程确实在运行并已联网。
