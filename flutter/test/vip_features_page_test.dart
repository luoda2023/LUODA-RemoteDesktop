import 'package:flutter_test/flutter_test.dart';
import 'package:luoda_flutter/common/widgets/vip_features_page.dart';

void main() {
  // Note: A full widget test of VipFeaturesPage is not feasible without a
  // mock PlatformFFI (translate() requires the native library).  We test
  // the constants and structure here; the widget rendering is verified
  // manually on-device and via the scroll-injection unit tests.

  test('kDownloadUrl points to dicad download page', () {
    expect(kDownloadUrl, 'https://download.dicad.cn');
    expect(kDownloadUrl.startsWith('https://'), isTrue);
  });

  test('kDownloadUrl is a valid URI', () {
    final uri = Uri.parse(kDownloadUrl);
    expect(uri.scheme, 'https');
    expect(uri.host, 'download.dicad.cn');
  });
}
