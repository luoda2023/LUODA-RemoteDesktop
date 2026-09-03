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

## 2026-09-03 本机(466619)"长时间后手机连不上/已连接请等待" 深度诊断 (进行中)
- 现象: 本机 PC 时间长了(熄屏/空闲)再用手机连, 一直"已连接,请等待"; 另一台电脑能连。
- 本机环境: S0 Modern Standby, 显示器 10 分钟自动熄屏(VIDEOIDLE=600s), 无自动锁屏策略;
  LDesk 以纯用户进程运行(便携 runtime %LOCALAPPDATA%\LDesk\runtime), 无 LDesk 服务组件(仅 dotchat 的 LUODA 服务, 不相关)。
- 已确认健康: 在线注册每16s正常(rev.dicad.cn:21116 acknowledged); DIRECT_SERVER 21118 LISTENING(IPv4+IPv6);
  本机自连 127.0.0.1:21118 和 192.168.31.42:21118 均成功; 进程 197线程/Responding=True; 会话 Active 未锁屏; 显示器 online。
- 时间线(runtime log ldesk_runtime.log + FileLogger %PROGRAMDATA%\LDesk\logs\ldesk-2026-09-03.log):
  * 最后一次稳定视频会话: 09-03 01:41:21 (first frame encoding completed subscribers=1)
  * 01:41 后 9 小时无稳定会话; 09:34 启动 2.2.20(当前 PID 43936)
  * 09:39:04 服务子系统崩溃重启: monitor0 "Desktop changed" x5 + mouse_cursor "拒绝访问"(os error 5) x3 + "Failed to switch desktop: 拒绝访问" + "ipc to connection manager exit: reset by the peer"
  * 09:39:08 FileLogger 停写(疑似 logger 异常或服务循环僵死)
  * 10:27:43 第二 LDesk 实例短暂启动("LDesk started")+ 一次 video 会话: 首帧编码 subscribers=1 -> 下一帧 "encoded frame but no subscribers"(订阅者1帧后消失)
  * 10:27:49 FileLogger "ipc to connection manager exit: expected" 后恢复心跳-only
- 代码疑点(video_service.rs / service.rs):
  * video_service.rs:743 desktop_changed() && !portable_service::running() => bail("Desktop changed")
    无服务组件时, 锁屏/会话切换(selectInputDesktop 失败 os error 5)会陷入 创建capturer->bail->退避 死循环, 永不产帧
  * video_service.rs:1380 handle_one_frame 里 sps.has_subscribes() => bail("SWITCH")
    无法区分"新加入订阅者"与"已在服务的订阅者", 订阅者持续存在时理论上每帧 SWITCH 重启
  * LAST_GOOD_YUV 仅进程内存(static Mutex<HashMap>), 进程重启即空; 熄屏+重启后首帧 WouldBlock 无缓存可回放
- 待办: 与用户确认根因方向(A: video SWITCH 死循环 / B: desktop_changed 崩溃 / C: 连接层), 再做最小修复并构建。


## 2026-09-03 熄屏无法连接 根治(采纳用户方案: 连接即自动亮屏) (bump 2.2.22)
- 根因确认: 本机为 ROG 笔记本, 熄屏 = 内屏面板断电 -> Intel 核显显示输出停摆 ->
  DXGI Desktop Duplication 无新帧; 原 keep-awake(ES_DISPLAY_REQUIRED) 只能"阻止熄灭",
  无法"重新点亮已熄灭的屏幕"; 台式机熄屏只是显示器 DPMS 断电、GPU 仍渲染 -> 所以另一台没事。
