import CoreNFC

@available(iOS 13.0, *)
class NFCTagReader: NSObject, NFCNDEFReaderSessionDelegate {
    var nfcSession: NFCNDEFReaderSession?
    var onNFCResult: ((Bool, String) -> Void)?
    var writeMessage: NFCNDEFMessage?

    func beginReadSession() {
        nfcSession = NFCNDEFReaderSession(delegate: self, queue: nil, invalidateAfterFirstRead: true)
        nfcSession?.begin()
    }
    func beginWriteSession(withMessage message: NFCNDEFMessage) {
        writeMessage = message
        nfcSession = NFCNDEFReaderSession(delegate: self, queue: nil, invalidateAfterFirstRead: false)
        nfcSession?.alertMessage = "Hold your iPhone near the NFC tag to write the message."
        nfcSession?.begin()
    }
    func readerSession(_ session: NFCNDEFReaderSession, didDetectNDEFs messages: [NFCNDEFMessage]) {
        if let message = messages.first {
            let payload = message.records.first
            let payloadString = String(data: payload!.payload, encoding: .utf8) ?? ""
            onNFCResult?(true, payloadString)
        }
    }

    func readerSession(_ session: NFCNDEFReaderSession, didInvalidateWithError error: Error) {
        onNFCResult?(false, error.localizedDescription)
    }
     func readerSession(_ session: NFCNDEFReaderSession, didDetect tags: [NFCNDEFTag]) {
        guard let tag = tags.first, let message = writeMessage else {
            session.invalidate(errorMessage: "No tags found or no message to write.")
            return
        }

        session.connect(to: tag) { error in
            if let error = error {
                self.onNFCResult?(false, error.localizedDescription)
                session.invalidate(errorMessage: "Connection failed.")
                return
            }

            tag.queryNDEFStatus { status, capacity, error in
                if let error = error {
                    self.onNFCResult?(false, error.localizedDescription)
                    session.invalidate(errorMessage: "NDEF status query failed.")
                    return
                }

                guard status == .readWrite else {
                    self.onNFCResult?(false, "Tag is not writable.")
                    session.invalidate(errorMessage: "Tag is not writable.")
                    return
                }

                tag.writeNDEF(message) { error in
                    if let error = error {
                        self.onNFCResult?(false, error.localizedDescription)
                        session.invalidate(errorMessage: "Write failed.")
                    } else {
                        self.onNFCResult?(true, "Message written successfully.")
                        session.alertMessage = "Message written successfully."
                        session.invalidate()
                    }
                }
            }
        }
    }

   
  
}
