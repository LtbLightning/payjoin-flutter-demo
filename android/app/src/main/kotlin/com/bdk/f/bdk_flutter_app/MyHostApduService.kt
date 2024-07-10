package com.bdk.f.bdk_flutter_app

import android.content.Intent
import android.nfc.NdefMessage
import android.nfc.NdefRecord
import android.nfc.cardemulation.HostApduService
import android.os.Build
import android.os.Bundle
import android.util.Log
import java.util.Arrays

/**
 * This class emulates a NFC Forum Tag Type 4 containing a NDEF message
 * The class uses the AID D2760000850101
 */
class MyHostApduService : HostApduService() {
    private lateinit var mNdefRecordFile: ByteArray
  
    override fun onCreate() {
        super.onCreate()
        mAppSelected = false
        mCcSelected = false
        mNdefSelected = false
        createDefaultMessage()
    }

    private fun createDefaultMessage() {
        val ndefDefaultMessage = createNdefMessage(DEFAULT_MESSAGE,"text/plain", NDEF_ID)
        // the maximum length is 246
        val ndefLen = ndefDefaultMessage!!.byteArrayLength
        mNdefRecordFile = ByteArray(ndefLen + 2)
        mNdefRecordFile[0] = ((ndefLen and 0xff00) / 256).toByte()
        mNdefRecordFile[1] = (ndefLen and 0xff).toByte()
        System.arraycopy(
            ndefDefaultMessage.toByteArray(),
            0,
            mNdefRecordFile,
            2,
            ndefDefaultMessage.byteArrayLength
        )
    }

    override fun onStartCommand(intent: Intent, flags: Int, startId: Int): Int {
        if (intent != null) {
            // intent contains a text message
            if (intent.hasExtra("ndefMessage")) {
                val ndef = intent.getStringExtra("ndefMessage")
             //   val ndefMessage = createNdefMessage(intent.getStringExtra("ndefMessage"))
                if (ndef != null) {
                    val ndefMessage = createNdefMessage(ndef, "text/plain", NDEF_ID)

                    val ndefLen = ndefMessage.byteArrayLength
                    mNdefRecordFile = ByteArray(ndefLen + 2)
                    mNdefRecordFile[0] = ((ndefLen and 0xff00) / 256).toByte()
                    mNdefRecordFile[1] = (ndefLen and 0xff).toByte()
                    System.arraycopy(
                        ndefMessage.toByteArray(),
                        0,
                        mNdefRecordFile,
                        2,
                        ndefMessage.byteArrayLength
                    )
                }
            }
        }
        return super.onStartCommand(intent, flags, startId)
    }

/*     private fun createNdefMessage(ndefData: String?): NdefMessage? {
        if (ndefData!!.isEmpty()) {
            return null
        }
        var ndefRecord: NdefRecord? = null
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            ndefRecord = NdefRecord.createTextRecord("en", ndefData)
        }
        return NdefMessage(ndefRecord)
    } */

    private fun createNdefMessage(content: String, mimeType: String, id: ByteArray): NdefMessage {
        Log.i(TAG, "createNdefMessage(): $content")

        if(mimeType == "text/plain") {
            return createTextRecord("en", content, id);
        }

        val type = mimeType.toByteArray(charset("US-ASCII"))
        val payload = content.toByteArray(charset("UTF-8"))

        return  NdefMessage(NdefRecord(NdefRecord.TNF_MIME_MEDIA, type, id, payload))
    }

    private fun createTextRecord(language: String, text: String, id: ByteArray): NdefMessage {
        val languageBytes: ByteArray
        val textBytes: ByteArray
        try {
            languageBytes = language.toByteArray(charset("US-ASCII"))
            textBytes = text.toByteArray(charset("UTF-8"))
        } catch (e: Error) {
            throw AssertionError(e)
        }

        val recordPayload = ByteArray(1 + (languageBytes.size and 0x03F) + textBytes.size)

        recordPayload[0] = (languageBytes.size and 0x03F).toByte()
        System.arraycopy(languageBytes, 0, recordPayload, 1, languageBytes.size and 0x03F)
        System.arraycopy(
            textBytes,
            0,
            recordPayload,
            1 + (languageBytes.size and 0x03F),
            textBytes.size,
        )

        return  NdefMessage(NdefRecord(NdefRecord.TNF_WELL_KNOWN, NdefRecord.RTD_TEXT, id, recordPayload))
    }

