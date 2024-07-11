package com.bdk.f.bdk_flutter_app

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.nfc.NdefMessage
import android.nfc.NdefRecord
import android.nfc.NfcAdapter
import io.flutter.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.Calendar
import java.util.Timer
import java.util.TimerTask


class MainActivity : FlutterActivity() {
    private val CHANNEL = "flutter_hce"
    private var nfcAdapter: NfcAdapter? = null
    private var pendingIntent: PendingIntent? = null
    private val TAG = "MainActivity"
    private lateinit var nfcReader: NfcReader

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        nfcReader = NfcReader(this, methodChannel) // Pass context and channel

        methodChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "sendNfcMessage" -> {
                    val dataToSend = call.argument<String>("content")
                    dataToSend?.let { sendNFCMessage(it) }
                    result.success(null)
                }
               "readNfcMessage" -> {
                    nfcReader.startNfcReading()
                    result.success(null)
                }
                "isNfcEnabled" -> {
                    if (isNfcEnabled()) {
                        result.success("true")
                    } else {
                        result.success("false")
                    }
                }
                "isNfcHceSupported" -> {
                    if (isNfcHceSupported()) {
                        result.success("true")
                    } else {
                        result.success("false")
                    }
                }
                "stopNfcHce" -> {
                    stopNfcHce()
                    result.success("success")
                }
                else -> result.notImplemented()
            }
        }
   }

    override fun onResume() {
        super.onResume()
    }

    override fun onPause() {
        super.onPause()
    }

    private fun sendNFCMessage(text: String) {
        Log.d(TAG, "message to send: $text")
        val intent = Intent(context, MyHostApduService::class.java)
        intent.putExtra("ndefMessage", text);
        context.startService(intent)

    }

    private fun isNfcEnabled(): Boolean {
        return nfcAdapter?.isEnabled == true
    }
    private fun isNfcHceSupported() =
    isNfcEnabled() && activity?.packageManager!!.hasSystemFeature(PackageManager.FEATURE_NFC_HOST_CARD_EMULATION)

    private fun stopNfcHce() {
      val intent = Intent(activity, MyHostApduService::class.java)
     //   activity?.stopService(intent)
    }
}
