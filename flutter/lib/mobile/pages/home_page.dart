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

/// Persisted authorization marker on the *real public* external storage
/// (/storage/emulated/0/Android/data/... is app-private and wiped together
/// with the app data on uninstall, so we deliberately use a folder that
/// survives reinstall). path_provider's external dirs are app-scoped, so the
/// path is resolved natively from Kotlin and cached in the Rust LocalConfig
/// (history-backup-dir). Falling back to the app-private marker keeps
/// "reinstalled over the same version" working even when the storage
/// permission was revoked (Android 13+ / no MANAGE_EXTERNAL_STORAGE grant).
String _authorizationBaseDir() {
  final dir = bind.mainGetLocalOption(key: kOptionAuthorizationBaseDir);
  if (dir.isNotEmpty) return dir;
  final backupDir = bind.mainGetLocalOption(key: kOptionHistoryBackupDir);
  if (backupDir.isNotEmpty) return File(backupDir).parent.path;
  return '';
}

File? _publicAuthMarkerFile() {
  final dir = _authorizationBaseDir();
  if (dir.isEmpty) return null;
  return File('$dir${Platform.pathSeparator}$_kPublicAuthMarkerName');
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

  /// True when the marker says the user already completed the one-tap flow AND
  /// the accessibility service (the capability Android wipes on a real
  /// uninstall/reinstall) is currently granted. When both hold, the app starts
  /// silently; otherwise the guided flow runs again but every step auto-skips
  /// the grants that are already in place.
  Future<bool> _canStartQuietly() async {
    try {
      final markedDone =
          bind.mainGetLocalOption(key: _kFirstRunAuthorization) == 'Y' ||
              await gFFI.invokeMethod('get_first_run_authorization') == true ||
              _readPublicAuthMarker();
      if (!markedDone) return false;
      // The accessibility grant is the capability Android actually wipes on a
      // real uninstall/reinstall, so treat it as the source of truth: only a
      // device whose accessibility service is still enabled starts silently.
      return await AndroidPermissionManager.checkAccessibility();
    } catch (e) {
      RuntimeLogger.instance.info('ANDROID', 'quiet-start check failed: $e');
    }
    return false;
  }

  /// On every cold start:
  ///  - already-authorized device: quietly request only the standard runtime
  ///    permissions that may have been reset by a reinstall (single system
  ///    dialog, no accessibility jump, no screen-capture prompt), then refresh
  ///    the marker; nothing pops when everything is already granted.
  ///  - first run: run the guided one-tap flow.
  Future<void> _runFirstLaunchAuthorization() async {
    if (!isAndroid || bind.isOutgoingOnly() || !mounted) {
      return;
    }
    try {
      final canStartQuietly = await _canStartQuietly();
      if (!canStartQuietly) {
        RuntimeLogger.instance
            .info('ANDROID', 'first-run authorization sequence started');
        final completed = await _firstRunPermissionFlow.run();
        if (completed) {
          await bind.mainSetLocalOption(
              key: _kFirstRunAuthorization, value: 'Y');
          await gFFI.invokeMethod('set_first_run_authorization', true);
          _writePublicAuthMarker();
          RuntimeLogger.instance
              .info('ANDROID', 'first-run authorization sequence finished');
        } else {
          RuntimeLogger.instance.warn('ANDROID',
              'first-run authorization incomplete; will retry on next launch');
        }
        return;
      }
      // Prior authorization: silently top up standard runtime permissions.
      // On a fresh reinstall Android resets those, but the batch system dialog
      // regrants them in one tap; when they are already granted nothing pops.
      // Accessibility keeps its OS-granted state and is never re-prompted here;
      // screen capture is only requested when the user actually starts a
      // session (Android 14+ revokes that token on every reboot, so auto
      // prompting on cold start would only annoy).
      RuntimeLogger.instance
          .info('ANDROID', 'rechecking Android authorization state');
      final stillComplete = await _requestStandardPermissionsBatch();
      if (stillComplete) {
        await bind.mainSetLocalOption(key: _kFirstRunAuthorization, value: 'Y');
        await gFFI.invokeMethod('set_first_run_authorization', true);
        _writePublicAuthMarker();
      }
    } catch (error, stackTrace) {
      RuntimeLogger.instance.error(
          'ANDROID', 'first-run authorization failed: $error\n$stackTrace');
    }
  }

  /// Batch-request the standard runtime permissions that matter for the core
  /// remote-control flow in ONE system dialog (they merge on modern Android).
  /// The "special" system pages (all-files access, battery-optimization list)
  /// are deliberately NOT requested here — each is a full separate settings
  /// screen and they are only needed by the optional file manager / keep-alive;
  /// they stay available in Settings when actually used.
  Future<bool> _requestStandardPermissionsBatch() async {
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

    if (typesToRequest.isEmpty) {
      return true;
    }

    // Request all ungranted standard permissions at once via batch API.
    RuntimeLogger.instance.info('ANDROID',
        'batch requesting ${typesToRequest.length} permissions: $typesToRequest');
    await gFFI.invokeMethod('request_permissions_batch', typesToRequest);

    // Wait for the batch dialog to complete by polling each permission.
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
    // Screen capture is only useful together with the accessibility input
    // service. In the guided flow step 2 already walked the user through
    // enabling it; if it is still off, skip the MediaProjection dialog instead
    // of stacking a second system prompt on top of the previous one.
    if (!await AndroidPermissionManager.checkAccessibility()) {
      RuntimeLogger.instance
          .warn('ANDROID', 'screen capture skipped: accessibility not enabled');
      return false;
    }
    final mediaReady =
        await gFFI.invokeMethod('check_video_permission') == true;
    if (mediaReady) {
      return true;
    }

    // One system MediaProjection confirmation dialog. This is the "one tap"
    // inside the first-run flow: once granted the token stays alive while the
    // service runs, and sessions no longer re-ask.
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
