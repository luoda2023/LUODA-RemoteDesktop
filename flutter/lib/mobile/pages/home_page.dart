import 'dart:async';

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

const _kFirstRunAuthorization = 'android-first-run-authorization-v2';

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
      final previouslyCompleted =
          bind.mainGetLocalOption(key: _kFirstRunAuthorization) == 'Y';
      if (!previouslyCompleted) {
        RuntimeLogger.instance
            .info('ANDROID', 'first-run authorization sequence started');
        // Show a one-time guidance dialog before requesting permissions
        final userAgreed = await _showFirstRunPermissionDialog();
        if (!userAgreed) {
          RuntimeLogger.instance
              .warn('ANDROID', 'user deferred first-run authorization');
          return;
        }
      } else {
        RuntimeLogger.instance
            .info('ANDROID', 'rechecking Android authorization state');
      }
      final completed = await _firstRunPermissionFlow.run();
      if (completed) {
        await bind.mainSetLocalOption(key: _kFirstRunAuthorization, value: 'Y');
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

  /// Show a one-time dialog explaining all permissions before requesting them.
  /// Returns true if the user tapped "一键授权", false if they deferred.
  Future<bool> _showFirstRunPermissionDialog() async {
    if (!mounted) return false;
    final res = await gFFI.dialogManager.show<bool>((setState, close, context) {
      return CustomAlertDialog(
        title: Row(children: [
          const Icon(Icons.security, color: Colors.blue, size: 28),
          const SizedBox(width: 10),
          Text(translate('One-time Authorization')),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(translate('android_first_run_permission_tip'),
                style: const TextStyle(fontSize: 14)),
            const SizedBox(height: 12),
            _buildPermissionItem(Icons.notifications, 'Notification',
                translate('Receive connection notifications')),
            _buildPermissionItem(Icons.mic, 'Microphone',
                translate('Voice call during remote control')),
            _buildPermissionItem(Icons.battery_full, 'Battery',
                translate('Keep service alive in background')),
            _buildPermissionItem(Icons.picture_in_picture, 'Floating Window',
                translate('Show floating window when minimized')),
            _buildPermissionItem(Icons.folder, 'Storage',
                translate('File transfer support')),
            _buildPermissionItem(Icons.accessibility, 'Accessibility',
                translate('Remote control of this device')),
            _buildPermissionItem(Icons.screen_share, 'Screen Capture',
                translate('Share screen to remote')),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => close(false),
              child: Text(translate('Later'))),
          ElevatedButton(
              onPressed: () => close(true),
              child: Text(translate('Authorize All'))),
        ],
        onSubmit: () => close(true),
        onCancel: () => close(false),
      );
    });
    return res == true;
  }

  Widget _buildPermissionItem(IconData icon, String title, String desc) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        Icon(icon, size: 18, color: Colors.grey[600]),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13)),
              Text(desc, style: TextStyle(fontSize: 11, color: Colors.grey[600])),
            ],
          ),
        ),
      ]),
    );
  }

  Future<bool> _requestPermissionIfMissing(String type) async {
    if (await AndroidPermissionManager.check(type)) {
      return true;
    }
    final granted = await AndroidPermissionManager.request(type);
    RuntimeLogger.instance.info(
        'ANDROID', 'permission request completed; type=$type granted=$granted');
    return granted;
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
    if (!await AndroidPermissionManager.check(kRequestIgnoreBatteryOptimizations)) {
      typesToRequest.add(kRequestIgnoreBatteryOptimizations);
    }
    // Floating window / overlay
    if (androidVersion >= 23 &&
        !await AndroidPermissionManager.check(kSystemAlertWindow)) {
      typesToRequest.add(kSystemAlertWindow);
    }
    // External storage
    if (!await AndroidPermissionManager.check(kManageExternalStorage)) {
      typesToRequest.add(kManageExternalStorage);
    }

    if (typesToRequest.isEmpty) {
      return true;
    }

    // Request all ungranted standard permissions at once via batch API
    RuntimeLogger.instance
        .info('ANDROID', 'batch requesting ${typesToRequest.length} permissions: $typesToRequest');
    await gFFI.invokeMethod('request_permissions_batch', typesToRequest);

    // Wait for all results - each type gets its own callback via on_android_permission_result
    for (final type in typesToRequest) {
      final granted = await AndroidPermissionManager.request(type).timeout(
        const Duration(seconds: 30),
        onTimeout: () => false,
      );
      // The batch request already shows the dialog; the per-type request above
      // just waits for the result that was already reported by the batch callback.
      if (!granted) allOk = false;
      RuntimeLogger.instance
          .info('ANDROID', 'batch permission result; type=$type granted=$granted');
    }

    return allOk;
  }

  Future<bool> _requestAccessibilityPermission() async {
    if (await AndroidPermissionManager.checkAccessibility()) {
      return true;
    }

    // Show a brief hint before jumping to settings
    if (mounted) {
      await gFFI.dialogManager.show<void>((setState, close, context) {
        return CustomAlertDialog(
          title: Row(children: [
            const Icon(Icons.accessibility, color: Colors.blue, size: 24),
            const SizedBox(width: 8),
            Text(translate('Enable Accessibility')),
          ]),
          content: Text(translate('android_accessibility_hint')),
          actions: [
            ElevatedButton(
                onPressed: close, child: Text(translate('Go to Settings'))),
          ],
          onSubmit: close,
          onCancel: close,
        );
      });
    }

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

    final granted = await AndroidPermissionManager.checkAccessibility();
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
        appBarActions: [],
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
    return WillPopScope(
        onWillPop: () async {
          if (_selectedIndex != 0) {
            setState(() {
              _selectedIndex = 0;
            });
          } else {
            return true;
          }
          return false;
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
        title: Text("${bind.mainGetAppNameSync()} (Preview)"),
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
