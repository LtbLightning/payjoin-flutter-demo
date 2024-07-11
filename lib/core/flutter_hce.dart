import 'package:bdk_flutter_demo/core/hce_platform.dart';

class FlutterHce {
  final HcePlatform _platform = HcePlatform.instance;

  /// Retrieves the platform version from the native platform.
  Future<String?> getPlatformVersion() => _platform.getPlatformVersion();

  /// Sends the NFC host card emulation with the specified content.
  /// [content]: The content to transmit via NFC.
  Future<String?> sendNfcMessage(String content) {
    return _platform.sendNfcMessage(content);
  }
  Future<String?> readNfcMessage() {
    return _platform.readNfcMessage();
  }

  /// Stops the NFC host card emulation and deletes the saved text file with the NFC message from internal storage.
  Future<void> stopNfcHce() => _platform.stopNfcHce();

  /// Checks if NFC HCE is supported by the platform.
  Future<bool> isNfcHceSupported() async {
    return await _platform.isNfcHceSupported() == 'true';
  }

  /// Checks if secure NFC functionality is enabled. This function always returns false for SDKs below Android 10 (API level 29).
  Future<bool> isSecureNfcEnabled() async {
    return await _platform.isSecureNfcEnabled() == 'true';
  }

  /// Determines whether NFC is enabled on the device.
  Future<bool> isNfcEnabled() async {
    return await _platform.isNfcEnabled() == 'true';
  }
}
