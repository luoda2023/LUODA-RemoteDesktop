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

const _kFirstRunAuthorization = 'android-first-run-authorization-v1';

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
    _firstRunPermissionFlow = FirstRunPermissionFlow([
      () async {
        await gFFI.serverModel.checkRequestNotificationPermission();
      },
      () => _requestPermissionIfMissing(kRecordAudio),
      () => _requestPermissionIfMissing(kRequestIgnoreBatteryOptimizations),
      () async {
        await gFFI.serverModel.checkFloatingWindowPermission();
      },
      () => _requestPermissionIfMissing(kManageExternalStorage),
      _requestAccessibilityPermission,
      _ensureScreenCaptureStarted,
    ]);
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
      if (bind.mainGetLocalOption(key: _kFirstRunAuthorization) != 'Y') {
        RuntimeLogger.instance
            .info('ANDROID', 'first-run authorization sequence started');
        await _firstRunPermissionFlow.run();
        await bind.mainSetLocalOption(key: _kFirstRunAuthorization, value: 'Y');
        RuntimeLogger.instance
            .info('ANDROID', 'first-run authorization sequence finished');
      } else {
        await _ensureScreenCaptureStarted();
      }
    } catch (error, stackTrace) {
      RuntimeLogger.instance.error(
          'ANDROID', 'first-run authorization failed: $error\n$stackTrace');
    }
  }

  Future<void> _requestPermissionIfMissing(String type) async {
    if (await AndroidPermissionManager.check(type)) {
      return;
    }
    final granted = await AndroidPermissionManager.request(type);
    RuntimeLogger.instance.info(
        'ANDROID', 'permission request completed; type=$type granted=$granted');
  }

  Future<void> _requestAccessibilityPermission() async {
    if (await AndroidPermissionManager.checkAccessibility()) {
      return;
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
  }

  Future<void> _ensureScreenCaptureStarted() async {
    if (!mounted || gFFI.serverModel.isStart) {
      return;
    }
    final mediaReady =
        await gFFI.invokeMethod('check_video_permission') == true;
    if (mediaReady) {
      return;
    }

    await gFFI.serverModel.startService();
    for (var i = 0; i < 240 && mounted; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      if (await gFFI.invokeMethod('check_video_permission') == true ||
          !gFFI.serverModel.isStart) {
        break;
      }
    }
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
