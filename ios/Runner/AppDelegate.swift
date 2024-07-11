import UIKit
import Flutter
import CoreNFC

@available(iOS 13.0, *)
@UIApplicationMain
@objc class AppDelegate: FlutterAppDelegate {
  private let CHANNEL = "flutter_hce"
    private var nfcReader: NFCTagReader?

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        let controller : FlutterViewController = window?.rootViewController as! FlutterViewController
        let nfcChannel = FlutterMethodChannel(name: CHANNEL, binaryMessenger: controller.binaryMessenger)
        nfcChannel.setMethodCallHandler({
            (call: FlutterMethodCall, result: @escaping FlutterResult) -> Void in
            if call.method == "readNfcMessage" {
                self.readNFCData(result: result)
            }else if call.method == "sendNfcMessage" {
                if let args = call.arguments as? [String: Any],
                let text = args["content"] as? String {
                self.sendNfcMessage(text: text, result: result)
                } else {
                    result(FlutterError(code: "INVALID_ARGUMENT", message: "Invalid argument for sendNfcMessage", details: nil))
                }
            }   else {
                result(FlutterMethodNotImplemented)
            }
        })
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    func readNFCData(result: @escaping FlutterResult) {
        nfcReader = NFCTagReader()
        nfcReader?.onNFCResult = { success, data in
            if success {
                result(data)
            } else {
                result(FlutterError(code: "NFC_READ_ERROR", message: "NFC read error", details: nil))
            }
        }
        nfcReader?.beginReadSession()
    }

    func sendNfcMessage(text: String, result: @escaping FlutterResult) {
        let payload = NFCNDEFPayload(format: .nfcWellKnown, type: Data("T".utf8), identifier: Data(), payload: Data(text.utf8))
        let message = NFCNDEFMessage(records: [payload])
        nfcReader = NFCTagReader()
        nfcReader?.onNFCResult = { success, data in
            if success {
                result(data)
            } else {
                result(FlutterError(code: "NFC_WRITE_ERROR", message: data, details: nil))
            }
        }
        nfcReader?.beginWriteSession(withMessage: message)
        }
}
