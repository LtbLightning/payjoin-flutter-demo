
import 'package:bdk_flutter_demo/core/hce_method_channel.dart';

abstract class HcePlatform {
  /// Constructs a HcePlatform.
  HcePlatform() : super();

  static HcePlatform instance = HceMethodChannel();

  /// Gets the platform version.
  Future<String?> getPlatformVersion() {
    throw UnimplementedError('getPlatformVersion() has not been implemented.');
  }

  /// Sends NFC HCE (Host Card Emulation) with the given content.
  Future<String?> sendNfcMessage(String content) {
    throw UnimplementedError('startNfcHce() has not been implemented.');
  }

  Future<String?> readNfcMessage() {
    throw UnimplementedError('readNfcMessage() has not been implemented.');
  }

  /// Stops the NFC HCE session.
  Future<String?> stopNfcHce() {
    throw UnimplementedError('stopNfcHce() has not been implemented.');
  }

  /// Checks if NFC HCE is supported on the platform.
  Future<String?> isNfcHceSupported() {
    throw UnimplementedError('isNfcHceSupported() has not been implemented.');
  }

  /// Checks if Secure NFC is enabled.
  Future<String?> isSecureNfcEnabled() {
    throw UnimplementedError('isSecureNfcEnabled() has not been implemented.');
  }

  /// Checks if NFC is enabled.
  Future<String?> isNfcEnabled() {
    throw UnimplementedError('isNfcEnabled() has not been implemented.');
  }
}
