import 'dart:async';
import 'dart:io';
import 'dart:convert';

import 'package:auto_size_text/auto_size_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:luoda_flutter/common.dart';
import 'package:luoda_flutter/common/widgets/animated_rotation_widget.dart';
import 'package:luoda_flutter/common/widgets/custom_password.dart';
import 'package:luoda_flutter/consts.dart';
import 'package:luoda_flutter/desktop/pages/connection_page.dart';
import 'package:luoda_flutter/desktop/pages/desktop_setting_page.dart';
import 'package:luoda_flutter/desktop/pages/desktop_tab_page.dart';
import 'package:luoda_flutter/desktop/widgets/update_progress.dart';
import 'package:luoda_flutter/models/platform_model.dart';
import 'package:luoda_flutter/models/server_model.dart';
import 'package:luoda_flutter/models/state_model.dart';
import 'package:luoda_flutter/plugin/ui_manager.dart';
import 'package:luoda_flutter/utils/multi_window_manager.dart';
import 'package:luoda_flutter/utils/platform_channel.dart';
import 'package:get/get.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:window_manager/window_manager.dart';
import 'package:window_size/window_size.dart' as window_size;
import '../widgets/button.dart';

class DesktopHomePage extends StatefulWidget {
  /// 如果为 true，只显示左侧内容（客户端专用版）
  final bool isClientOnly;
  const DesktopHomePage({Key? key, this.isClientOnly = false}) : super(key: key);

  @override
  State<DesktopHomePage> createState() => _DesktopHomePageState();
}

const borderColor = Color(0xFF2F65BA);