    /**
     * emulates an NFC Forum Tag Type 4
     */
    override fun processCommandApdu(commandApdu: ByteArray, extras: Bundle?): ByteArray {
        if (extras == null) {
            Log.d(TAG, "Received null extras in processCommandApdu")
            // Handle the case where extras is null if necessary
        }
        Log.d(TAG, "commandApdu: " + Utils.bytesToHex(commandApdu))
        //if (Arrays.equals(SELECT_APP, commandApdu)) {
        // check if commandApdu qualifies for SELECT_APPLICATION
        if (SELECT_APPLICATION.contentEquals(commandApdu)) {
            mAppSelected = true
            mCcSelected = false
            mNdefSelected = false
            Log.d(TAG, "responseApdu: " + Utils.bytesToHex(SUCCESS_SW))
            return SUCCESS_SW
            // check if commandApdu qualifies for SELECT_CAPABILITY_CONTAINER
        } else if (mAppSelected && SELECT_CAPABILITY_CONTAINER.contentEquals(commandApdu)) {
            mCcSelected = true
            mNdefSelected = false
            Log.d(TAG, "responseApdu: " + Utils.bytesToHex(SUCCESS_SW))
            return SUCCESS_SW
            // check if commandApdu qualifies for SELECT_NDEF_FILE
        } else if (mAppSelected && SELECT_NDEF_FILE.contentEquals(commandApdu)) {
            // NDEF
            mCcSelected = false
            mNdefSelected = true
            Log.d(TAG, "responseApdu: " + Utils.bytesToHex(SUCCESS_SW))
            return SUCCESS_SW
            // check if commandApdu qualifies for // READ_BINARY
        } else if (commandApdu[0] == 0x00.toByte() && commandApdu[1] == 0xb0.toByte()) {
            // READ_BINARY
            // get the offset an le (length) data
            //System.out.println("** " + Utils.bytesToHex(commandApdu) + " in else if (commandApdu[0] == (byte)0x00 && commandApdu[1] == (byte)0xb0) {");
            val offset =
                (0x00ff and commandApdu[2].toInt()) * 256 + (0x00ff and commandApdu[3].toInt())
            val le = 0x00ff and commandApdu[4].toInt()
            val responseApdu = ByteArray(le + SUCCESS_SW.size)
            if (mCcSelected && offset == 0 && le == CAPABILITY_CONTAINER_FILE.size) {
                System.arraycopy(CAPABILITY_CONTAINER_FILE, offset, responseApdu, 0, le)
                System.arraycopy(SUCCESS_SW, 0, responseApdu, le, SUCCESS_SW.size)
                Log.d(TAG, "responseApdu: " + Utils.bytesToHex(responseApdu))
                return responseApdu
            } else if (mNdefSelected) {
                if (offset + le <= mNdefRecordFile.size) {
                    System.arraycopy(mNdefRecordFile, offset, responseApdu, 0, le)
                    System.arraycopy(SUCCESS_SW, 0, responseApdu, le, SUCCESS_SW.size)
                    Log.d(TAG, "responseApdu: " + Utils.bytesToHex(responseApdu))
                    return responseApdu
                }
            }
        }

        // The tag should return different errors for different reasons
        // this emulation just returns the general error message
        Log.d(TAG, "responseApdu: " + Utils.bytesToHex(FAILURE_SW))
        return FAILURE_SW
    }

    /**
     * onDeactivated is called when reading ends
     * reset the status boolean values
     */
    override fun onDeactivated(reason: Int) {
        mAppSelected = false
        mCcSelected = false
        mNdefSelected = false
        Log.i(TAG, "onDeactivated() Reason: $reason")

    }

    companion object {
        private const val TAG = "MyHostApduService"
        const val DEFAULT_MESSAGE = "This is the default message."
        private var mAppSelected = false // true when SELECT_APPLICATION detected
        private var mCcSelected = false // true when SELECT_CAPABILITY_CONTAINER detected
        private var mNdefSelected = false // true when SELECT_NDEF_FILE detected
        private val NDEF_ID = byteArrayOf(0xE1.toByte(), 0x04.toByte())

        private val SELECT_APPLICATION = byteArrayOf(
            0x00.toByte(),
            0xA4.toByte(),
            0x04.toByte(),
            0x00.toByte(),
            0x07.toByte(),
            0xD2.toByte(),
            0x76.toByte(),
            0x00.toByte(),
            0x00.toByte(),
            0x85.toByte(),
            0x01.toByte(),
            0x01.toByte(),
            0x00.toByte()
        )
        private val SELECT_CAPABILITY_CONTAINER = byteArrayOf(
            0x00.toByte(),
            0xa4.toByte(),
            0x00.toByte(),
            0x0c.toByte(),
            0x02.toByte(),
            0xe1.toByte(),
            0x03.toByte()
        )
        private val SELECT_NDEF_FILE = byteArrayOf(
            0x00.toByte(),
            0xa4.toByte(),
            0x00.toByte(),
            0x0c.toByte(),
            0x02.toByte(),
            0xE1.toByte(),
            0x04.toByte()
        )
        private val CAPABILITY_CONTAINER_FILE = byteArrayOf(
            0x00,
            0x0f,  // CCLEN
            0x20,  // Mapping Version
            0x00,
            0x3b,  // Maximum R-APDU data size
            0x00,
            0x34,  // Maximum C-APDU data size
            0x04,
            0x06,
            0xe1.toByte(),
            0x04,
            0x00.toByte(),
            0xff.toByte(),  // Maximum NDEF size, do NOT extend this value
            0x00,
            0xff.toByte()
        )

        // Status Word success
        private val SUCCESS_SW = byteArrayOf(0x90.toByte(), 0x00.toByte())

        // Status Word failure
        private val FAILURE_SW = byteArrayOf(0x6a.toByte(), 0x82.toByte())
    }
}
