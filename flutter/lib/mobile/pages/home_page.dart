import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:luoda_flutter/mobile/pages/server_page.dart';
import 'package:luoda_flutter/mobile/pages/settings_page.dart';
import 'package:luoda_flutter/runtime_logger.dart';
import 'package:luoda_flutter/web/settings_page.dart';
import 'package:get/get.dart';
import '../../common.dart';
import '../../common/widgets/chat_page.dart';
import '../../consts.dart';
import '../../models/platform_model.dart';
import '../../models/state_model.dart';
import '../first_run_permission_flow.dart';
import 'connection_page.dart';
import 'scan_page.dart';

const _kFirstRunAuthorization = 'android-first-run-authorization-v2';
const _kPublicAuthMarkerName = 'first-run-authorization';

/// The public-storage marker file lives next to the visit-history backup
/// (Documents/LDesk/), so it survives uninstall/reinstall. The OS always
/// resets runtime permissions on reinstall, but this lets the app remember
/// that the user already completed the one-tap authorization flow before, and
/// skip the explanation dialog on a fresh install.
File? _publicAuthMarkerFile() {
  final backupDir = bind.mainGetLocalOption(key: kOptionHistoryBackupDir);
  if (backupDir.isEmpty) return null;
  final dir = File(backupDir).parent;
  return File('${dir.path}${Platform.pathSeparator}$_kPublicAuthMarkerName');
}

bool _readPublicAuthMarker() {
  try {
    final f = _publicAuthMarkerFile();
    if (f == null) return false;
    return f.existsSync() && f.readAsStringSync().trim() == 'Y';
  } catch (_) {
    return false;
  }
}

void _writePublicAuthMarker() {
  try {
    final f = _publicAuthMarkerFile();
    if (f == null) return;
    f.parent.createSync(recursive: true);
    f.writeAsStringSync('Y');
  } catch (_) {}
}

abstract class PageShape extends Widget {
  final String title = "";
  final Widget icon = Icon(null);
  final List<Widget> appBarActions = [];
}

class HomePage extends StatefulWidget {
  static final homeKey = GlobalKey<HomePageState>();

  HomePage() : super(key: homeKey);

  @override
  HomePageState createState() => HomePageState();
}

class HomePageState extends State<HomePage> with WidgetsBindingObserver {
  var _selectedIndex = 0;
  int get selectedIndex => _selectedIndex;
  final List<PageShape> _pages = [];
  int _chatPageTabIndex = -1;
  late final FirstRunPermissionFlow _firstRunPermissionFlow;
  Completer<void>? _accessibilityReturn;
  bool _leftForAccessibilitySettings = false;
  bool get isChatPageCurrentTab => isAndroid
      ? _selectedIndex == _chatPageTabIndex
      : false; // change this when ios have chat page

