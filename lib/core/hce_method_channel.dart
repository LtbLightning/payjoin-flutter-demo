import 'package:bdk_flutter_demo/core/hce_platform.dart';
import 'package:flutter/services.dart';

/// An implementation of [HcePlatform] that uses method channels to communicate with the native platform.
class HceMethodChannel extends HcePlatform {
  /// The method channel used to interact with the native platform.
  static const MethodChannel _methodChannel = MethodChannel('flutter_hce');

  /// Retrieves the platform version from the native side.
  @override
  Future<String?> getPlatformVersion() async {
    return await _methodChannel.invokeMethod<String>('getPlatformVersion');
  }

  /// Sends an NFC HCE session with the given parameters.
  @override
  Future<String?> sendNfcMessage(String content) async {
    return await _methodChannel.invokeMethod<String>(
      'sendNfcMessage',
      {"content": content},
    );
  }

  @override
  Future<String?> readNfcMessage() async {
    
    String? result= await _methodChannel.invokeMethod<String>('readNfcMessage');
    return result;
  }

  /// Stops the ongoing NFC HCE session.
  @override
  Future<String?> stopNfcHce() async {
    return await _methodChannel.invokeMethod<String>('stopNfcHce');
  }

  /// Checks if NFC HCE is supported by the platform.
  @override
  Future<String?> isNfcHceSupported() async {
    return await _methodChannel.invokeMethod<String>('isNfcHceSupported');
  }

  /// Checks if Secure NFC is enabled on the device.
  @override
  Future<String?> isSecureNfcEnabled() async {
    return await _methodChannel.invokeMethod<String>('isSecureNfcEnabled');
  }

  /// Checks if NFC is enabled on the device.
  @override
  Future<String?> isNfcEnabled() async {
    return await _methodChannel.invokeMethod<String>('isNfcEnabled');
  }
}