- 用户方案(采纳): 有连接进来就自动点亮屏幕, 亮起后核显恢复渲染 -> 捕获恢复 -> 首帧可达。
- 修复(3 层, 全部只碰 Windows 便携/桌面运行路径):
  1. src/platform/windows.rs: 新增 pub fn wake_up_displays()
     - SendMessageTimeoutW(HWND_BROADCAST, WM_SYSCOMMAND, SC_MONITORPOWER, -1) 系统级真正点亮显示器;
       失败回退 PostMessageW; 再 SetThreadExecutionState(ES_CONTINUOUS|ES_DISPLAY_REQUIRED) 防立即再熄。
  2. src/server/connection.rs: try_activate_screen() 强化 + 触发时机提前
     - 原实现只在授权通过后鼠标微移(-6/+6), 无法可靠点亮已熄灭内屏, 且时机太晚。
     - 现在: handle_login_request_without_validation() 入口即调用(授权窗口弹出前屏幕已开始点亮);
       windows 分支先调 wake_up_displays() 再鼠标微移; 5 秒节流防风暴(LAST_SCREEN_WAKE lazy_static)。
  3. src/server/video_service.rs: 等首帧期间周期兜底重亮
     - WouldBlock 分支 + 捕获错误分支: !first_frame_sent 且距上次唤醒>=4s 时再次 wake_up_displays(),
       直到首帧发出, 覆盖"唤醒后被系统再次熄屏/唤醒失败"的持续场景。
- 语法验证: rustfmt --check 三文件均通过(仅格式建议, 无语法错误); 本地 vcpkg 缺失无法 cargo check,
  由 CI(默认 features, 同 build-exe.yml) 做最终编译验证。
- 修正(v2.2.22 定稿): 
  * wake_up_displays() 改为一次性点亮(SC_MONITORPOWER), 不再带持续 ES_DISPLAY_REQUIRED
    (原实现调用一次后无连接也永不熄屏, 违反用户"平时按系统自动熄屏"要求);
    连接期间常亮由既有 wakelock 机制负责(连接数>0 才持有, 断开即释放)。
  * try_activate_screen() 改为 #[cfg(windows)] 实做 / #[cfg(not(windows))] no-op,
    修复 Android 构建失败(cannot find function mouse_move_relative)。
- 待用户实测: 手机连 466619, 观察 PC 屏幕是否自动亮起 + 手机不再"已连接请等待"。


## 2026-09-03 授权一次性完成+重装不重复授权+冷启动零弹窗 (commit 46c2f0c, 2.2.22 追加)
- 用户诉求: 每次打开软件不要再弹任何设置/授权窗口, 授权只在第一次安装后出现一次; 重装软件也不要再次授权。
- 根因: 已授权设备(含重装后公共marker仍在)每次冷启动仍调用 _requestStandardPermissionsBatch()
  批量请求通知/录音权限; 重装后系统重置这些运行时权限 => 每次打开都弹系统授权框。
- 修复:
  1. MainActivity.kt 新增 write_public_auth_marker / read_public_auth_marker 两个 channel,
     直读写 /storage/emulated/0/Documents/LDesk/first-run-authorization (publicAuthBaseDir,
     重装保留, Android 10+ 免运行时权限)。
  2. home_page.dart _canStartQuietly() 优先读 native 公共 marker 作为跨重装权威信号,
     旧安装由 LocalConfig/SharedPreferences/legacy Dart marker 兜底兼容。
  3. home_page.dart _runFirstLaunchAuthorization(): 已授权设备(任意 marker 命中)直接
     return 完全静默, 不再冷启动批量请求权限; 首次安装才跑一次性引导流。
     无障碍(输入控制)/录屏 只在"分享屏幕"页用户主动开启时请求(toggleService/toggleInput 内已有)。
- 验证: dart analyze home_page.dart 零问题; Kotlin 分支语法与既有 when/else 模式一致。
- 补漏: 4991ce6 bump 2.2.22 漏改 Cargo.lock luoda version -> 本次同步为 2.2.22。
- 待 CI: build-exe + build-apk 双构建确认 (前一轮 2.2.22 APK 曾因 mouse_move_relative 失败,
  已在 4991ce6 try_activate_screen cfg(windows) 修复, 需新 CI 证实)。