class _DesktopHomePageState extends State<DesktopHomePage>
    with AutomaticKeepAliveClientMixin, WidgetsBindingObserver {
  final _leftPaneScrollController = ScrollController();

  @override
  bool get wantKeepAlive => true;
  var systemError = '';
  StreamSubscription? _uniLinksSubscription;
  var svcStopped = false.obs;
  var watchIsCanScreenRecording = false;
  var watchIsProcessTrust = false;
  var watchIsInputMonitoring = false;
  var watchIsCanRecordAudio = false;
  Timer? _updateTimer;
  bool isCardClosed = false;
  String _lastIp = '';
  String _lastPort = '';

  final RxBool _settingsHover = false.obs;
  final RxBool _relayHover = false.obs;
  final RxBool _block = false.obs;

  final GlobalKey _childKey = GlobalKey();

  // ---- 客户端专用版：ID输入框 ----
  final TextEditingController _clientIdController = TextEditingController();
  final FocusNode _clientIdFocusNode = FocusNode();

  void _onClientConnect(String id, BuildContext buildCtx) {
    final trimmed = id.trim();
    if (trimmed.isEmpty) return;
    connect(buildCtx, trimmed);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final isIncomingOnly = bind.isIncomingOnly();
    // 客户端专用版：只显示左侧内容，不包含右侧输入框和历史列表
    if (widget.isClientOnly) {
      return _buildBlock(
          child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          buildLeftPane(context),
          if (!isIncomingOnly) const VerticalDivider(width: 1),
        ],
      ));
    }
    return _buildBlock(
        child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        buildLeftPane(context),
        if (!isIncomingOnly) const VerticalDivider(width: 1),
        if (!isIncomingOnly) Expanded(child: buildRightPane(context)),
      ],
    ));
  }

  Widget _buildBlock({required Widget child}) {
    return buildRemoteBlock(
        block: _block, mask: true, use: canBeBlocked, child: child);
  }

	  Widget buildLeftPane(BuildContext context) {
    if (widget.isClientOnly) {
      return ChangeNotifierProvider.value(
        value: gFFI.serverModel,
        child: SizedBox(
          width: 276.0,
          child: Column(
            children: [
              Expanded(
                child: Column(
                  key: _childKey,
                  children: [
                    // 圆形头像 + LUODA 远程协助标题
                    Align(
                      alignment: Alignment.center,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Container(
                            margin: const EdgeInsets.only(top: 20, bottom: 8),
                            width: 64,
                            height: 64,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white,
                              border: Border.all(color: MyTheme.accent, width: 2),
                              boxShadow: [
                                BoxShadow(
                                    color: Colors.black.withOpacity(0.1),
                                    blurRadius: 6,
                                    offset: Offset(0, 2))
                              ],
                            ),
                            child: ClipOval(
                              child: Image.asset(
                                "assets/avatar.png",
                                fit: BoxFit.cover,
                                errorBuilder: (ctx, error, stackTrace) => Icon(
                                    Icons.computer,
                                    size: 32,
                                    color: MyTheme.accent),
                              ),
                            ),
                          ),
                          Text(
                            "LUODA 远程协助",
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).textTheme.titleLarge?.color,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // 本机ID
                    buildIDBoard(context),
                    SizedBox(height: 4),
                    // 密码
                    buildPasswordBoard(context),
                    SizedBox(height: 4),
                    // IP:端口
                    buildDirectAccessBoard(context),
                    Spacer(flex: 3),
                    // 底部连接状态 —— 加大间距防止紧贴 IP 栏
                    SizedBox(
                      height: 60,
                      child: OnlineStatusWidget(
                        onSvcStatusChanged: () {
                          if (isInHomePage()) {
                            Future.delayed(const Duration(milliseconds: 300),
                                () {
                              _updateWindowSize();
                            });
                          }
                        },
                      ),
                    ).marginOnly(left: 6, right: 6, bottom: 18),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }
    final isIncomingOnly = bind.isIncomingOnly();
    final isOutgoingOnly = bind.isOutgoingOnly();
    final children = <Widget>[
      if (!isOutgoingOnly) buildPresetPasswordWarning(),
      if (bind.isCustomClient())
        Align(
          alignment: Alignment.center,
          child: loadPowered(context),
        ),
      // 圆形头像 + LUODA 远程协助
      Align(
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 20, bottom: 8),
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
                border: Border.all(color: MyTheme.accent, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 8,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: ClipOval(
                child: Image.asset(
                  'assets/avatar.png',
                  fit: BoxFit.cover,
                  errorBuilder: (ctx, error, stackTrace) => Icon(
                    Icons.computer,
                    size: 40,
                    color: MyTheme.accent,
                  ),
                ),
              ),
            ),
            Text(
              "LUODA 远程协助",
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).textTheme.titleLarge?.color,
              ),
            ),
            SizedBox(height: 10),
          ],
        ),
      ),
      if (!isOutgoingOnly) buildIDBoard(context),
      if (!isOutgoingOnly) buildPasswordBoard(context),
      if (!isOutgoingOnly) buildDirectAccessBoard(context),
      FutureBuilder<Widget>(
        future: Future.value(
            Obx(() => buildHelpCards(stateGlobal.updateUrl.value))),
        builder: (_, data) {
          if (data.hasData) {
            if (isIncomingOnly) {
              if (isInHomePage()) {
                Future.delayed(Duration(milliseconds: 300), () {
                  _updateWindowSize();
                });
              }
            }
            return data.data!;
          } else {
            return const Offstage();
          }
        },
      ),
      buildPluginEntry(),
    ];
    if (isIncomingOnly) {
      children.addAll([
        Divider(),
        OnlineStatusWidget(
          onSvcStatusChanged: () {
            if (isInHomePage()) {
              Future.delayed(Duration(milliseconds: 300), () {
                _updateWindowSize();
              });
            }
          },
        ).marginOnly(bottom: 6, right: 6)
      ]);
    }
    final textColor = Theme.of(context).textTheme.titleLarge?.color;
    
    return ChangeNotifierProvider.value(
      value: gFFI.serverModel,
      child: Container(
        width: isIncomingOnly ? 300.0 : 220.0,
        color: Theme.of(context).colorScheme.background,
        child: Stack(
          children: [
            Column(
              children: [
                SingleChildScrollView(
                  controller: _leftPaneScrollController,
                  child: Column(
                    key: _childKey,
                    children: children,
                  ),
                ),
                Expanded(child: Container())
              ],
            ),
            Positioned(
              bottom: 6,
              left: 10,
              right: 10,
              child: Row(
                children: [
                  // 设置按钮
                  Expanded(
                    child: Obx(
                      () => InkWell(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.settings_outlined,
                              color: _settingsHover.value
                                  ? textColor
                                  : Colors.grey.withOpacity(0.5),
                              size: 18,
                            ),
                            Text(
                              translate("Settings"),
                              style: TextStyle(
                                fontSize: 10,
                                color: _settingsHover.value
                                    ? textColor
                                    : Colors.grey.withOpacity(0.5),
                              ),
                            ),
                          ],
                        ),
                        onTap: () {
                          if (DesktopSettingPage.tabKeys.isNotEmpty) {
                            DesktopSettingPage.switch2page(
                                DesktopSettingPage.tabKeys[0]);
                          }
                        },
                        onHover: (value) =>
                            _settingsHover.value = value,
                      ),
                    ),
                  ),
                  // 中继服务器按钮
                  Expanded(
                    child: Obx(
                      () => InkWell(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.cloud_outlined,
                              color: _relayHover.value
                                  ? textColor
                                  : Colors.grey.withOpacity(0.5),
                              size: 18,
                            ),
                            Text(
                              translate("Network"),
                              style: TextStyle(
                                fontSize: 10,
                                color: _relayHover.value
                                    ? textColor
                                    : Colors.grey.withOpacity(0.5),
                              ),
                            ),
                          ],
                        ),
                        onTap: () {
                          DesktopSettingPage.switch2page(
                              SettingsTabKey.network);
                        },
                        onHover: (value) =>
                            _relayHover.value = value,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  buildRightPane(BuildContext context) {
    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: ConnectionPage(),
    );
  }

  /// 客户端专用版：远程ID输入框，回车直接连接
  Widget _buildClientIDField() {
    return Container(
      margin: const EdgeInsets.only(left: 14, right: 14, top: 16),
      child: TextFormField(
        controller: _clientIdController,
        focusNode: _clientIdFocusNode,
        autocorrect: false,
        enableSuggestions: false,
        keyboardType: TextInputType.visiblePassword,
        style: const TextStyle(fontSize: 13),
        decoration: InputDecoration(
          filled: true,
          fillColor: Theme.of(context)
              .colorScheme
              .background
              .withOpacity(0.5),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: BorderSide(
              color: Theme.of(context).dividerColor,
            ),
          ),
          hintText: translate('Enter Remote ID'),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        ),
        onFieldSubmitted: (value) {
          _onClientConnect(value, context);
        },
      ),
    );
  }

  buildIDBoard(BuildContext context) {
    final model = gFFI.serverModel;
    return Container(
      margin: const EdgeInsets.only(left: 20, right: 11),
      height: 62,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Container(
            width: 3,
            height: 30,
            decoration: BoxDecoration(
              color: MyTheme.accent,
              borderRadius: BorderRadius.circular(2),
            ),
          ).marginOnly(top: 8),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(left: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        translate("ID"),
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.color
                                ?.withOpacity(0.45)),
                      ).marginOnly(top: 8),
                    ],
                  ),
                  GestureDetector(
                    onDoubleTap: () {
                      Clipboard.setData(
                          ClipboardData(text: model.serverId.text));
                      showToast(translate("Copied"));
                    },
                    child: TextFormField(
                      controller: model.serverId,
                      readOnly: true,
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: Theme.of(context)
                            .colorScheme
                            .background
                            .withOpacity(0.5),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                        isDense: true,
                      ),
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'monospace',
                        letterSpacing: 1.0,
                      ),
                    ).workaroundFreezeLinuxMint(),
                  )
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget buildPopupMenu(BuildContext context) {
    final textColor = Theme.of(context).textTheme.titleLarge?.color;
    RxBool hover = false.obs;
    return InkWell(
      onTap: DesktopTabPage.onAddSetting,
      child: Tooltip(
        message: translate('Settings'),
        child: Obx(
          () => CircleAvatar(
            radius: 15,
            backgroundColor: hover.value
                ? Theme.of(context).scaffoldBackgroundColor
                : Theme.of(context).colorScheme.background,
            child: Icon(
              Icons.more_vert_outlined,
              size: 20,
              color: hover.value ? textColor : textColor?.withOpacity(0.5),
            ),
          ),
        ),
      ),
      onHover: (value) => hover.value = value,
    );
  }

  buildPasswordBoard(BuildContext context) {
    return ChangeNotifierProvider.value(
        value: gFFI.serverModel,
        child: Consumer<ServerModel>(
          builder: (context, model, child) {
            return buildPasswordBoard2(context, model);
          },
        ));
  }

  buildPasswordBoard2(BuildContext context, ServerModel model) {
    RxBool refreshHover = false.obs;
    RxBool editHover = false.obs;
    final textColor = Theme.of(context).textTheme.titleLarge?.color;
    final showOneTime = model.approveMode != 'click' &&
        model.verificationMethod != kUsePermanentPassword;
    return Container(
      margin: EdgeInsets.only(left: 20.0, right: 16, top: 13, bottom: 13),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Container(
            width: 3,
            height: 30,
            decoration: BoxDecoration(
              color: MyTheme.accent,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(left: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AutoSizeText(
                    translate("One-time Password"),
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: textColor?.withOpacity(0.45)),
                    maxLines: 1,
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onDoubleTap: () {
                            if (showOneTime) {
                              Clipboard.setData(
                                  ClipboardData(text: model.serverPasswd.text));
                              showToast(translate("Copied"));
                            }
                          },
                          child: TextFormField(
                            controller: model.serverPasswd,
                            readOnly: true,
                            decoration: InputDecoration(
                              filled: true,
                              fillColor: Theme.of(context)
                                  .colorScheme
                                  .background
                                  .withOpacity(0.5),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(6),
                                borderSide: BorderSide.none,
                              ),
                              contentPadding:
                                  EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                              isDense: true,
                            ),
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'monospace',
                              letterSpacing: 1.5,
                            ),
                          ).workaroundFreezeLinuxMint(),
                        ),
                      ),
                      if (showOneTime)
                        AnimatedRotationWidget(
                          onPressed: () => bind.mainUpdateTemporaryPassword(),
                          child: Tooltip(
                            message: translate('Refresh Password'),
                            child: Obx(() => RotatedBox(
                                quarterTurns: 2,
                                child: Icon(
                                  Icons.refresh,
                                  color: refreshHover.value
                                      ? textColor
                                      : Color(0xFFDDDDDD),
                                  size: 22,
                                ))),
                          ),
                          onHover: (value) => refreshHover.value = value,
                        ).marginOnly(right: 8, top: 4),
                      // 客户端版：不显示"修改密码"按钮
                      if (!bind.isDisableSettings() && !bind.isCustomClient())
                        InkWell(
                          child: Tooltip(
                            message: translate('Change Password'),
                            child: Obx(
                              () => Icon(
                                Icons.edit,
                                color: editHover.value
                                    ? textColor
                                    : Color(0xFFDDDDDD),
                                size: 22,
                              ).marginOnly(right: 8, top: 4),
                            ),
                          ),
                          onTap: () => DesktopSettingPage.switch2page(
                              SettingsTabKey.safety),
                          onHover: (value) => editHover.value = value,
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  buildDirectAccessBoard(BuildContext context) {
    final publicIP = bind.mainGetOptionSync(key: 'public-ip');
    final lanIP = bind.mainGetOptionSync(key: 'lan-ip');
    final directPort = bind.mainGetOptionSync(key: kOptionDirectAccessPort);
    // UPnP 状态：通过 option "upnp-status" 读取（在 rust 侧 direct_server 启动后设置）
    final upnpStatus = bind.mainGetOptionSync(key: 'upnp-status');
    final upnpOk = upnpStatus == 'ok';
    final textColor = Theme.of(context).textTheme.titleLarge?.color;

    // 显示用："地址:端口"，没有则只显示地址，再没有则"Not available"
    String publicAddr = publicIP;
    String lanAddr = lanIP;
    if (directPort.isNotEmpty) {
      if (publicIP.isNotEmpty) publicAddr = '$publicIP:$directPort';
      if (lanIP.isNotEmpty) lanAddr = '$lanIP:$directPort';
    }

    return Container(
      margin: const EdgeInsets.only(left: 20, right: 11),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题
          Text(
            "IP直连",
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: textColor?.withOpacity(0.45)),
          ),
          SizedBox(height: 6),
          // 公网 IP 卡片 —— 独立蓝色竖线
          _ipCard(
            context: context,
            label: '公网',
            addr: publicAddr,
            hasAddr: publicAddr.isNotEmpty,
            textColor: textColor,
            upnpOk: upnpOk,
            showUpnp: true,
          ),
          SizedBox(height: 6),
          // 内网 IP 卡片 —— 独立蓝色竖线
          _ipCard(
            context: context,
            label: '内网',
            addr: lanAddr,
            hasAddr: lanAddr.isNotEmpty,
            textColor: textColor,
            upnpOk: false,
            showUpnp: false,
          ),
        ],
      ),
    );
  }

  // 一行 IP 显示：左侧独立蓝色竖线 + 标签 + IP:端口
  //鼠标移到 IP 上时，Tooltip 弹窗显示完整地址（防止因宽度不够被截断）
  Widget _ipCard(
      {required BuildContext context,
      required String label,
      required String addr,
      required bool hasAddr,
      required Color? textColor,
      required bool upnpOk,
      required bool showUpnp}) {
    final naText = translate('Not available');
    final displayText = addr.isNotEmpty ? addr : naText;
    // Tooltip 完整文本，悬停弹窗显示用，UPnP 状态一并放入弹窗
    final tooltipText = showUpnp && addr.isNotEmpty
        ? (upnpOk
            ? '$addr\n端口已映射，外网可直连'
            : '$addr\n端口映射未成功，需手动配置路由器端口转发')
        : (addr.isNotEmpty ? addr : naText);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 3,
          height: 30,
          decoration: BoxDecoration(
            color: MyTheme.accent,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        SizedBox(width: 8),
        SizedBox(
          width: 24,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: textColor?.withOpacity(0.5),
            ),
          ),
        ),
        Expanded(
          child: Tooltip(
            message: tooltipText,
            preferBelow: false,
            waitDuration: Duration(milliseconds: 200),
            child: GestureDetector(
              onDoubleTap: () {
                if (addr.isNotEmpty) {
                  Clipboard.setData(ClipboardData(text: addr));
                  showToast(translate("Copied"));
                }
              },
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .background
                      .withOpacity(0.5),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        displayText,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'monospace',
                          letterSpacing: 0.3,
                          color: hasAddr
                              ? textColor
                              : textColor?.withOpacity(0.4),
                        ),
                      ),
                    ),
                    if (showUpnp && addr.isNotEmpty) ...[
                      SizedBox(width: 4),
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: upnpOk ? Colors.green : Colors.orange,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget buildHelpCards(String updateUrl) {
    if (!bind.isCustomClient() &&
        updateUrl.isNotEmpty &&
        !isCardClosed &&
        bind.mainUriPrefixSync().contains('luoda')) {
      final isToUpdate = (isWindows || isMacOS) && bind.mainIsInstalled();
      String btnText = isToUpdate ? 'Update' : 'Download';
      GestureTapCallback onPressed = () async {
        final Uri url = Uri.parse('https://dicad.cn/download');
        await launchUrl(url);
      };
      if (isToUpdate) {
        onPressed = () {
          handleUpdate(updateUrl);
        };
      }
      return buildInstallCard(
          "Status",
          "${translate("new-version-of-{${bind.mainGetAppNameSync()}}-tip")} (${bind.mainGetNewVersion()}).",
          btnText,
          onPressed,
          closeButton: true,
          help: isToUpdate ? 'Changelog' : null,
          link: isToUpdate
              ? 'https://github.com/luoda/luoda/releases/tag/${bind.mainGetNewVersion()}'
              : null);
    }
    if (systemError.isNotEmpty) {
      return buildInstallCard("", systemError, "", () {});
    }

    if (isWindows && !bind.isDisableInstallation()) {
      // Installation prompt removed for LUODA
      if (false && !bind.mainIsInstalled()) {
        return buildInstallCard(
            "", bind.isOutgoingOnly() ? "" : "install_tip", "Install",
            () async {
          await luodaWinManager.closeAllSubWindows();
          bind.mainGotoInstall();
        });
      } else if (false && bind.mainIsInstalledLowerVersion()) {
        return buildInstallCard(
            "Status", "Your installation is lower version.", "Click to upgrade",
            () async {
          await luodaWinManager.closeAllSubWindows();
          bind.mainUpdateMe();
        });
      }
    } else if (isMacOS) {
      final isOutgoingOnly = bind.isOutgoingOnly();
      if (!(isOutgoingOnly || bind.mainIsCanScreenRecording(prompt: false))) {
        return buildInstallCard("Permissions", "config_screen", "Configure",
            () async {
          bind.mainIsCanScreenRecording(prompt: true);
          watchIsCanScreenRecording = true;
        }, help: 'Help', link: translate("doc_mac_permission"));
      } else if (!isOutgoingOnly && !bind.mainIsProcessTrusted(prompt: false)) {
        return buildInstallCard("Permissions", "config_acc", "Configure",
            () async {
          bind.mainIsProcessTrusted(prompt: true);
          watchIsProcessTrust = true;
        }, help: 'Help', link: translate("doc_mac_permission"));
      } else if (!bind.mainIsCanInputMonitoring(prompt: false)) {
        return buildInstallCard("Permissions", "config_input", "Configure",
            () async {
          bind.mainIsCanInputMonitoring(prompt: true);
          watchIsInputMonitoring = true;
        }, help: 'Help', link: translate("doc_mac_permission"));
      } else if (!isOutgoingOnly &&
          !svcStopped.value &&
          bind.mainIsInstalled() &&
          !bind.mainIsInstalledDaemon(prompt: false)) {
        return buildInstallCard("", "install_daemon_tip", "Install", () async {
          bind.mainIsInstalledDaemon(prompt: true);
        });
      }
      //// Disable microphone configuration for macOS. We will request the permission when needed.
      // else if ((await osxCanRecordAudio() !=
      //     PermissionAuthorizeType.authorized)) {
      //   return buildInstallCard("Permissions", "config_microphone", "Configure",
      //       () async {
      //     osxRequestAudio();
      //     watchIsCanRecordAudio = true;
      //   });
      // }
    } else if (isLinux) {
      if (bind.isOutgoingOnly()) {
        return Container();
      }
      final LinuxCards = <Widget>[];
      if (bind.isSelinuxEnforcing()) {
        // Check is SELinux enforcing, but show user a tip of is SELinux enabled for simple.
        final keyShowSelinuxHelpTip = "show-selinux-help-tip";
        if (bind.mainGetLocalOption(key: keyShowSelinuxHelpTip) != 'N') {
          LinuxCards.add(buildInstallCard(
            "Warning",
            "selinux_tip",
            "",
            () async {},
            marginTop: LinuxCards.isEmpty ? 20.0 : 5.0,
            help: 'Help',
            link:
                'https://dicad.cn/docs/en/client/linux/#permissions-issue',
            closeButton: true,
            closeOption: keyShowSelinuxHelpTip,
          ));
        }
      }
      // Wayland warnings removed per user request
      if (LinuxCards.isNotEmpty) {
        return Column(
          children: LinuxCards,
        );
      }
    }
    if (bind.isIncomingOnly()) {
      return Align(
        alignment: Alignment.centerRight,
        child: OutlinedButton(
          onPressed: () {
            SystemNavigator.pop(); // Close the application
            // https://github.com/flutter/flutter/issues/66631
            if (isWindows) {
              exit(0);
            }
          },
          child: Text(translate('Quit')),
        ),
      ).marginAll(14);
    }
    return Container();
  }

  Widget buildInstallCard(String title, String content, String btnText,
      GestureTapCallback onPressed,
      {double marginTop = 20.0,
      String? help,
      String? link,
      bool? closeButton,
      String? closeOption}) {
    if (bind.mainGetBuildinOption(key: kOptionHideHelpCards) == 'Y' &&
        content != 'install_daemon_tip') {
      return const SizedBox();
    }
    void closeCard() async {
      if (closeOption != null) {
        await bind.mainSetLocalOption(key: closeOption, value: 'N');
        if (bind.mainGetLocalOption(key: closeOption) == 'N') {
          setState(() {
            isCardClosed = true;
          });
        }
      } else {
        setState(() {
          isCardClosed = true;
        });
      }
    }

    return Stack(
      children: [
        Container(
          margin: EdgeInsets.fromLTRB(
              0, marginTop, 0, bind.isIncomingOnly() ? marginTop : 0),
          child: Container(
              decoration: BoxDecoration(
                  gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  Color.fromARGB(255, 226, 66, 188),
                  Color.fromARGB(255, 244, 114, 124),
                ],
              )),
              padding: EdgeInsets.all(20),
              child: Column(
                  mainAxisAlignment: MainAxisAlignment.start,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: (title.isNotEmpty
                          ? <Widget>[
                              Center(
                                  child: Text(
                                translate(title),
                                style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15),
                              ).marginOnly(bottom: 6)),
                            ]
                          : <Widget>[]) +
                      <Widget>[
                        if (content.isNotEmpty)
                          Text(
                            translate(content),
                            style: TextStyle(
                                height: 1.5,
                                color: Colors.white,
                                fontWeight: FontWeight.normal,
                                fontSize: 13),
                          ).marginOnly(bottom: 20)
                      ] +
                      (btnText.isNotEmpty
                          ? <Widget>[
                              Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    FixedWidthButton(
                                      width: 150,
                                      padding: 8,
                                      isOutline: true,
                                      text: translate(btnText),
                                      textColor: Colors.white,
                                      borderColor: Colors.white,
                                      textSize: 20,
                                      radius: 10,
                                      onTap: onPressed,
                                    )
                                  ])
                            ]
                          : <Widget>[]) +
                      (help != null
                          ? <Widget>[
                              Center(
                                  child: InkWell(
                                      onTap: () async =>
                                          await launchUrl(Uri.parse(link!)),
                                      child: Text(
                                        translate(help),
                                        style: TextStyle(
                                            decoration:
                                                TextDecoration.underline,
                                            color: Colors.white,
                                            fontSize: 12),
                                      )).marginOnly(top: 6)),
                            ]
                          : <Widget>[]))),
        ),
        if (closeButton != null && closeButton == true)
          Positioned(
            top: 18,
            right: 0,
            child: IconButton(
              icon: Icon(
                Icons.close,
                color: Colors.white,
                size: 20,
              ),
              onPressed: closeCard,
            ),
          ),
      ],
    );
  }

  @override
  void initState() {
    super.initState();
    _updateTimer = periodic_immediate(const Duration(seconds: 1), () async {
      await gFFI.serverModel.fetchID();
      final error = await bind.mainGetError();
      if (systemError != error) {
        systemError = error;
        setState(() {});
      }
      final v = await mainGetBoolOption(kOptionStopService);
      if (v != svcStopped.value) {
        svcStopped.value = v;
        // When service starts (v becomes false), refresh the temporary password
        if (!v) {
          bind.mainGetTemporaryPassword();
        }
        setState(() {});
      }
      if (watchIsCanScreenRecording) {
        if (bind.mainIsCanScreenRecording(prompt: false)) {
          watchIsCanScreenRecording = false;
          setState(() {});
        }
      }
      if (watchIsProcessTrust) {
        if (bind.mainIsProcessTrusted(prompt: false)) {
          watchIsProcessTrust = false;
          setState(() {});
        }
      }
      if (watchIsInputMonitoring) {
        if (bind.mainIsCanInputMonitoring(prompt: false)) {
          watchIsInputMonitoring = false;
          // Do not notify for now.
          // Monitoring may not take effect until the process is restarted.
          // luodaWinManager.call(
          //     WindowType.RemoteDesktop, kWindowDisableGrabKeyboard, '');
          setState(() {});
        }
      }
      if (watchIsCanRecordAudio) {
        if (isMacOS) {
          Future.microtask(() async {
            if ((await osxCanRecordAudio() ==
                PermissionAuthorizeType.authorized)) {
              watchIsCanRecordAudio = false;
              setState(() {});
            }
          });
        } else {
          watchIsCanRecordAudio = false;
          setState(() {});
        }
      }
      // 1秒定时刷新IP:端口显示
      _refreshIpDisplay();
    });
    Get.put<RxBool>(svcStopped, tag: 'stop-service');
    luodaWinManager.registerActiveWindowListener(onActiveWindowChanged);

    screenToMap(window_size.Screen screen) => {
          'frame': {
            'l': screen.frame.left,
            't': screen.frame.top,
            'r': screen.frame.right,
            'b': screen.frame.bottom,
          },
          'visibleFrame': {
            'l': screen.visibleFrame.left,
            't': screen.visibleFrame.top,
            'r': screen.visibleFrame.right,
            'b': screen.visibleFrame.bottom,
          },
          'scaleFactor': screen.scaleFactor,
        };

    bool isChattyMethod(String methodName) {
      switch (methodName) {
        case kWindowBumpMouse: return true;
      }

      return false;
    }

    luodaWinManager.setMethodHandler((call, fromWindowId) async {
      if (!isChattyMethod(call.method)) {
        debugPrint(
          "[Main] call ${call.method} with args ${call.arguments} from window $fromWindowId");
      }
      if (call.method == kWindowMainWindowOnTop) {
        windowOnTop(null);
      } else if (call.method == kWindowRefreshCurrentUser) {
        gFFI.userModel.refreshCurrentUser();
      } else if (call.method == kWindowGetWindowInfo) {
        final screen = (await window_size.getWindowInfo()).screen;
        if (screen == null) {
          return '';
        } else {
          return jsonEncode(screenToMap(screen));
        }
      } else if (call.method == kWindowGetScreenList) {
        return jsonEncode(
            (await window_size.getScreenList()).map(screenToMap).toList());
      } else if (call.method == kWindowActionRebuild) {
        reloadCurrentWindow();
      } else if (call.method == kWindowEventShow) {
        await luodaWinManager.registerActiveWindow(call.arguments["id"]);
      } else if (call.method == kWindowEventHide) {
        await luodaWinManager.unregisterActiveWindow(call.arguments['id']);
      } else if (call.method == kWindowConnect) {
        await connectMainDesktop(
          call.arguments['id'],
          isFileTransfer: call.arguments['isFileTransfer'],
          isViewCamera: call.arguments['isViewCamera'],
          isTerminal: call.arguments['isTerminal'],
          isTcpTunneling: call.arguments['isTcpTunneling'],
          isRDP: call.arguments['isRDP'],
          password: call.arguments['password'],
          forceRelay: call.arguments['forceRelay'],
          connToken: call.arguments['connToken'],
        );
      } else if (call.method == kWindowBumpMouse) {
        return RdPlatformChannel.instance.bumpMouse(
          dx: call.arguments['dx'],
          dy: call.arguments['dy']);
      } else if (call.method == kWindowEventMoveTabToNewWindow) {
        final args = call.arguments.split(',');
        int? windowId;
        try {
          windowId = int.parse(args[0]);
        } catch (e) {
          debugPrint("Failed to parse window id '${call.arguments}': $e");
        }
        WindowType? windowType;
        try {
          windowType = WindowType.values.byName(args[3]);
        } catch (e) {
          debugPrint("Failed to parse window type '${call.arguments}': $e");
        }
        if (windowId != null && windowType != null) {
          await luodaWinManager.moveTabToNewWindow(
              windowId, args[1], args[2], windowType);
        }
      } else if (call.method == kWindowEventOpenMonitorSession) {
        final args = jsonDecode(call.arguments);
        final windowId = args['window_id'] as int;
        final peerId = args['peer_id'] as String;
        final display = args['display'] as int;
        final displayCount = args['display_count'] as int;
        final windowType = args['window_type'] as int;
        final screenRect = parseParamScreenRect(args);
        await luodaWinManager.openMonitorSession(
            windowId, peerId, display, displayCount, screenRect, windowType);
      } else if (call.method == kWindowEventRemoteWindowCoords) {
        final windowId = int.tryParse(call.arguments);
        if (windowId != null) {
          return jsonEncode(
              await luodaWinManager.getOtherRemoteWindowCoords(windowId));
        }
      }
    });
    _uniLinksSubscription = listenUniLinks();

    if (bind.isIncomingOnly()) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _updateWindowSize();
      });
    }
    WidgetsBinding.instance.addObserver(this);
  }

  _updateWindowSize() {
    if (widget.isClientOnly) return;
    RenderObject? renderObject = _childKey.currentContext?.findRenderObject();
    if (renderObject == null) {
      return;
    }
    if (renderObject is RenderBox) {
      final size = renderObject.size;
      if (size != imcomingOnlyHomeSize) {
        imcomingOnlyHomeSize = size;
        windowManager.setSize(getIncomingOnlyHomeSize());
      }
    }
  }

  _refreshIpDisplay() {
    final ip = bind.mainGetOptionSync(key: 'public-ip');
    final port = bind.mainGetOptionSync(key: kOptionDirectAccessPort);
    if (ip != _lastIp || port != _lastPort) {
      _lastIp = ip;
      _lastPort = port;
      if (ip.isNotEmpty || port.isNotEmpty) {
        setState(() {});
      }
    }
  }

  @override
  void dispose() {
    _uniLinksSubscription?.cancel();
    Get.delete<RxBool>(tag: 'stop-service');
    _updateTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      shouldBeBlocked(_block, canBeBlocked);
    }
  }

  Widget buildPluginEntry() {
    final entries = PluginUiManager.instance.entries.entries;
    return Offstage(
      offstage: entries.isEmpty,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ...entries.map((entry) {
            return entry.value;
          })
        ],
      ),
    );
  }
}

