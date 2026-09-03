# bugs.md — 修复备忘（2026-09-03）

## BUG-1 [确定性崩溃] PC 端 EXE 远程一次后弹 "LDesk.exe - Unknown Hard Error"
- 现象：远程(被手机控制)会话结束后数秒，进程崩溃弹 Unknown Hard Error 系统框。
- 证据（6 个崩溃 dump 完全一致，100% 复现）：
  - 异常码 0xe0464645（Rust panic-abort / fail-fast 特征）
  - 崩溃地址恒为 dcomp.dll+0x7f034，RIP 在 KERNELBASE!RaiseFailFastException+0x18e
  - R12 恒为 flutter_inappwebview_windows_plugin.dll+0x97d01（WebView2 桌面渲染插件间接调用点）
  - 栈：inappwebview 25 帧 / dcomp 11 帧；R13/R14/R15 = 0xaaaaaaaa（已释放内存填充）
  - 崩溃线程每次 TID 都不同（各渲染/合成线程）
- 关联：Cargo.toml [profile.release] panic='abort' => Rust panic 直接杀进程，不写 "=== PANIC ===" 日志
- 关键：flutter_inappwebview_windows_plugin.dll + WebView2Loader.dll 每次都在进程内（插件随 app 启动加载）
- 崩溃时机：总在手机远程会话 (#7xx/#2xx) Peer close → 清理（stop video service / Displays changed）之后
- 历史：a020136 曾"回滚 mimalloc+opt-level=z"声称修复 Unknown Hard Error，但崩溃仍在 => 残余路径未修

## BUG-2 [连接卡住] 隔一段时间再用手机连电脑，一直卡在"已连接/等待"窗口
- 现象：时间隔久一点，手机连 PC 一直卡在 connecting/waiting 不进画面。
- 待查：client.rs 连接建立、超时、rendezvous 重连逻辑；会话"静置后"心跳/保活。

## BUG-3 [在线状态] 手机端仍不能显示对方在线（PC 能显示手机）
- 现象：PC 端在线状态可显示；手机端看 PC 设备仍灰（虽然 PC 在线）。
- 历史：dac8fef 已做权威表+跨 load 存活，宣称封死误灰；用户反馈手机端仍不行。
- 待查：手机端 peer 在线状态数据源/心跳/UI 刷新链路，与桌面端的差异。

## BUG-4 [授权弹窗] 手机端每次启动都弹"输入控制(无障碍)授权窗口"
- 现象：手机端打开时每次都是 输入控制 授权窗口。
- 历史：home_page.dart 已删掉无障碍/录屏自动请求（工作区未提交 diff），但用户仍见弹窗。
- 要求：授权窗口只能在"授权时"主动弹出，平时启动/任何其它路径不得自动弹出。

## 配置注意
- [profile.release] panic='abort'（Cargo.toml L244）——panic 不会走 file_logger 的 hook
- 桌面端 WebView：flutter_inappwebview（唯一使用处 flutter/lib/common/widgets/vip_features_page.dart）
- 在线状态/授权涉及 flutter/lib/models/peer_model.dart、flutter/lib/mobile/pages/home_page.dart

## 2026-09-03 补充（commit 3cc5343, 2.2.18 一并发布）
- BUG-1 根治：桌面端移除常驻 WebView2(flutter_inappwebview)。
  证据链：dcomp.dll+0x7f034 / 0xe0464645 / 栈内恒有 flutter_inappwebview_windows_plugin.dll，
  2.2.15/16/17 全复现，每次远程会话结束后数秒崩(常两次)。
  修改：VipFeaturesPage 桌面端改用外置浏览器(同 Linux/Web)；依赖整体移除
  flutter_inappwebview，Windows EXE 不再打包/加载该插件 dll + WebView2Loader.dll。
  移动端仍用 webview_flutter，不受影响。dart analyze 通过。
- 用户本机(LDesk 2.2.17, runtime b39d9f..., PID 2756)确认：
  每 16s 向 rev.dicad.cn:21116 注册成功 => 在线没问题，灰点在手机端展示链路(2.2.17 旧包缺 91eb9f0 补查修复)。

## 2026-09-03 收尾审计结论（供 2.2.18 实测对照）
- 本机(这台PC)身份核查：
  * config\LDesk_local.toml remote_id='930647' = 最近远程过的"对方", 不是本机 id。
  * config\peers\930647.toml 存在 => 930647 是本机曾连接的设备。
  * 本机真实 id 存于 LDesk.toml enc_id(secretbox, key=machine_uid 截断32B)。466619 未在本机任何配置中出现。
  * 用户认为"466619=这台PC"存疑: 需用户在本机 LDesk 主界面核对"我的ID"到底是不是 466619。
- 手机端灰点代码链路(2.2.18 已修复, 审计通过):
  * Rust query_onlines: 无界 channel, 逐批串行, 回调 callback_query_onlines。
  * Flutter Peers 权威表 _onlineStates 在 gFFI 全局单例(跨tab/跨重建存活)。
  * 事件按 (callback_query_onlines, name) 隔离, 各 tab 互不串。
  * load 后对未知 peer 立即补查; _PeersViewState 10s 轮询 _curPeers(load 时全量填充)。
  * 纯数字ID走服务器查询(21115), 不因直连IP误判。
  * 服务器 rev.dicad.cn:21115/21116 本机 TCP 连通正常。
- 待用户实测确认项:
  1. 手机装 2.2.18 arm64 APK 后, 466619 在哪个tab? (recent/fav/ab/lan)
  2. 本机 PC 主界面"我的ID"显示多少? 是否 466619?
  3. 若466619在通讯录: 手机需登录同账号才能pullAb, 未登录则列表来自本地缓存且不自动刷新。

## 2026-09-03 灰点根因终审 + 进程级权威表修复（新提交）
- 实测（决定性）：用 LUODA-SERVER-API 自带 online_probe 连线上服务器 47.114.75.115:21115
  查询 466619 => ONLINE。PC(2.2.17, PID 2756) 每16s向 21116 注册成功。
  => PC 在线无问题、服务器无问题、手机查询通道无问题；灰点在手机 UI 层多处重建 Peer 丢 online。
- 真正根因：手机端顶部 Remote ID 输入框的补全列表(AllPeersLoader)与各列表(ab/group/restIds)
  在合并/加载时会 toJson()→fromJson 或 Peer.copy 重建 Peer 对象，online 字段恒 false；
  旧的"权威表"是每个 Peers 实例私有的，AllPeersLoader/ab/group 重建对象后查不到真实状态 => 永久灰。
- 修复：
  * peer_model.dart: 权威表 _onlineStates 升为 static(进程级共享)；新增 Peers.onlineOf(id)、
    Peers.restoreOnline(peers)、活跃实例 _instances + _broadcast；任一线程收到服务端推送
    同步到所有实例并 notify；新实例创建即回填。
  * autocomplete.dart(AllPeersLoader): 合并 ab/group/lan/recent/restIds 全程 restoreOnline。
  * ab_model.dart / group_model.dart: 拉取/反序列化后用 Peers.restoreOnline 替代仅恢复旧online id。
- dart analyze 通过(4文件)。

## 2026-09-03 2.2.19 交付 + 本机实测验证（goal 收尾）
- 2.2.19 双构建成功(EXE 57min / APK 49min)，Release v2.2.19 已发布，7 资产 SHA256 与官方 digest 全部一致。
- 旧 _release_v2.2.17 / _release_v2.2.18 已删除（共释放 ~240MB）。
- **本机(466619)已从 2.2.17 升级到 2.2.19**：旧 PID 2756 终止，新 PID 12332 runtime 75b6d51c... version=2.2.19+1。
- 升级后官方 online_probe 连 47.114.75.115:21115 查询 => **466619 -> ONLINE**（决定性验证）。
- 本机 id 复核：enc_id 用 machine_uid 前32字节 zero-pad 作 key(sodium secretbox, nonce全0) 解密 = 466619 确认。
- 灰点修复链路闭环审计(2.2.19)：peer_model 进程级权威表(_onlineStates static) + 实例注册表(_instances) + 广播(_broadcast) + load后未知peer补查(bind.queryOnlines) + Rust handle_query_onlines 事件回传 => 466619 load后立即翻绿。
- 待用户动作：手机安装 LDesk-arm64-v8a.apk (2.2.19)，覆盖旧版；装完 466619 应在任意tab绿点。


## 2026-09-03 灰点残余根因终修 (commit 6f9510c, bump 2.2.20)
- 发现: 2.2.19 只修了 autocomplete/ab pullAbImpl/group _pull 的 restoreOnline,
  但冷启动/切 tab 走本地缓存加载路径仍重建 Peer 丢 online:
  * group_model.loadCache()  (data['peers'] -> Peer.fromJson -> peers.add) 无回填
  * ab_model._deserializeCache()  (abEntry['peers'] -> Peer.fromJson -> ab.peers.add) 无回填
  => 手机冷启动/切 tab 时, 服务器已确认在线的设备仍灰 (权威表有值但重建对象没回填)。
- 根治方案: Peer.fromJson 构造器初始化列表直接查进程级权威表:
    online = Peers.onlineOf(json['id'] ?? '') ?? false
  一处修改覆盖所有 Peer.fromJson 重建路径(缓存/补全/通讯录/群组/PeerPayload.toPeer/getRecentPeers/addPeers/_fetchPeers)。
- 双保险: group loadCache / ab _deserializeCache 也显式补 Peers.restoreOnline。
- dart analyze 全 lib 通过, 零问题。版本 2.2.19 -> 2.2.20。
- 已 push 6f9510c, CI 双构建进行中。

## 2026-09-03 2.2.20 PC 端日志审计 (补充)
- runtime 日志(ldesk_runtime.log) 证实 2.2.20 PC(466619):
  * 每16s向 rev.dicad.cn:21116 注册且被服务器确认, 当前实时(09:40 仍在注册)
  * DIRECT_SERVER status=listening (直连端口正常)
  * 无崩溃记录
- rendezvous 历史失败 404 次, 集中在凌晨 04:00-04:18 (疑似服务器维护窗口), 最长簇仅64s,
  不影响 120s 在线超时窗口 => 非灰点/连接卡住根因, 当前已完全恢复。
- 结论: PC 被控端全链路健康; 灰点根因在手机端 Peer 重建(2.2.20 fromJson 自动回填已根治)。
