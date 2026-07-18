// main window right pane

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:luoda_flutter/common/widgets/connection_page_title.dart';
import 'package:luoda_flutter/consts.dart';
import 'package:luoda_flutter/desktop/widgets/popup_menu.dart';
import 'package:luoda_flutter/models/state_model.dart';
import 'package:luoda_flutter/runtime_logger.dart';
import 'package:get/get.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:window_manager/window_manager.dart';
import 'package:luoda_flutter/models/peer_model.dart';

import '../../common.dart';
import '../../common/formatter/id_formatter.dart';
import '../../common/widgets/peer_tab_page.dart';
import '../../common/widgets/autocomplete.dart';
import '../../models/platform_model.dart';
import '../../desktop/widgets/material_mod_popup_menu.dart' as mod_menu;

class OnlineStatusWidget extends StatefulWidget {
  const OnlineStatusWidget({Key? key, this.onSvcStatusChanged})
      : super(key: key);

  final VoidCallback? onSvcStatusChanged;

  @override
  State<OnlineStatusWidget> createState() => _OnlineStatusWidgetState();
}

/// State for the connection page.
class _OnlineStatusWidgetState extends State<OnlineStatusWidget> {
  final _svcStopped = Get.isRegistered<RxBool>(tag: 'stop-service')
      ? Get.find<RxBool>(tag: 'stop-service')
      : Get.put<RxBool>(false.obs, tag: 'stop-service');
  Timer? _updateTimer;
  bool _statusReadFailed = false;

  double get em => 14.0;
  double get emForStatus =>
      (isCustomClientFresh() || bind.isIncomingOnly()) ? 11.5 : em;
  double? get height => bind.isIncomingOnly() ? null : em * 3;

  void onUsePublicServerGuide() {
    const url = "https://dicad.cn/pricing";
    canLaunchUrlString(url).then((can) {
      if (can) {
        launchUrlString(url);
      }
    });
  }

  @override
  void initState() {
    super.initState();
    if (!_svcStopped.value) {
      stateGlobal.svcStatus.value = SvcStatus.connecting;
    }
    _updateTimer = periodic_immediate(Duration(seconds: 1), () async {
      await updateStatus();
    });
  }

  @override
  void dispose() {
    _updateTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isIncomingOnly = bind.isIncomingOnly();

    startServiceWidget() => Offstage(
          offstage: !_svcStopped.value,
          child: InkWell(
                  onTap: () async {
                    await start_service(true);
                  },
                  child: Text(translate("Start service"),
                      style: TextStyle(
                          decoration: TextDecoration.underline, fontSize: em)))
              .marginOnly(left: em),
        );

    basicWidget(SvcStatus status) {
      final isReady = !_svcStopped.value && status == SvcStatus.ready;
      final statusColor = _svcStopped.value || status == SvcStatus.notReady
          ? Colors.grey
          : isReady
              ? const Color.fromARGB(255, 50, 190, 166)
              : Colors.orange;
      return Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            height: 10,
            width: 10,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(5),
              color: statusColor,
            ),
          ).marginSymmetric(horizontal: em),
          Flexible(
            child: SizedBox(
              width: isIncomingOnly ? 226 : null,
              child: isReady
                  ? _ServerAddressWidget(em: emForStatus, suffix: '已连接')
                  : _buildConnStatusMsg(status),
            ),
          ),
          if (!isIncomingOnly) startServiceWidget(),
        ],
      );
    }

    return Container(
      height: height,
      child: Obx(() {
        final status = stateGlobal.svcStatus.value;
        return isIncomingOnly
            ? Column(
                children: [
                  basicWidget(status),
                  Align(
                          child: startServiceWidget(),
                          alignment: Alignment.centerLeft)
                      .marginOnly(top: 2.0, left: 22.0),
                ],
              )
            : basicWidget(status);
      }),
    ).paddingOnly(right: isIncomingOnly ? 8 : 0);
  }

  _buildConnStatusMsg(SvcStatus status) {
    return Text(
      _svcStopped.value
          ? translate("Service is not running")
          : status == SvcStatus.connecting
              ? translate("connecting_status")
              : translate("not_ready_status"),
      style: TextStyle(fontSize: emForStatus),
    );
  }

  updateStatus() async {
    try {
      final status =
          jsonDecode(await bind.mainGetConnectStatus()) as Map<String, dynamic>;
      final statusNum = status['status_num'] as int;
      final nextStatus = statusNum > 0 ? SvcStatus.ready : SvcStatus.connecting;
      final previousStatus = stateGlobal.svcStatus.value;
      if (previousStatus != nextStatus) {
        stateGlobal.svcStatus.value = nextStatus;
        final configuredServer =
            bind.mainGetOptionSync(key: 'custom-rendezvous-server').trim();
        final server =
            configuredServer.isEmpty ? 'rev.dicad.cn' : configuredServer;
        RuntimeLogger.instance.info(
          'NETWORK',
          'service ${previousStatus.name} -> ${nextStatus.name}; server=$server',
        );
        widget.onSvcStatusChanged?.call();
      }
      stateGlobal.videoConnCount.value = status['video_conn_count'] as int;
      if (_statusReadFailed) {
        RuntimeLogger.instance.info('NETWORK', 'connect status reader recovered');
        _statusReadFailed = false;
      }
    } catch (error) {
      // Preserve the last verified state on a transient IPC/JSON failure.
      if (!_statusReadFailed) {
        RuntimeLogger.instance.warn(
          'NETWORK',
          'connect status read failed: $error',
        );
        _statusReadFailed = true;
      }
    }
  }
}

