package com.bdk.f.bdk_flutter_app

import android.content.Context
import android.content.Intent
import android.nfc.NdefRecord
import android.nfc.NfcAdapter
import android.nfc.Tag
import android.nfc.tech.Ndef
import android.os.Build
import android.os.Bundle
import android.os.VibrationEffect
import android.os.Vibrator
import android.provider.Settings
import android.widget.Toast
import io.flutter.embedding.android.FlutterActivity
import java.util.Arrays
import io.flutter.plugin.common.MethodChannel

class NfcReader(private val context: Context, private val channel: MethodChannel) : NfcAdapter.ReaderCallback {

    private var mNfcAdapter: NfcAdapter? = null

    fun startNfcReading() {
        mNfcAdapter = NfcAdapter.getDefaultAdapter(context)
        if (mNfcAdapter != null) {
            if (!mNfcAdapter!!.isEnabled) {
                showWirelessSettings()
                return
            }
            val options = Bundle()
            options.putInt(NfcAdapter.EXTRA_READER_PRESENCE_CHECK_DELAY, 250)
            mNfcAdapter!!.enableReaderMode(
                context as FlutterActivity,
                this,
                NfcAdapter.FLAG_READER_NFC_A or
                        NfcAdapter.FLAG_READER_NFC_B or
                        NfcAdapter.FLAG_READER_NFC_F or
                        NfcAdapter.FLAG_READER_NFC_V or
                        NfcAdapter.FLAG_READER_NFC_BARCODE or
                        NfcAdapter.FLAG_READER_NO_PLATFORM_SOUNDS,
                options
            )
        }
    }

    override fun onTagDiscovered(tag: Tag?) {
        println("NFC tag discovered")
        val mNdef = Ndef.get(tag)
        if (mNdef != null) {
            val mNdefMessage = mNdef.cachedNdefMessage
            val record = mNdefMessage.records
            val ndefRecordsCount = record.size
            if (ndefRecordsCount > 0) {
                var ndefText = ""
                for (i in 0 until ndefRecordsCount) {
                    val ndefTnf = record[i].tnf
                    val ndefType = record[i].type
                    val ndefPayload = record[i].payload
                    if (ndefTnf == NdefRecord.TNF_WELL_KNOWN &&
                        Arrays.equals(ndefType, NdefRecord.RTD_TEXT)
                    ) {
                        ndefText += "\nrec: $i Well known Text payload\n${String(ndefPayload)} \n"
                        ndefText += Utils.parseTextrecordPayload(ndefPayload) + " \n"
                    }
                    if (ndefTnf == NdefRecord.TNF_WELL_KNOWN &&
                        Arrays.equals(ndefType, NdefRecord.RTD_URI)
                    ) {
                        ndefText += "\nrec: $i Well known Uri payload\n${String(ndefPayload)} \n"
                        ndefText += Utils.parseUrirecordPayload(ndefPayload) + " \n"
                    }
                    if (ndefTnf == NdefRecord.TNF_MIME_MEDIA) {
                        ndefText += "\nrec: $i TNF Mime Media payload\n${String(ndefPayload)} \n"
                        ndefText += "TNF Mime Media type\n${String(ndefType)} \n"
                    }
                    if (ndefTnf == NdefRecord.TNF_EXTERNAL_TYPE) {
                        ndefText += "\nrec: $i TNF External type payload\n${String(ndefPayload)} \n"
                        ndefText += "TNF External type type\n${String(ndefType)} \n"
                    }
                }
                channel.invokeMethod("onNfcRead", ndefText)
            } else {
                channel.invokeMethod("onNfcReadError", "No NDEF records found")
            }
        } else {
            channel.invokeMethod("onNfcReadError", "There was an error in NDEF data")
        }
        doVibrate()
    }

    private fun doVibrate() {
        val vibrator = context.getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            vibrator.vibrate(VibrationEffect.createOneShot(150, 10))
        } else {
            vibrator.vibrate(200)
        }
    }

    private fun showWirelessSettings() {
        Toast.makeText(context, "You need to enable NFC", Toast.LENGTH_SHORT).show()
        val intent = Intent(Settings.ACTION_WIRELESS_SETTINGS)
        context.startActivity(intent)
    }
}