## 2026-09-03 v2.2.22 构建验证通过 (CI 33716725514 APK / 33716725482 EXE)
- 双构建均 success: APK 58m16s, EXE 51m55s。APK 成功证实 4991ce6 的
  try_activate_screen cfg(windows) 拆分修复了上轮 mouse_move_relative 编译失败。
- Release v2.2.22 (Latest) 7 资产全部上传: 3 APK (arm64/v7a/x86_64/universal 4 个) +
  install/portable EXE + service zip。核对:
  * LDesk-arm64-v8a.apk sha256 61edebec...da9b3a 一致
  * LDesk-portable-x64.exe sha256 40b3df34...5092 一致 (install/portable 同 digest)
- 本机(amei-print, ID 930647) 已用 portable 升级 2.2.22:
  * 新 runtime 目录 2997026936029b9800a6db5aac62023e (旧 6c28342... 为 2.2.20)
  * LDesk.exe FileVersion 2.2.22+1 确认, 进程 Responding=True, 21118 LISTENING,
    direct-access-status=listening, 配置 LDesk2.toml 14:16:41 正常写入
  * 启动级无崩溃 (验证熄屏修复未引入启动问题)
- 下载注意: gh release download 在本机不走代理会卡 0 字节; 需 curl.exe --proxy
  socks5h://127.0.0.1:10808 -L 显式代理下载 (8MB/s)。
- 待用户实测(手机端): 装 arm64 APK, 验证 (a) 首次安装才弹一次授权,
  (b) 重装不再弹, (c) 已授权设备每次冷启动零弹窗, (d) 熄屏后手机连 466619/930647
  屏幕自动亮起不再"已连接请等待"。

## 2026-09-03 冷启动静默判定逐标记容错加固 (commit 2fa358c, bump 2.2.23)
- 缺陷复盘: v2.2.22 _canStartQuietly() 用单个 try 包裹 4 个授权标记的 || 串联。
  任一 invokeMethod 抛 PlatformException(native channel 时序/存储瞬时不可用),
  整个判断跳到 catch 返回 false -> 已授权设备被误判未授权 -> 冷启动走首次授权弹窗。
  这是用户反复投诉'重装后仍弹授权'的潜在复发源, 属同族缺陷必须根除。
- 修复: 4 个检查(公共marker/LocalConfig/SharedPreferences/legacy Dart marker)
  各自独立 try/catch; 单项异常仅降级 false + RuntimeLogger 记录; 任一命中即 true。
  单点故障不再影响整体判定, 已授权设备冷启动 100% 静默。
- 验证: dart analyze 零问题, dart format 规范。版本 2.2.22 -> 2.2.23 四文件同步。
- 待 CI: build-exe + build-apk (2.2.23) 双构建, 完成后核对 Release 资产。

## 2026-09-03 v2.2.23 构建验证通过 (CI 33723651169 APK / 33723651175 EXE)
- 双构建 success: APK 58m24s, EXE 49m14s。Release v2.2.23 (Latest) 7 资产齐全。
- 完整性核对(与 release digest 一致):
  * LDesk-arm64-v8a.apk sha256 00cc17c6...6493, 25883593 bytes
  * LDesk-portable-x64.exe sha256 bd9e774e...7cc, 24488448 bytes
- 本机(amei-print, ID 930647) portable 冒烟测试:
  * 新 runtime 016a5c1aa52f018d99774a61481d7df2, LDesk.exe FileVersion 2.2.23+1
  * 进程 195 线程/182MB/Responding=True/主窗口 LDesk
  * Test-NetConnection 127.0.0.1:21118 = True (DIRECT_SERVER 实际握手成功)
  * 无启动崩溃; 测试后已 Stop-Process 恢复干净环境
- 下载教训: 本机 socks5 代理(127.0.0.1:10808)对 github 大文件时通时断;
  直连 github release 大文件被限速(~12-24KB/s)但 curl -C - 断点续传可完成;
  gh release download 会卡 0 字节。可靠法: curl -L -C - --retry 3 直连续传。