void setPasswordDialog({VoidCallback? notEmptyCallback}) async {
  final p0 = TextEditingController(text: "");
  final p1 = TextEditingController(text: "");
  var errMsg0 = "";
  var errMsg1 = "";
  final localPasswordSet =
      (await bind.mainGetCommon(key: "local-permanent-password-set")) == "true";
  final permanentPasswordSet =
      (await bind.mainGetCommon(key: "permanent-password-set")) == "true";
  final presetPassword = permanentPasswordSet && !localPasswordSet;
  var canSubmit = false;
  final RxString rxPass = "".obs;
  final rules = [
    DigitValidationRule(),
    UppercaseValidationRule(),
    LowercaseValidationRule(),
    // SpecialCharacterValidationRule(),
    MinCharactersValidationRule(8),
  ];
  final maxLength = bind.mainMaxEncryptLen();
  final statusTip = localPasswordSet
      ? translate('password-hidden-tip')
      : (presetPassword ? translate('preset-password-in-use-tip') : '');
  final showStatusTipOnMobile =
      statusTip.isNotEmpty && !isDesktop && !isWebDesktop;

  gFFI.dialogManager.show((setState, close, context) {
    updateCanSubmit() {
      canSubmit = p0.text.trim().isNotEmpty || p1.text.trim().isNotEmpty;
    }

    submit() async {
      if (!canSubmit) {
        return;
      }
      setState(() {
        errMsg0 = "";
        errMsg1 = "";
      });
      final pass = p0.text.trim();
      if (pass.isNotEmpty) {
        final Iterable violations = rules.where((r) => !r.validate(pass));
        if (violations.isNotEmpty) {
          setState(() {
            errMsg0 =
                '${translate('Prompt')}: ${violations.map((r) => r.name).join(', ')}';
          });
          return;
        }
      }
      if (p1.text.trim() != pass) {
        setState(() {
          errMsg1 =
              '${translate('Prompt')}: ${translate("The confirmation is not identical.")}';
        });
        return;
      }
      final ok = await bind.mainSetPermanentPasswordWithResult(password: pass);
      if (!ok) {
        setState(() {
          errMsg0 = '${translate('Prompt')}: ${translate("Failed")}';
        });
        return;
      }
      if (pass.isNotEmpty) {
        notEmptyCallback?.call();
      }
      close();
    }

    return CustomAlertDialog(
      title: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.key, color: MyTheme.accent),
          Text(translate("Set Password")).paddingOnly(left: 10),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 500),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: showStatusTipOnMobile ? 0.0 : 6.0,
            ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    obscureText: true,
                    decoration: InputDecoration(
                        labelText: translate('Password'),
                        errorText: errMsg0.isNotEmpty ? errMsg0 : null),
                    controller: p0,
                    autofocus: true,
                    onChanged: (value) {
                      rxPass.value = value.trim();
                      setState(() {
                        errMsg0 = '';
                        updateCanSubmit();
                      });
                    },
                    maxLength: maxLength,
                  ).workaroundFreezeLinuxMint(),
                ),
              ],
            ),
            Row(
              children: [
                Expanded(child: PasswordStrengthIndicator(password: rxPass)),
              ],
            ).marginOnly(top: 2, bottom: showStatusTipOnMobile ? 2 : 8),
            SizedBox(
              height: showStatusTipOnMobile ? 0.0 : 8.0,
            ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    obscureText: true,
                    decoration: InputDecoration(
                        labelText: translate('Confirmation'),
                        errorText: errMsg1.isNotEmpty ? errMsg1 : null),
                    controller: p1,
                    onChanged: (value) {
                      setState(() {
                        errMsg1 = '';
                        updateCanSubmit();
                      });
                    },
                    maxLength: maxLength,
                  ).workaroundFreezeLinuxMint(),
                ),
              ],
            ),
            if (statusTip.isNotEmpty)
              Row(
                children: [
                  Icon(Icons.info, color: Colors.amber, size: 18)
                      .marginOnly(right: 6),
                  Expanded(
                      child: Text(
                    statusTip,
                    style: const TextStyle(fontSize: 13, height: 1.1),
                  ))
                ],
              ).marginOnly(top: 6, bottom: 2),
            SizedBox(
              height: showStatusTipOnMobile ? 0.0 : 8.0,
            ),
            Obx(() => Wrap(
                  runSpacing: showStatusTipOnMobile ? 2.0 : 8.0,
                  spacing: 4,
                  children: rules.map((e) {
                    var checked = e.validate(rxPass.value.trim());
                    return Chip(
                        label: Text(
                          e.name,
                          style: TextStyle(
                              color: checked
                                  ? const Color(0xFF0A9471)
                                  : Color.fromARGB(255, 198, 86, 157)),
                        ),
                        backgroundColor: checked
                            ? const Color(0xFFD0F7ED)
                            : Color.fromARGB(255, 247, 205, 232));
                  }).toList(),
                ))
          ],
        ),
      ),
      actions: (() {
        final cancelButton = dialogButton(
          "Cancel",
          icon: Icon(Icons.close_rounded),
          onPressed: close,
          isOutline: true,
        );
        final removeButton = dialogButton(
          "Remove",
          icon: Icon(Icons.delete_outline_rounded),
          onPressed: () async {
            setState(() {
              errMsg0 = "";
              errMsg1 = "";
            });
            final ok =
                await bind.mainSetPermanentPasswordWithResult(password: "");
            if (!ok) {
              setState(() {
                errMsg0 = '${translate('Prompt')}: ${translate("Failed")}';
              });
              return;
            }
            close();
          },
          buttonStyle: ButtonStyle(
              backgroundColor: MaterialStatePropertyAll(Colors.red)),
        );
        final okButton = dialogButton(
          "OK",
          icon: Icon(Icons.done_rounded),
          onPressed: canSubmit ? submit : null,
        );
        if (!isDesktop && !isWebDesktop && localPasswordSet) {
          return [
            Align(
              alignment: Alignment.centerRight,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    cancelButton,
                    const SizedBox(width: 4),
                    removeButton,
                    const SizedBox(width: 4),
                    okButton,
                  ],
                ),
              ),
            ),
          ];
        }
        return [
          cancelButton,
          if (localPasswordSet) removeButton,
          okButton,
        ];
      })(),
      onSubmit: canSubmit ? submit : null,
      onCancel: close,
    );
  });
}
