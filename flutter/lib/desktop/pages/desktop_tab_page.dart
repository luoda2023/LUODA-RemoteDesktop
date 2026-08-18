import 'package:flutter/material.dart';
import 'package:luoda_flutter/common.dart';
import 'package:luoda_flutter/consts.dart';
import 'package:luoda_flutter/desktop/pages/desktop_home_page.dart';
import 'package:luoda_flutter/desktop/pages/desktop_setting_page.dart';
import 'package:luoda_flutter/desktop/widgets/tabbar_widget.dart';
import 'package:luoda_flutter/models/platform_model.dart';
import 'package:luoda_flutter/models/state_model.dart';
import 'package:get/get.dart';
import 'package:window_manager/window_manager.dart';
// import 'package:flutter/services.dart';

import '../../common/shared_state.dart';

class DesktopTabPage extends StatefulWidget {
  const DesktopTabPage({Key? key}) : super(key: key);

  @override
  State<DesktopTabPage> createState() => _DesktopTabPageState();

  static void onAddSetting(
      {SettingsTabKey initialPage = SettingsTabKey.general}) {
    try {
      DesktopTabController tabController = Get.find<DesktopTabController>();
      tabController.add(TabInfo(
          key: kTabLabelSettingPage,
          label: kTabLabelSettingPage,
          selectedIcon: Icons.build_sharp,
          unselectedIcon: Icons.build_outlined,
          page: DesktopSettingPage(
            key: const ValueKey(kTabLabelSettingPage),
            initialTabkey: initialPage,
          )));
    } catch (e) {
      debugPrintStack(label: '$e');
    }
  }
}

class _DesktopTabPageState extends State<DesktopTabPage> {
  final tabController = DesktopTabController(tabType: DesktopTabType.main);

  _DesktopTabPageState() {
    RemoteCountState.init();
    Get.put<DesktopTabController>(tabController);
    tabController.add(TabInfo(
        key: kTabLabelHomePage,
        label: kTabLabelHomePage,
        selectedIcon: Icons.home_sharp,
        unselectedIcon: Icons.home_outlined,
        closable: false,
        page: DesktopHomePage(
          key: const ValueKey(kTabLabelHomePage),
          isClientOnly: isCustomClientFresh(),
        )));
    if (bind.isIncomingOnly()) {
      tabController.onSelected = (key) {
        if (isCustomClientFresh()) {
          enforceCustomClientHomeWindowSize();
          return;
        }
        if (key == kTabLabelHomePage) {
          windowManager.setSize(getIncomingOnlyHomeSize());
          setResizable(false);
        } else {
          windowManager.setSize(getIncomingOnlySettingsSize());
          setResizable(true);
        }
      };
    }
  }

  @override
  void initState() {
    super.initState();
    // HardwareKeyboard.instance.addHandler(_handleKeyEvent);
  }

  /*
  bool _handleKeyEvent(KeyEvent event) {
    if (!mouseIn && event is KeyDownEvent) {
      debugPrint('key down: ${event.logicalKey}');
      shouldBeBlocked(_block, canBeBlocked);
    }
    return false; // allow it to propagate
  }
  */

  @override
  void dispose() {
    // HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    Get.delete<DesktopTabController>();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 客户端定制版只保留关闭按钮，不显示最小化和最大化。
    final bool compactClient = isCustomClientFresh();
    final tabWidget = Container(
        child: Scaffold(
            backgroundColor: Theme.of(context).colorScheme.surface,
            body: DesktopTab(
              controller: tabController,
              showMinimize: !compactClient,
              showMaximize: !compactClient,
              showClose: true,
tail: Offstage(
 // 用户反馈 (round-17 修正): 顶部 Tab Bar tail 的 Settings ActionIcon 是设置入口,
 // 与 主页左下角"设置/网络"两个按钮功能重复.
 // 全 版 (普 通 + 客 户) 均 隐 藏 这里, 设置入口仅保留 主页左下角按钮 一处.
 // 之前: round-17 我 误 删 了 主 页 左 下 角 按 钮 (A), 这 里 (B) 反 而 还 在 显 示.
 // 现 在 修 回: A 恢 复显 示, B 全 版 隐 藏.
 offstage: true,
 child: ActionIcon(
 message: 'Settings',
 icon: IconFont.menu,
 onTap: DesktopTabPage.onAddSetting,
 isClose: false,
 ),
 ),
            )));
    return compactClient || isMacOS || kUseCompatibleUiMode
        ? tabWidget
        : Obx(
            () => DragToResizeArea(
              resizeEdgeSize: stateGlobal.resizeEdgeSize.value,
              enableResizeEdges: windowManagerEnableResizeEdges,
              child: tabWidget,
            ),
          );
  }
}