  void refreshPages() {
    setState(() {
      initPages();
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _firstRunPermissionFlow = FirstRunPermissionFlow(
      [
        () => _requestStandardPermissionsBatch(),
        _requestAccessibilityPermission,
        _ensureScreenCaptureStarted,
      ],
      stepNames: ['standard_permissions', 'accessibility', 'screen_capture'],
      onStepProgress: (name, index, total, granted) {
        RuntimeLogger.instance.info('ANDROID',
            'first-run step ${index + 1}/$total ($name): ${granted ? "granted" : "denied/skipped"}');
      },
    );
    initPages();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _runFirstLaunchAuthorization();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    final waiting = _accessibilityReturn;
    if (waiting != null && !waiting.isCompleted) {
      waiting.complete();
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final waiting = _accessibilityReturn;
    if (waiting == null || waiting.isCompleted) {
      return;
    }
    if (state == AppLifecycleState.resumed && _leftForAccessibilitySettings) {
      waiting.complete();
    } else if (state != AppLifecycleState.resumed) {
      _leftForAccessibilitySettings = true;
    }
  }

  Future<void> _runFirstLaunchAuthorization() async {
    if (!isAndroid || bind.isOutgoingOnly() || !mounted) {
      return;
    }
    try {
      final previousLocalMarker =
          bind.mainGetLocalOption(key: _kFirstRunAuthorization) == 'Y';
      final previousAndroidMarker =
          await gFFI.invokeMethod('get_first_run_authorization') == true;
      final previouslyCompleted = previousLocalMarker ||
          previousAndroidMarker ||
          _readPublicAuthMarker();
      if (!previouslyCompleted) {
        RuntimeLogger.instance
            .info('ANDROID', 'first-run authorization sequence started');
      } else {
        RuntimeLogger.instance
            .info('ANDROID', 'rechecking Android authorization state');
      }
      final completed = await _firstRunPermissionFlow.run();
      if (completed) {
        await bind.mainSetLocalOption(key: _kFirstRunAuthorization, value: 'Y');
        await gFFI.invokeMethod('set_first_run_authorization', true);
        _writePublicAuthMarker();
        RuntimeLogger.instance
            .info('ANDROID', 'first-run authorization sequence finished');
      } else {
        RuntimeLogger.instance.warn('ANDROID',
            'first-run authorization incomplete; will retry on next launch');
      }
    } catch (error, stackTrace) {
      RuntimeLogger.instance.error(
          'ANDROID', 'first-run authorization failed: $error\n$stackTrace');
    }
  }

  /// Batch-request all standard runtime permissions in a single system dialog.
  /// This replaces the old approach of requesting each permission one-by-one
  /// which caused multiple separate system dialogs to pop up.
  Future<bool> _requestStandardPermissionsBatch() async {
    // Collect all standard permissions that are not yet granted
    final typesToRequest = <String>[];
    var allOk = true;

    // Notification (Android 13+)
    if (androidVersion >= 33 &&
        !await AndroidPermissionManager.check(kAndroid13Notification)) {
      typesToRequest.add(kAndroid13Notification);
    }
    // Record audio
    if (!await AndroidPermissionManager.check(kRecordAudio)) {
      typesToRequest.add(kRecordAudio);
    }
    // Battery optimization
    if (!await AndroidPermissionManager.check(
        kRequestIgnoreBatteryOptimizations)) {
      typesToRequest.add(kRequestIgnoreBatteryOptimizations);
    }
    // External storage
    if (!await AndroidPermissionManager.check(kManageExternalStorage)) {
      typesToRequest.add(kManageExternalStorage);
    }

    if (typesToRequest.isEmpty) {
      return true;
    }

    // Request all ungranted standard permissions at once via batch API.
    // This shows a single system dialog (or minimal dialogs) instead of
    // popping up one dialog per permission.
    RuntimeLogger.instance.info('ANDROID',
        'batch requesting ${typesToRequest.length} permissions: $typesToRequest');
    await gFFI.invokeMethod('request_permissions_batch', typesToRequest);

    // Wait for the batch dialog to complete by polling each permission.
    // The batch API reports results via on_android_permission_result callback,
    // but we simply re-check each permission after a short delay.
    // Give the system dialog time to show and be answered.
    for (final type in typesToRequest) {
      // Poll up to 30 seconds for each permission to be granted
      var granted = false;
      for (var attempt = 0; attempt < 60; attempt++) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
        if (await AndroidPermissionManager.check(type)) {
          granted = true;
          break;
        }
        if (!mounted) break;
      }
      if (!granted) allOk = false;
      RuntimeLogger.instance.info(
          'ANDROID', 'batch permission result; type=$type granted=$granted');
    }

    return allOk;
  }

  Future<bool> _requestAccessibilityPermission() async {
    if (await AndroidPermissionManager.checkAccessibility()) {
      return true;
    }

    // 直接跳转到无障碍设置页，不弹中间提示框，让"一键授权"尽可能一步到位
    final waiting = Completer<void>();
    _accessibilityReturn = waiting;
    _leftForAccessibilitySettings = false;
    final opened = await AndroidPermissionManager.startAction(
        kActionAccessibilityDetailsSettings);
    if (!opened && !waiting.isCompleted) {
      waiting.complete();
    }
    try {
      await waiting.future.timeout(const Duration(minutes: 5));
    } on TimeoutException {
      RuntimeLogger.instance.warn(
          'ANDROID', 'accessibility settings did not return within 5 minutes');
    } finally {
      _accessibilityReturn = null;
      _leftForAccessibilitySettings = false;
    }

    // Some ROMs connect the accessibility service a moment after the toggle
    // is flipped; poll briefly so the flow reports the real state instead of
    // an immediate false negative.
    var granted = await AndroidPermissionManager.checkAccessibility();
    for (var i = 0; i < 20 && !granted; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      granted = await AndroidPermissionManager.checkAccessibility();
    }
    await gFFI.invokeMethod('check_service');
    RuntimeLogger.instance
        .info('ANDROID', 'accessibility request completed; granted=$granted');
    return granted;
  }

  Future<bool> _ensureScreenCaptureStarted() async {
    if (!mounted) {
      return false;
    }
    final mediaReady =
        await gFFI.invokeMethod('check_video_permission') == true;
    if (mediaReady) {
      return true;
    }

    await gFFI.serverModel.startService();
    for (var i = 0; i < 240 && mounted; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      if (await gFFI.invokeMethod('check_video_permission') == true ||
          !gFFI.serverModel.isStart) {
        break;
      }
    }
    return await gFFI.invokeMethod('check_video_permission') == true;
  }

  void initPages() {
    _pages.clear();
    if (!bind.isIncomingOnly()) {
      _pages.add(ConnectionPage(
        appBarActions: bind.isDisableSettings() ? [] : [_ScanConnectButton()],
      ));
    }
    if (isAndroid && !bind.isOutgoingOnly()) {
      _chatPageTabIndex = _pages.length;
      _pages.addAll([ChatPage(type: ChatPageType.mobileMain), ServerPage()]);
    }
    _pages.add(SettingsPage());
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
        canPop: _selectedIndex == 0,
        onPopInvokedWithResult: (didPop, result) {
          if (didPop) return;
          setState(() {
            _selectedIndex = 0;
          });
        },
        child: Scaffold(
          // backgroundColor: MyTheme.grayBg,
          appBar: AppBar(
            centerTitle: true,
            title: appTitle(),
            actions: _pages.elementAt(_selectedIndex).appBarActions,
          ),
          bottomNavigationBar: BottomNavigationBar(
            key: navigationBarKey,
            items: _pages
                .map((page) =>
                    BottomNavigationBarItem(icon: page.icon, label: page.title))
                .toList(),
            currentIndex: _selectedIndex,
            type: BottomNavigationBarType.fixed,
            selectedItemColor: MyTheme.accent, //
            unselectedItemColor: MyTheme.darkGray,
            onTap: (index) => setState(() {
              // close chat overlay when go chat page
              if (_selectedIndex != index) {
                _selectedIndex = index;
                if (isChatPageCurrentTab) {
                  gFFI.chatModel.hideChatIconOverlay();
                  gFFI.chatModel.hideChatWindowOverlay();
                  gFFI.chatModel.mobileClearClientUnread(
                      gFFI.chatModel.currentKey.connId);
                }
              }
            }),
          ),
          body: _pages.elementAt(_selectedIndex),
        ));
  }

  Widget appTitle() {
    final currentUser = gFFI.chatModel.currentUser;
    final currentKey = gFFI.chatModel.currentKey;
    if (isChatPageCurrentTab &&
        currentUser != null &&
        currentKey.peerId.isNotEmpty) {
      final connected =
          gFFI.serverModel.clients.any((e) => e.id == currentKey.connId);
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Tooltip(
            message: currentKey.isOut
                ? translate('Outgoing connection')
                : translate('Incoming connection'),
            child: Icon(
              currentKey.isOut
                  ? Icons.call_made_rounded
                  : Icons.call_received_rounded,
            ),
          ),
          Expanded(
            child: Center(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    "${currentUser.firstName}   ${currentUser.id}",
                  ),
                  if (connected)
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Color.fromARGB(255, 133, 246, 199)),
                    ).marginSymmetric(horizontal: 2),
                ],
              ),
            ),
          ),
        ],
      );
    }
    return Text(bind.mainGetAppNameSync());
  }
}

