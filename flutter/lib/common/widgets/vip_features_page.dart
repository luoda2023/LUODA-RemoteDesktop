import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart' as inapp;

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

  // Mobile controller (webview_flutter)
  late final WebViewController? _mobileController;

  // Desktop controller (flutter_inappwebview)
  inapp.InAppWebViewController? _desktopController;

  bool _loading = true;
  bool _canGoBack = false;
  bool _canGoForward = false;
  Timer? _loadingTimer;

  /// CSS injected into every page load to prevent horizontal scrolling
  /// while keeping vertical scroll, and making content fill the width.
  /// Kept as pure CSS on purpose: the old version also installed a JS scroll
  /// guard that called window.scrollTo() on every touchmove, which could fight
  /// the page and freeze the WebView.
  static const String _noHorizontalScrollCss = r'''
(function() {
  try {
    var meta = document.querySelector('meta[name="viewport"]');
    if (!meta) {
      meta = document.createElement('meta');
      meta.name = 'viewport';
      meta.content = 'width=device-width, initial-scale=1.0, maximum-scale=5.0';
      document.head.appendChild(meta);
    }
    var css =
      'html,body{overflow-x:hidden !important;overflow-y:auto !important;'
      + 'width:100% !important;max-width:100% !important;'
      + 'margin:0 !important;padding:0 !important;'
      + 'overscroll-behavior-x:none !important;'
      + 'overscroll-behavior-y:auto !important;}'
      + 'img,video,iframe,table,pre,canvas,svg{max-width:100% !important;height:auto !important;}'
      + '*,*::before,*::after{box-sizing:border-box !important;}'
      + 'body{overflow-wrap:break-word !important;word-break:break-word !important;}'
      + '::-webkit-scrollbar{width:8px !important;height:8px !important;}'
      + '::-webkit-scrollbar-track{background:transparent !important;}'
      + '::-webkit-scrollbar-thumb{background:rgba(128,128,128,0.5) !important;border-radius:4px !important;}'
      + '::-webkit-scrollbar-thumb:hover{background:rgba(128,128,128,0.8) !important;}'
      + '::-webkit-scrollbar-corner{background:transparent !important;}';
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
    }
    if (b) {
      b.style.overflowX = 'hidden';
      b.style.width = '100%';
      b.style.maxWidth = '100%';
      b.style.overscrollBehaviorX = 'none';
    }
  } catch (e) {}
})();
''';

  void _startLoadingTimeout() {
    _loadingTimer?.cancel();
    _loadingTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _loading = false);
    });
  }

  void _injectNoHorizontalScroll(dynamic controller) {
    if (controller == null) return;
    try {
      if (controller is WebViewController) {
        controller.runJavaScript(_noHorizontalScrollCss);
      } else if (controller is inapp.InAppWebViewController) {
        controller.evaluateJavascript(source: _noHorizontalScrollCss);
      }
    } catch (_) {}
  }

  Future<void> _refreshNavState(dynamic controller) async {
    if (controller == null || !mounted) return;
    try {
      bool back, forward;
      if (controller is WebViewController) {
        back = await controller.canGoBack();
        forward = await controller.canGoForward();
      } else if (controller is inapp.InAppWebViewController) {
        back = await controller.canGoBack();
        forward = await controller.canGoForward();
      } else {
        return;
      }
      if (mounted) {
        setState(() {
          _canGoBack = back;
          _canGoForward = forward;
        });
      }
    } catch (_) {}
  }

  void _onPageStarted(dynamic controller) {
    _injectNoHorizontalScroll(controller);
    _startLoadingTimeout();
    if (mounted) setState(() => _loading = true);
    _refreshNavState(controller);
  }

  void _onPageFinished(dynamic controller) {
    _injectNoHorizontalScroll(controller);
    _loadingTimer?.cancel();
    if (mounted) setState(() => _loading = false);
    _refreshNavState(controller);
  }

  @override
  void initState() {
    super.initState();
    if (isAndroid || isIOS) {
      _mobileController = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setNavigationDelegate(NavigationDelegate(
          onPageStarted: (_) => _onPageStarted(_mobileController),
          onPageFinished: (_) => _onPageFinished(_mobileController),
          onWebResourceError: (_) {
            if (mounted) setState(() => _loading = false);
            _refreshNavState(_mobileController);
          },
        ))
        ..loadRequest(Uri.parse(kDownloadUrl));
    } else {
      _mobileController = null;
    }
  }

  Future<void> _openExternal() async {
    final uri = Uri.parse(kDownloadUrl);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      showToast(translate('Failed to open URL'));
    }
  }

  void _cleanupInjectedScripts(dynamic controller) {
    if (controller == null) return;
    try {
      const cleanup = r'''
(function() {
  try {
    var style = document.getElementById('__luoda_noscroll__');
    if (style) style.remove();
  } catch (e) {}
})();
''';
      if (controller is WebViewController) {
        controller.runJavaScript(cleanup);
      } else if (controller is inapp.InAppWebViewController) {
        controller.evaluateJavascript(source: cleanup);
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _loadingTimer?.cancel();
    _cleanupInjectedScripts(_mobileController);
    _cleanupInjectedScripts(_desktopController);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    // Mobile: use webview_flutter (Android/iOS)
    if (isAndroid || isIOS) {
      final controller = _mobileController;
      if (controller == null) return const SizedBox.shrink();
      return Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            top: 44,
            child: WebViewWidget(controller: controller),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _buildNavBar(context, controller),
          ),
          if (_loading)
            const Positioned.fill(
              top: 44,
              child: Center(child: CircularProgressIndicator()),
            ),
        ],
      );
    }

    // Linux & Web: no embedded webview, fall back to external browser
    if (isLinux || isWeb) {
      return _buildExternalBrowserPlaceholder(context);
    }

    // Desktop (Windows/macOS): use flutter_inappwebview
    return _buildDesktopWebView(context);
  }

  Widget _buildDesktopWebView(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(
          top: 44,
          child: inapp.InAppWebView(
            initialUrlRequest:
                inapp.URLRequest(url: inapp.WebUri(kDownloadUrl)),
            initialSettings: inapp.InAppWebViewSettings(
              javaScriptEnabled: true,
              useShouldOverrideUrlLoading: false,
              mediaPlaybackRequiresUserGesture: false,
              allowsInlineMediaPlayback: true,
              iframeAllow: 'fullscreen',
            ),
            onWebViewCreated: (controller) {
              _desktopController = controller;
            },
            onLoadStart: (controller, url) {
              _onPageStarted(controller);
            },
            onLoadStop: (controller, url) {
              _onPageFinished(controller);
            },
            onReceivedError: (controller, request, error) {
              if (mounted) setState(() => _loading = false);
              _refreshNavState(controller);
            },
          ),
        ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: _buildNavBar(context, _desktopController),
        ),
        if (_loading)
          const Positioned.fill(
            top: 44,
            child: Center(child: CircularProgressIndicator()),
          ),
      ],
    );
  }

  Widget _buildExternalBrowserPlaceholder(BuildContext context) {
    final textColor = Theme.of(context).textTheme.titleLarge?.color;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.open_in_browser, size: 64, color: Colors.amber.shade300),
          const SizedBox(height: 16),
          Text(
            translate('VIP features'),
            style: TextStyle(
                fontSize: 20, fontWeight: FontWeight.w500, color: textColor),
          ),
          const SizedBox(height: 8),
          Text(
            kDownloadUrl,
            style: TextStyle(
                fontSize: 14, color: textColor?.withValues(alpha: 0.5)),
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

  Widget _buildNavBar(BuildContext context, dynamic controller) {
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
                    try {
                      if (controller is WebViewController) {
                        if (await controller.canGoBack())
                          await controller.goBack();
                      } else if (controller is inapp.InAppWebViewController) {
                        if (await controller.canGoBack())
                          await controller.goBack();
                      }
                    } catch (_) {}
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
                    try {
                      if (controller is WebViewController) {
                        if (await controller.canGoForward())
                          await controller.goForward();
                      } else if (controller is inapp.InAppWebViewController) {
                        if (await controller.canGoForward())
                          await controller.goForward();
                      }
                    } catch (_) {}
                  }
                : null,
          ),
          IconButton(
            icon: const Icon(Icons.refresh, size: 20),
            tooltip: translate('Refresh'),
            padding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
            onPressed: () {
              try {
                if (controller is WebViewController) {
                  controller.reload();
                } else if (controller is inapp.InAppWebViewController) {
                  controller.reload();
                }
              } catch (_) {}
            },
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