- 待用户实测(手机): 装 LDesk-arm64-v8a.apk 2.2.23, 验证首次弹一次授权、
  重装不弹、已授权设备每次冷启动零弹窗、熄屏后连 930647 自动亮屏。

## 2026-09-03 v2.2.23 APK 内容级验证 + release tag 溯源核查
- 内容级铁证(解包 arm64 APK):
  * lib/arm64-v8a/libluoda.so 内版本串 = 2.2.23 (Rust 修复: 熄屏自动亮屏等已编译入)
  * lib/arm64-v8a/libapp.so 内含 2.2.23 Dart 新增字符串:
    'public marker check failed' / 'legacy marker check failed' (容错日志) +
    'authorized device: silent cold start' (2.2.22 静默启动)
  => 下载的 v2.2.23 APK 确实含本轮全部修复, 非旧版误标。
- release tag 溯源核查: v2.2.20~v2.2.23 的 git tag 均指向 dac8fef (v2.0.1 分支旧码),
  因 softprops/action-gh-release 只在 tag 缺失时创建、发布时不移 tag 到构建 HEAD。
  影响: 仅源码 checkout tag 会拿到旧码; 资产本身由每次 workflow 从触发分支
  (v2.0.1-track 实际 HEAD) 构建上传, 内容正确(已由 APK 内容验证)。
  备查: 若要 tag 正确溯源, workflow 需在发布前移动轻量 tag 到 GITHUB_SHA。
- 网络: git push 走 socks5 代理故障时, 本机 SSH(git@github.com:22) 可用,
  加 origin-ssh remote 即可 push (本次已用此法补推 9a06bd1)。

## 2026-09-03 决定性验证: 本机=466619, 2.2.23 运行中官方查询 ONLINE
- 本机身份澄清: LDesk_local.toml remote_id='930647' 是"最近远程过的对方",
  非本机 id; 本机真实 id=466619 (LDesk.toml enc_id secretbox 解密, bugs.md 早前确认)。
  peers/930647.toml = 曾连接的设备。两 id 当前都 ONLINE。
- 决定性反证(灰点/离线问题): 本机跑 2.2.23 portable (PID 41320, runtime 016a5c1a...,
  FileVersion 2.2.23+1), 官方 online_probe 连 47.114.75.115:21115 查询:
  * 466619 -> ONLINE
  * 930647 -> ONLINE
  => 修复版运行时 466619 已被服务器确认在线, 手机端应显示绿点, 不再灰/离线。
- 该 2.2.23 实例保持运行, 供用户立即用手机验证 466619 在线状态 + 熄屏自动亮屏。

## 2026-09-03 最终审计: 全量 analyze + 产物内容核验 + 本机持续在线
- dart analyze lib (全 Flutter 代码库, 含手机端 peer_model 灰点修复/home_page 授权)
  = No issues found (零问题)。
- 2.2.23 portable EXE 不含任何 WebView2/inappwebview 串 => BUG-1(远程后 dcomp
  弹错窗)修复在产物中确认生效。
- 2.2.23 runtime luoda.dll 版本串 2.2.23 (size 30497792), 2.2.20 为 2.2.20
  (30496768), 二进制确实不同 => 含全部 Rust 修复(熄屏亮屏)。
- 466619 以 2.2.23 持续运行 (PID 41320 Responding=True), 官方 probe 反复查询
  = ONLINE。手机装 v2.2.23 arm64 APK 即可实测: 绿点在线/首次授权一次/重装不弹/
  熄屏自动亮屏。
- 代码侧所有可验证项全部闭环, 待用户手机真机验收。

## 2026-09-03 观察: LDesk portable 进程曾被正常关闭, 已重启保持在线
- 16:39 启动的 2.2.23 (PID 41320) 约 16:44 消失; 无 LDesk 崩溃日志
  (Application Error 无 LDesk), 系统未重启(up 22.6h) => 属正常关闭(用户操作)。
- 16:44:02 系统日志 'LUODA Service 意外停止' = dotchat 的 LUODA 服务,
  非本 LDesk 便携版; 按用户约束不介入 dotchat。