class WebHomePage extends StatelessWidget {
  final connectionPage =
      ConnectionPage(appBarActions: <Widget>[const WebSettingsPage()]);

  @override
  Widget build(BuildContext context) {
    stateGlobal.isInMainPage = true;
    handleUnilink(context);
    return Scaffold(
      // backgroundColor: MyTheme.grayBg,
      appBar: AppBar(
        centerTitle: true,
        title: Text("${bind.mainGetAppNameSync()} (${translate('Preview')})"),
        actions: connectionPage.appBarActions,
      ),
      body: connectionPage,
    );
  }

  handleUnilink(BuildContext context) {
    if (webInitialLink.isEmpty) {
      return;
    }
    final link = webInitialLink;
    webInitialLink = '';
    final splitter = ["/#/", "/#", "#/", "#"];
    var fakelink = '';
    for (var s in splitter) {
      if (link.contains(s)) {
        var list = link.split(s);
        if (list.length < 2 || list[1].isEmpty) {
          return;
        }
        list.removeAt(0);
        fakelink = "luoda://${list.join(s)}";
        break;
      }
    }
    if (fakelink.isEmpty) {
      return;
    }
    final uri = Uri.tryParse(fakelink);
    if (uri == null) {
      return;
    }
    final args = urlLinkToCmdArgs(uri);
    if (args == null || args.isEmpty) {
      return;
    }
    bool isFileTransfer = false;
    bool isViewCamera = false;
    bool isTerminal = false;
    String? id;
    String? password;
    for (int i = 0; i < args.length; i++) {
      switch (args[i]) {
        case '--connect':
        case '--play':
          id = args[i + 1];
          i++;
          break;
        case '--file-transfer':
          isFileTransfer = true;
          id = args[i + 1];
          i++;
          break;
        case '--view-camera':
          isViewCamera = true;
          id = args[i + 1];
          i++;
          break;
        case '--terminal':
          isTerminal = true;
          id = args[i + 1];
          i++;
          break;
        case '--terminal-admin':
          setEnvTerminalAdmin();
          isTerminal = true;
          id = args[i + 1];
          i++;
          break;
        case '--password':
          password = args[i + 1];
          i++;
          break;
        default:
          break;
      }
    }
    if (id != null) {
      connect(context, id,
          isFileTransfer: isFileTransfer,
          isViewCamera: isViewCamera,
          isTerminal: isTerminal,
          password: password);
    }
  }
}

/// AppBar button that opens the QR scanner for one-tap connect.
class _ScanConnectButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(Icons.qr_code_scanner),
      tooltip: translate('Scan QR'),
      onPressed: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (ctx) => ScanPage()),
        );
      },
    );
  }
}
