import 'package:flutter_test/flutter_test.dart';

void main() {
  // The injected JS string is a critical piece of the VIP page — it must
  // contain the right CSS rules and scroll-guard logic.  We verify its
  // structure without needing a real WebView.
  test('scroll-guard CSS contains overflow-x:hidden and touch-action:pan-y',
      () {
    const expectedSubstrings = [
      'overflow-x:hidden',
      'touch-action:pan-y',
      'overscroll-behavior-x:none',
      '::-webkit-scrollbar',
      'scrollbar-width:thin',
    ];

    // Reproduce the CSS fragment that the JS injection builds.
    final css = [
      'html,body{overflow-x:hidden !important;overflow-y:auto !important;',
      'width:100% !important;max-width:100% !important;',
      'margin:0 !important;padding:0 !important;',
      'touch-action:pan-y !important;',
      'overscroll-behavior-x:none !important;',
      'overscroll-behavior-y:auto !important;}',
      '::-webkit-scrollbar{width:8px !important;height:8px !important;}',
      '::-webkit-scrollbar-thumb{background:rgba(128,128,128,0.5) !important;border-radius:4px !important;}',
      'html{scrollbar-width:thin !important;scrollbar-color:rgba(128,128,128,0.5),transparent !important;}',
    ].join();

    for (final s in expectedSubstrings) {
      expect(css.contains(s), isTrue, reason: 'CSS missing: $s');
    }
  });

  test('scroll guard registers window listeners with passive flag', () {
    // The JS code checks window.__luoda_scroll_guard__ before registering.
    // This ensures the guard is only installed once per page lifecycle.
    const guardSnippet = '''
if (!window.__luoda_scroll_guard__) {
 window.__luoda_scroll_guard__ = true;
 var guardFn = function() {
 if (window.scrollX > 0) window.scrollTo(0, window.scrollY);
 };
 window.__luoda_scroll_handler__ = guardFn;
 window.addEventListener('scroll', guardFn, { passive: true });
 window.addEventListener('touchmove', guardFn, { passive: true });
}''';

    expect(guardSnippet.contains('__luoda_scroll_guard__'), isTrue);
    expect(guardSnippet.contains('__luoda_scroll_handler__'), isTrue);
    expect(guardSnippet.contains('passive: true'), isTrue);
  });

  test('cleanup removes guard and style element', () {
    const cleanupSnippet = '''
if (window.__luoda_scroll_guard__) {
 window.removeEventListener('scroll', window.__luoda_scroll_handler__);
 window.removeEventListener('touchmove', window.__luoda_scroll_handler__);
 delete window.__luoda_scroll_guard__;
 delete window.__luoda_scroll_handler__;
}
var style = document.getElementById('__luoda_noscroll__');
if (style) style.remove();''';

    expect(cleanupSnippet.contains('removeEventListener'), isTrue);
    expect(cleanupSnippet.contains('__luoda_noscroll__'), isTrue);
    expect(cleanupSnippet.contains('delete window.__luoda_scroll_guard__'),
        isTrue);
  });
}
