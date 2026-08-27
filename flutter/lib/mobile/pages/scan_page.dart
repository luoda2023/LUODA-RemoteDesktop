import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:qr_code_scanner/qr_code_scanner.dart';
import 'package:zxing2/qrcode.dart';

import '../../common.dart';
import '../../models/platform_model.dart';
import '../widgets/dialog.dart';

class ScanPage extends StatefulWidget {
  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage> {
  QRViewController? controller;
  final GlobalKey qrKey = GlobalKey(debugLabel: 'QR');
  StreamSubscription? scanSubscription;

  @override
  void reassemble() {
    super.reassemble();
    if (isAndroid && controller != null) {
      controller!.pauseCamera();
    } else if (controller != null) {
      controller!.resumeCamera();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(translate('Scan QR')),
        actions: [
          _buildImagePickerButton(),
          _buildFlashToggleButton(),
          _buildCameraSwitchButton(),
        ],
      ),
      body: _buildQrView(context),
    );
  }

  Widget _buildQrView(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final minSide = size.width < size.height ? size.width : size.height;
    var scanArea = (minSide < 400 ? 150.0 : 300.0) * 1.5;
    // Enlarged by 1/2, but keep it inside the screen on narrow devices.
    if (scanArea > minSide * 0.9) {
      scanArea = minSide * 0.9;
    }
    return QRView(
      key: qrKey,
      onQRViewCreated: _onQRViewCreated,
      overlay: QrScannerOverlayShape(
        borderColor: Colors.red,
        borderRadius: 10,
        borderLength: 30,
        borderWidth: 10,
        cutOutSize: scanArea,
      ),
      onPermissionSet: (ctrl, p) => _onPermissionSet(context, ctrl, p),
    );
  }

 void _onQRViewCreated(QRViewController controller) {
 setState(() {
 this.controller = controller;
 });
 scanSubscription = controller.scannedDataStream.listen((scanData) {
 if (scanData.code != null) {
 _handleQrCode(scanData.code!);
 }
 });
 }

 /// Dispatch a scanned code: if it looks like a connect QR (--connect),
 /// initiate a direct connection; otherwise fall back to server config.
 void _handleQrCode(String code) async {
 await controller?.pauseCamera();
 // Connect QR: "luoda://--connect <id> --password <pwd>" or "--connect <id> --password <pwd>"
 final uriPrefix = bind.mainUriPrefixSync();
 String raw = code;
 if (raw.startsWith(uriPrefix)) {
 raw = raw.substring(uriPrefix.length);
 }
 if (raw.contains('--connect')) {
 _parseAndConnect(raw);
 return;
 }
 // URI link with full prefix (e.g. deep link)
 if (code.startsWith(uriPrefix)) {
 Navigator.of(context).pop();
 handleUriLink(uriString: code);
 return;
 }
 // Fall back to server config QR
 showServerSettingFromQr(code);
 }

 void _parseAndConnect(String raw) async {
 final parts = raw.split(RegExp(r'\s+'));
 String? id;
 String? password;
 for (int i = 0; i < parts.length; i++) {
 if (parts[i] == '--connect' && i + 1 < parts.length) {
 id = parts[i + 1];
 i++;
 } else if (parts[i] == '--password' && i + 1 < parts.length) {
 password = parts[i + 1];
 i++;
 }
 }
 if (id != null && id.isNotEmpty) {
 Navigator.of(context).pop();
 connect(context, id, password: password);
 } else {
 showToast(translate('Invalid QR code'));
 }
 }

  void _onPermissionSet(BuildContext context, QRViewController ctrl, bool p) {
    if (!p) {
      showToast(translate('No permission'));
    }
  }

  Future<void> _pickImage() async {
    final ImagePicker picker = ImagePicker();
    final XFile? file = await picker.pickImage(source: ImageSource.gallery);
    if (file != null) {
      try {
        var image = img.decodeImage(await File(file.path).readAsBytes())!;
        LuminanceSource source = RGBLuminanceSource(
          image.width,
          image.height,
          image.getBytes(order: img.ChannelOrder.abgr).buffer.asInt32List(),
        );
        var bitmap = BinaryBitmap(HybridBinarizer(source));

var reader = QRCodeReader();
var result = reader.decode(bitmap);
_handleQrCode(result.text);
      } catch (e) {
        showToast(translate('No QR code found'));
      }
    }
  }

  Widget _buildImagePickerButton() {
    return IconButton(
      color: Colors.white,
      icon: Icon(Icons.image_search),
      iconSize: 32.0,
      onPressed: _pickImage,
    );
  }

  Widget _buildFlashToggleButton() {
    return IconButton(
      color: Colors.yellow,
      icon: Icon(Icons.flash_on),
      iconSize: 32.0,
      onPressed: () async {
        await controller?.toggleFlash();
      },
    );
  }

  Widget _buildCameraSwitchButton() {
    return IconButton(
      color: Colors.white,
      icon: Icon(Icons.switch_camera),
      iconSize: 32.0,
      onPressed: () async {
        await controller?.flipCamera();
      },
    );
  }

  @override
  void dispose() {
    scanSubscription?.cancel();
    controller?.dispose();
    super.dispose();
  }

  void showServerSettingFromQr(String data) async {
    closeConnection();
    await controller?.pauseCamera();
    if (!data.startsWith('config=')) {
      showToast(translate('Invalid QR code'));
      return;
    }
    try {
      final sc = ServerConfig.decode(data.substring(7));
      Timer(Duration(milliseconds: 60), () {
        showServerSettingsWithValue(sc, gFFI.dialogManager, null);
      });
    } catch (e) {
      showToast(translate('Invalid QR code'));
    }
  }
}
