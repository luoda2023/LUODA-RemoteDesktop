import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:luoda_flutter/utils/image.dart';

void main() {
  test('decodeImageFromPixels returns null for zero-size buffer', () async {
    final result = await decodeImageFromPixels(
      Uint8List(0),
      0,
      0,
      ui.PixelFormat.rgba8888,
    );
    expect(result, isNull);
  });

  test('decodeImageFromPixels throws assertion when not allowing upscaling',
      () async {
    final pixels = Uint8List.fromList([255, 0, 0, 255]);
    expect(
      () => decodeImageFromPixels(
        pixels,
        1,
        1,
        ui.PixelFormat.rgba8888,
        targetWidth: 10,
        allowUpscaling: false,
      ),
      throwsA(isA<AssertionError>()),
    );
  });

  test('decodeImageFromPixels decodes a valid 1x1 image', () async {
    final pixels = Uint8List.fromList([255, 0, 0, 255]);
    final result = await decodeImageFromPixels(
      pixels,
      1,
      1,
      ui.PixelFormat.rgba8888,
    );
    expect(result, isNotNull);
    expect(result!.width, 1);
    expect(result.height, 1);
  });

  test('ImagePainter shouldRepaint returns true for different instances', () {
    final painter1 = ImagePainter(image: null, x: 0, y: 0, scale: 1.0);
    final painter2 = ImagePainter(image: null, x: 1, y: 1, scale: 2.0);
    expect(painter2.shouldRepaint(painter1), isTrue);
  });
}
