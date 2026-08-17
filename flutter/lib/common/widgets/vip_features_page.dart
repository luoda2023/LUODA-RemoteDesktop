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

  late final WebViewController _controller;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (String url) {
          if (mounted) {
            setState(() {
              _loading = true;
            });
          }
        },
        onPageFinished: (String url) {
          if (mounted) {
            setState(() {
              _loading = false;
            });
          }
        },
        onWebResourceError: (WebResourceError error) {
          if (mounted) {
            setState(() {
              _loading = false;
            });
          }
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

  @override
  Widget build(BuildContext context) {
    super.build(context);
    // 桌面端 webview_flutter 不支持（Windows），回退到外部浏览器打开。
    if (isDesktop || isWebDesktop) {
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
    return Stack(
      children: [
        WebViewWidget(controller: _controller),
        if (_loading)
          const Center(
            child: CircularProgressIndicator(),
          ),
      ],
    );
  }
}
