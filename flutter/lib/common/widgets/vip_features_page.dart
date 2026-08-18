import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../common.dart';

/// VIP 下载/功能页地址：直接内嵌浏览
const String kDownloadUrl = 'https://download.dicad.cn';

class VipFeaturesPage extends StatefulWidget {
  final EdgeInsets? menuPadding;
  const VipFeaturesPage({Key? key, this.menuPadding}) : super(key: key);

  @override
  State<VipFeaturesPage> createState() => _VipFeaturesPageState();
}

class _VipFeaturesPageState extends State<VipFeaturesPage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  late final WebViewController? _controller;
  bool _loading = true;
  bool _canGoBack = false;
  bool _canGoForward = false;

  /// 查询 WebView 导航状态，刷新工具栏按钮可用性。
  Future<void> _refreshNavState() async {
    final controller = _controller;
    if (controller == null || !mounted) return;
    try {
      final back = await controller.canGoBack();
      final forward = await controller.canGoForward();
      if (mounted) {
        setState(() {
          _canGoBack = back;
          _canGoForward = forward;
        });
      }
    } catch (_) {}
  }

  /// 注入样式：全屏宽度自适应，只允许上下滚动、禁止左右滚动。
  void _injectNoHorizontalScroll() {
if (_controller == null) return;
_controller!.runJavaScript(r'''
(function() {
 try {
 // 确保移动端 viewport 正确，防止页面以桌面宽度渲染导致横向溢出
 var meta = document.querySelector('meta[name="viewport"]');
 if (!meta) {
 meta = document.createElement('meta');
 meta.name = 'viewport';
 meta.content = 'width=device-width, initial-scale=1.0, maximum-scale=5.0';
 document.head.appendChild(meta);
 }

 var css =
 // html/body：禁止横向溢出、宽度锁定 100%
 'html,body{overflow-x:hidden !important;overflow-y:auto !important;'
 + 'width:100% !important;max-width:100% !important;'
 + 'margin:0 !important;padding:0 !important;'
 // 阻止横向触摸滑动 & 横向过度滚动
 + 'touch-action:pan-y !important;'
 + 'overscroll-behavior-x:none !important;'
 + 'overscroll-behavior-y:auto !important;}'
 // 媒体元素自适应缩放
 + 'img,video,iframe,table,pre,canvas,svg{max-width:100% !important;height:auto !important;}'
 // 全局盒模型统一
 + '*,*::before,*::after{box-sizing:border-box !important;}'
 // 长文本/长 URL 自动换行，防止撑宽页面
 + 'body{overflow-wrap:break-word !important;word-break:break-word !important;}'
 // 固定/绝对定位元素不超出视口
 + 'body{position:relative !important;}'
 // 可见竖向滚动条：让用户清楚看到滚动位置
 + '::-webkit-scrollbar{width:8px !important;height:8px !important;}'
 + '::-webkit-scrollbar-track{background:transparent !important;}'
 + '::-webkit-scrollbar-thumb{background:rgba(128,128,128,0.5) !important;border-radius:4px !important;}'
 + '::-webkit-scrollbar-thumb:hover{background:rgba(128,128,128,0.8) !important;}'
 + '::-webkit-scrollbar-corner{background:transparent !important;}'
 + 'html{scrollbar-width:thin !important;scrollbar-color:rgba(128,128,128,0.5),transparent !important;}';

 var style = document.getElementById('__luoda_noscroll__');
 if (!style) {
 style = document.createElement('style');
 style.id = '__luoda_noscroll__';
 document.head.appendChild(style);
 }
 style.innerHTML = css;

 var d = document.documentElement;
 var b = document.body;
 if (d) {
 d.style.overflowX = 'hidden';
 d.style.width = '100%';
 d.style.maxWidth = '100%';
 d.style.overscrollBehaviorX = 'none';
 d.style.touchAction = 'pan-y';
 }
 if (b) {
 b.style.overflowX = 'hidden';
 b.style.width = '100%';
 b.style.maxWidth = '100%';
 b.style.overscrollBehaviorX = 'none';
 b.style.touchAction = 'pan-y';
 b.style.position = 'relative';
 }

 // 持续校正：如有横向偏移则拉回（防止 JS 动态内容撑宽后残留在偏移位置）
 if (!window.__luoda_scroll_guard__) {
 window.__luoda_scroll_guard__ = true;
 var guardFn = function() {
 if (window.scrollX > 0) window.scrollTo(0, window.scrollY);
 };
 window.__luoda_scroll_handler__ = guardFn;
 window.addEventListener('scroll', guardFn, { passive: true });
 window.addEventListener('touchmove', guardFn, { passive: true });
 }
 } catch (e) {}
})();
''');
}

  @override
  void initState() {
    super.initState();
    if (!isAndroid && !isIOS) {
      _controller = null;
      return;
    }
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (String url) {
          _injectNoHorizontalScroll();
          if (mounted) {
            setState(() {
              _loading = true;
            });
          }
          _refreshNavState();
        },
        onPageFinished: (String url) {
          _injectNoHorizontalScroll();
          if (mounted) {
            setState(() {
              _loading = false;
            });
          }
          _refreshNavState();
        },
        onWebResourceError: (WebResourceError error) {
          if (mounted) {
            setState(() {
              _loading = false;
            });
          }
          _refreshNavState();
        },
      ))
      ..loadRequest(Uri.parse(kDownloadUrl));
  }

  Future<void> _openExternal() async {
    final uri = Uri.parse(kDownloadUrl);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      showToast(translate('Failed to open URL'));
    }
  }

  /// Remove injected scroll-guard listeners and style element so the
  /// WebView JS context is cleaned up before the controller is disposed.
  void _cleanupInjectedScripts() {
    if (_controller == null) return;
    try {
      _controller!.runJavaScript(r'''
(function() {
  try {
    if (window.__luoda_scroll_guard__) {
      window.removeEventListener('scroll', window.__luoda_scroll_handler__);
      window.removeEventListener('touchmove', window.__luoda_scroll_handler__);
      delete window.__luoda_scroll_guard__;
      delete window.__luoda_scroll_handler__;
    }
    var style = document.getElementById('__luoda_noscroll__');
    if (style) style.remove();
  } catch (e) {}
})();
''');
    } catch (_) {
      // Controller may already be disposed; safe to ignore.
    }
  }

  @override
  void dispose() {
    _cleanupInjectedScripts();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    // webview_flutter 仅支持 Android/iOS；桌面端（Windows/Linux/macOS）
    // 与 Web 端回退到外部浏览器打开。
    if (!isAndroid && !isIOS) {
      final textColor = Theme.of(context).textTheme.titleLarge?.color;
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.open_in_browser,
              size: 64,
              color: Colors.amber.shade300,
            ),
            const SizedBox(height: 16),
            Text(
              translate("VIP features"),
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w500,
                color: textColor,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              kDownloadUrl,
              style: TextStyle(
                fontSize: 14,
                color: textColor?.withValues(alpha: 0.5),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _openExternal,
              icon: const Icon(Icons.launch, size: 18),
              label: Text(translate('Open in browser')),
            ),
          ],
        ),
      );
    }
  // 全屏显示网页：WebView 占满整个 tab 区域，无额外边距/装饰。
  final controller = _controller;
  if (controller == null) {
    return const SizedBox.shrink();
  }
  return Stack(
    fit: StackFit.expand,
    children: [
      // 让出顶部工具栏的空间，WebView 从工具栏下方开始
      Positioned.fill(
        top: 44,
        child: WebViewWidget(controller: controller),
      ),
      // 悬浮导航工具栏：返回 / 前进 / 刷新
      Positioned(
        top: 0,
        left: 0,
        right: 0,
        child: _buildNavBar(context, controller),
      ),
      if (_loading)
        const Positioned.fill(
          top: 44,
          child: Center(
            child: CircularProgressIndicator(),
          ),
        ),
    ],
  );
  }

  Widget _buildNavBar(BuildContext context, WebViewController controller) {
    final theme = Theme.of(context);
    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.92),
        border: Border(
          bottom: BorderSide(
            color: theme.dividerColor.withValues(alpha: 0.3),
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_new, size: 20),
            tooltip: translate('Back'),
            padding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
            onPressed: _canGoBack
                ? () async {
                    if (await controller.canGoBack()) {
                      await controller.goBack();
                    }
                  }
                : null,
          ),
          IconButton(
            icon: const Icon(Icons.arrow_forward_ios, size: 20),
            tooltip: translate('Forward'),
            padding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
            onPressed: _canGoForward
                ? () async {
                    if (await controller.canGoForward()) {
                      await controller.goForward();
                    }
                  }
                : null,
          ),
          IconButton(
            icon: const Icon(Icons.refresh, size: 20),
            tooltip: translate('Refresh'),
            padding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
            onPressed: () => controller.reload(),
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.open_in_browser, size: 18),
            tooltip: translate('Open in browser'),
            padding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
            onPressed: _openExternal,
          ),
        ],
      ),
    );
  }
}