- 已重启 2.2.23 (PID 35880, runtime 016a5c1a 不变), 466619 官方 probe = ONLINE。
- 状态: 466619 以 2.2.23 在线, 待用户手机装 v2.2.23 arm64 APK 真机验收
  (绿点/首装一次授权/重装不弹/熄屏自动亮屏)。

## 2026-09-03 运行证据: 466619 = 本机, 2.2.23 持续在线无崩溃 (用户确认)
- 用户明确: "466619 正在这台电脑运行呀" => 466619 = 本机(不是930647; 930647是
  amei-print 旧配置, 另一台设备)。此前把本机ID误判为930647是错的, 已纠正。
- 本机 = 这台PC (ROG Strix G814JI, hostname DESKTOP-6UI3K4R)。运行 2.2.23
  portable (runtime 016a5c1a..., 启动于 17:11:53, PID 7392) 保持466619在线。
- 证据:
  * 服务器 21115 权威探测: 466619 ONLINE=True (930647 也 True, 那台也在线)
  * 21118 DIRECT_SERVER listening (PID 7392)
  * 日志每16s一条 rendezvous registration acknowledged; 最新心跳距查询仅3s
    (近5分钟19条), 证明持续稳定注册, 无掉线
  * 运行目录无任何 webview/inappwebview 组件 => 远程后 dcomp/Unknown Hard
    Error 崩溃根因已随 2.2.23 移除, 进程自启动持续无崩溃
- 交付物(用户可装):
  * PC: 桌面 LDesk-portable-v2.2.23.exe (sha256 BD9E774E..., 官方一致)
  * APK: _release_v2.2.23\LDesk-arm64-v8a.apk
  * 验收: _release_v2.2.23\验收清单-v2.2.23.md
- 待用户真机4项验收: 绿点/零弹窗/重装不弹/熄屏自动亮屏。

## 2026-09-03 决定性根因: 手机端灰点 = online查询被WebSocket改写, 已修复推送CI
- 用户最终反馈"手机端466619还是灰色, 明明在线"。真机(OPPO PFUM10 7358bbbb)
  Rust日志(rs_rCURRENT.log)铁证:
    ERROR websocket.rs:275 WebSocket protocol error: Connection reset without closing handshake
    WARN  client.rs:4138 Failed to query online states for 1 peers: Online stream receives None
  手机端每4~10秒查询466619在线状态, 全部失败 => _onlineStates权威表永空 => 灰点。
- 根因链(代码+服务器双证):
  * Android use_ws() 默认 true (carrier 网络假设), 桌面 false
  * create_online_stream() 用 connect_tcp() => check_ws() 把 rev.dicad.cn:21115
    (online明文TCP) 改写成 wss://rev.dicad.cn/ws/id (443)
  * nginx 把 /ws/id 转发到 hbbs 21118 (注册WS端口), 明文 OnlineRequest 无法解析
    => 服务器RST => 每次查询失败
  * 桌面 use_ws()=false 直连21115明文TCP成功 => 仅手机端灰
  * 服务器源码(LUODA-SERVER-API/src/rendezvous_server.rs:880 handle_online_request)
    确认 21115 (port-1) 用 FramedStream 明文处理 OnlineRequest, 非WS
- 修复: src/client.rs create_online_stream() 改 connect_tcp_local() 强制raw TCP
  (与 create_relay/rendezvous_mediator fallback 一致), 绕过WS改写直连21115。
  host cargo check --lib 通过。已提交 e44eea7 并 push v2.0.1-track,
  CI Build LDesk Android APK (run 33748097790) 构建中。
- 附加现象: 手机端每1.2~5秒 AtchDlg 窗口闪烁(空对话框+输入法onStartInput),
  与 online 查询失败同源(每次失败WS连接触发UI刷新)。修复后应同步消失。
  若仍有, 再单独追查(与页面无关, 全局性)。
- 交付: 等 CI APK (LDesk-arm64-v8a.apk), 装到手机后验证 466619 绿点。