/// Connection page for connecting to a remote peer.
class ConnectionPage extends StatefulWidget {
  const ConnectionPage({Key? key}) : super(key: key);

  @override
  State<ConnectionPage> createState() => _ConnectionPageState();
}

/// State for the connection page.
class _ConnectionPageState extends State<ConnectionPage>
    with SingleTickerProviderStateMixin, WindowListener {
  /// Controller for the id input bar.
  final _idController = IDTextEditingController();

  final RxBool _idInputFocused = false.obs;
  final FocusNode _idFocusNode = FocusNode();
  final TextEditingController _idEditingController = TextEditingController();

  String selectedConnectionType = 'Connect';

  bool isWindowMinimized = false;

  final AllPeersLoader _allPeersLoader = AllPeersLoader();

  // https://github.com/flutter/flutter/issues/157244
  Iterable<Peer> _autocompleteOpts = [];

  final _menuOpen = false.obs;

  @override
  void initState() {
    super.initState();
    _allPeersLoader.init(setState);
    _idFocusNode.addListener(onFocusChanged);
    if (_idController.text.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final lastRemoteId = await bind.mainGetLastRemoteId();
        if (lastRemoteId != _idController.id) {
          setState(() {
            _idController.id = lastRemoteId;
          });
        }
      });
    }
    Get.put<TextEditingController>(_idEditingController);
    Get.put<IDTextEditingController>(_idController);

    windowManager.addListener(this);
  }

  @override
  void dispose() {
    _idController.dispose();
    windowManager.removeListener(this);
    _allPeersLoader.clear();
    _idFocusNode.removeListener(onFocusChanged);
    _idFocusNode.dispose();
    _idEditingController.dispose();
    if (Get.isRegistered<IDTextEditingController>()) {
      Get.delete<IDTextEditingController>();
    }
    if (Get.isRegistered<TextEditingController>()) {
      Get.delete<TextEditingController>();
    }
    super.dispose();
  }

  @override
  void onWindowEvent(String eventName) {
    super.onWindowEvent(eventName);
    if (eventName == 'minimize') {
      isWindowMinimized = true;
    } else if (eventName == 'maximize' || eventName == 'restore') {
      if (isWindowMinimized && isWindows) {
        // windows can't update when minimized.
        Get.forceAppUpdate();
      }
      isWindowMinimized = false;
    }
  }

  @override
  void onWindowEnterFullScreen() {
    // Remove edge border by setting the value to zero.
    stateGlobal.resizeEdgeSize.value = 0;
  }

  @override
  void onWindowLeaveFullScreen() {
    // Restore edge border to default edge size.
    stateGlobal.resizeEdgeSize.value = stateGlobal.isMaximized.isTrue
        ? kMaximizeEdgeSize
        : windowResizeEdgeSize;
  }

  @override
  void onWindowClose() {
    super.onWindowClose();
    bind.mainOnMainWindowClose();
  }

  void onFocusChanged() {
    _idInputFocused.value = _idFocusNode.hasFocus;
    if (_idFocusNode.hasFocus) {
      if (_allPeersLoader.needLoad) {
        _allPeersLoader.getAllPeers();
      }

      final textLength = _idEditingController.value.text.length;
      // Select all to facilitate removing text, just following the behavior of address input of chrome.
      _idEditingController.selection =
          TextSelection(baseOffset: 0, extentOffset: textLength);
    }
  }

  @override
 Widget build(BuildContext context) {
 final isOutgoingOnly = bind.isOutgoingOnly();
 return Column(
 crossAxisAlignment: CrossAxisAlignment.stretch,
 children: [
 Expanded(
 child: Column(
 crossAxisAlignment: CrossAxisAlignment.stretch,
 children: [
 _buildRemoteIDTextField(context).marginOnly(top: 22),
 SizedBox(height: 12),
 Expanded(child: PeerTabPage()),
 ],
 ).paddingOnly(left: 12.0)),
 // 普通版右下角状态条 (用户反馈 round-23):
 // v2.0.1 base 干净上 普通版只在 left pane 有 OnlineStatusWidget
 // 当 isIncomingOnly=false 时, left pane 不渲染 OnlineStatusWidget,
 // 因此普通版无任何状态条显示. 这里主动在 right pane 底部 加 一 行.
 // 客户定制 版 (isIncomingOnly=true) 仍 走 desktop_home_page.dart 的 left pane
 // OnlineStatusWidget 渲染逻辑, 这里 块 仅 在 正常 输 入 模 式时大 出可见
 if (!isOutgoingOnly && !bind.isIncomingOnly())
 OnlineStatusWidget(
 onSvcStatusChanged: () {},
 ).paddingOnly(left: 12.0, right: 8.0, bottom: 6.0, top: 2.0),
 ],
 );
 }

  /// Callback for the connect button.
  /// Connects to the selected peer.
  void onConnect(
      {bool isFileTransfer = false,
      bool isViewCamera = false,
      bool isTerminal = false}) {
    var id = _idController.id;
    connect(context, id,
        isFileTransfer: isFileTransfer,
        isViewCamera: isViewCamera,
        isTerminal: isTerminal);
  }

  /// UI for the remote ID TextField.
  /// Search for a peer.
  Widget _buildRemoteIDTextField(BuildContext context) {
    var w = Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 22),
      decoration: BoxDecoration(
          borderRadius: const BorderRadius.all(Radius.circular(13)),
          // 之前用 colorScheme.background 作为 border，对比度下显示成"灰色细线"，
          // 普通版输入框与下方 TAB 栏之间不需要这条分隔线，去掉。
          border: Border.all(color: Colors.transparent)),
      child: Ink(
        child: Column(
          children: [
            getConnectionPageTitle(context, false).marginOnly(bottom: 15),
            Row(
              children: [
                Expanded(
                    child: RawAutocomplete<Peer>(
                  optionsBuilder: (TextEditingValue textEditingValue) {
                    if (textEditingValue.text == '') {
                      _autocompleteOpts = const Iterable<Peer>.empty();
                    } else if (_allPeersLoader.peers.isEmpty &&
                        !_allPeersLoader.isPeersLoaded) {
                      Peer emptyPeer = Peer(
                        id: '',
                        username: '',
                        hostname: '',
                        alias: '',
                        platform: '',
                        tags: [],
                        hash: '',
                        password: '',
                        forceAlwaysRelay: false,
                        rdpPort: '',
                        rdpUsername: '',
                        loginName: '',
                        device_group_name: '',
                        note: '',
                      );
                      _autocompleteOpts = [emptyPeer];
                    } else {
                      String textWithoutSpaces =
                          textEditingValue.text.replaceAll(" ", "");
                      if (int.tryParse(textWithoutSpaces) != null) {
                        textEditingValue = TextEditingValue(
                          text: textWithoutSpaces,
                          selection: textEditingValue.selection,
                        );
                      }
                      String textToFind = textEditingValue.text.toLowerCase();
                      _autocompleteOpts = _allPeersLoader.peers
                          .where((peer) =>
                              peer.id.toLowerCase().contains(textToFind) ||
                              peer.username
                                  .toLowerCase()
                                  .contains(textToFind) ||
                              peer.hostname
                                  .toLowerCase()
                                  .contains(textToFind) ||
                              peer.alias.toLowerCase().contains(textToFind))
                          .toList();
                    }
                    return _autocompleteOpts;
                  },
                  focusNode: _idFocusNode,
                  textEditingController: _idEditingController,
                  fieldViewBuilder: (
                    BuildContext context,
                    TextEditingController fieldTextEditingController,
                    FocusNode fieldFocusNode,
                    VoidCallback onFieldSubmitted,
                  ) {
                    updateTextAndPreserveSelection(
                        fieldTextEditingController, _idController.text);
                    return Obx(() => TextField(
                          autocorrect: false,
                          enableSuggestions: false,
                          keyboardType: TextInputType.visiblePassword,
                          focusNode: fieldFocusNode,
                          style: const TextStyle(
                            fontFamily: 'WorkSans',
                            fontSize: 22,
                            height: 1.4,
                          ),
                          maxLines: 1,
                          cursorColor:
                              Theme.of(context).textTheme.titleLarge?.color,
                          decoration: InputDecoration(
                              filled: false,
                              counterText: '',
                              hintText: _idInputFocused.value
                                  ? null
                                  : translate('Enter Remote ID'),
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 15, vertical: 13)),
                          controller: fieldTextEditingController,
                          inputFormatters: [IDTextInputFormatter()],
                          onChanged: (v) {
                            _idController.id = v;
                          },
                          onSubmitted: (_) {
                            onConnect();
                          },
                        ).workaroundFreezeLinuxMint());
                  },
                  onSelected: (option) {
                    setState(() {
                      _idController.id = option.id;
                      FocusScope.of(context).unfocus();
                    });
                  },
                  optionsViewBuilder: (BuildContext context,
                      AutocompleteOnSelected<Peer> onSelected,
                      Iterable<Peer> options) {
                    options = _autocompleteOpts;
                    double maxHeight = options.length * 50;
                    if (options.length == 1) {
                      maxHeight = 52;
                    } else if (options.length == 3) {
                      maxHeight = 146;
                    } else if (options.length == 4) {
                      maxHeight = 193;
                    }
                    maxHeight = maxHeight.clamp(0, 200);

                    return Align(
                      alignment: Alignment.topLeft,
                      child: Container(
                          decoration: BoxDecoration(
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.3),
                                blurRadius: 5,
                                spreadRadius: 1,
                              ),
                            ],
                          ),
                          child: ClipRRect(
                              borderRadius: BorderRadius.circular(5),
                              child: Material(
                                elevation: 4,
                                child: ConstrainedBox(
                                  constraints: BoxConstraints(
                                    maxHeight: maxHeight,
                                    maxWidth: 319,
                                  ),
                                  child: _allPeersLoader.peers.isEmpty &&
                                          !_allPeersLoader.isPeersLoaded
                                      ? Container(
                                          height: 80,
                                          child: Center(
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          ))
                                      : Padding(
                                          padding:
                                              const EdgeInsets.only(top: 5),
                                          child: ListView(
                                            children: options
                                                .map((peer) =>
                                                    AutocompletePeerTile(
                                                        onSelect: () =>
                                                            onSelected(peer),
                                                        peer: peer))
                                                .toList(),
                                          ),
                                        ),
                                ),
                              ))),
                    );
                  },
                )),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(top: 13.0),
              child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                // 方形连接按钮: 只显示图标,不显示"Connect"文字,
                // 连接图标用"登入箭头"(Icons.login),与登录对话框的钥匙图标(Icons.vpn_key)区分。
                SizedBox(
                  height: 40.0,
                  width: 40.0,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      padding: EdgeInsets.zero,
                      shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.all(Radius.circular(8)),
                      ),
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () {
                      onConnect();
                    },
                    child: Tooltip(
                      message: translate("Connect"),
                      child: const Icon(Icons.login,
                          size: 22, color: Colors.white),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  height: 28.0,
                  width: 28.0,
                  decoration: BoxDecoration(
                    border: Border.all(color: Theme.of(context).dividerColor),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: StatefulBuilder(
                      builder: (context, setState) {
                        var offset = Offset(0, 0);
                        return Obx(() => InkWell(
                              child: _menuOpen.value
                                  ? Transform.rotate(
                                      angle: pi,
                                      child: Icon(IconFont.more, size: 14),
                                    )
                                  : Icon(IconFont.more, size: 14),
                              onTapDown: (e) {
                                offset = e.globalPosition;
                              },
                              onTap: () async {
                                _menuOpen.value = true;
                                final x = offset.dx;
                                final y = offset.dy;
                                await mod_menu
                                    .showMenu(
                                  context: context,
                                  position: RelativeRect.fromLTRB(x, y, x, y),
                                  items: [
                                    (
                                      'Transfer file',
                                      () => onConnect(isFileTransfer: true)
                                    ),
                                    (
                                      'View camera',
                                      () => onConnect(isViewCamera: true)
                                    ),
                                    (
                                      '${translate('Terminal')} (beta)',
                                      () => onConnect(isTerminal: true)
                                    ),
                                  ]
                                      .map((e) => MenuEntryButton<String>(
                                            childBuilder: (TextStyle? style) =>
                                                Text(
                                              translate(e.$1),
                                              style: style,
                                            ),
                                            proc: () => e.$2(),
                                            padding: EdgeInsets.symmetric(
                                                horizontal:
                                                    kDesktopMenuPadding.left),
                                            dismissOnClicked: true,
                                          ))
                                      .map((e) => e.build(
                                          context,
                                          const MenuConfig(
                                              commonColor: CustomPopupMenuTheme
                                                  .commonColor,
                                              height:
                                                  CustomPopupMenuTheme.height,
                                              dividerHeight:
                                                  CustomPopupMenuTheme
                                                      .dividerHeight)))
                                      .expand((i) => i)
                                      .toList(),
                                  elevation: 8,
                                )
                                    .then((_) {
                                  _menuOpen.value = false;
                                });
                              },
                            ));
                      },
                    ),
                  ),
                ),
              ]),
            ),
          ],
        ),
      ),
    );
    return Container(
        constraints: const BoxConstraints(maxWidth: 600), child: w);
  }
}

class _ServerAddressWidget extends StatefulWidget {
  final double em;
  final String? suffix;

  const _ServerAddressWidget({required this.em, this.suffix});

  @override
  State<_ServerAddressWidget> createState() => _ServerAddressWidgetState();
}

class _ServerAddressWidgetState extends State<_ServerAddressWidget> {
  String _server = 'rev.dicad.cn';

  @override
  void initState() {
    super.initState();
    _loadServer();
  }

  void _loadServer() {
    final custom =
        bind.mainGetOptionSync(key: 'custom-rendezvous-server').trim();
    if (custom.isNotEmpty) {
      _server = custom;
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final suffix = (widget.suffix ?? '').trim();
    final text = suffix.isNotEmpty ? '$_server $suffix' : _server;
    return Text(
      text,
      style: TextStyle(fontSize: widget.em),
      overflow: TextOverflow.ellipsis,
    );
  }
}
