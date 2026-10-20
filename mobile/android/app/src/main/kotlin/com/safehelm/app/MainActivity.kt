package com.safehelm.app

import android.content.Context
import android.os.Build
import android.telephony.SmsManager
import android.telephony.SubscriptionManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
  private fun getSmsManager(): SmsManager {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP_MR1) {
      var subId = SubscriptionManager.getDefaultSmsSubscriptionId()
      if (subId == SubscriptionManager.INVALID_SUBSCRIPTION_ID && Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
        subId = SubscriptionManager.getDefaultDataSubscriptionId()
      }
      if (subId == SubscriptionManager.INVALID_SUBSCRIPTION_ID) {
        val sm = getSystemService(Context.TELEPHONY_SUBSCRIPTION_SERVICE) as? SubscriptionManager
        val activeList = try { sm?.activeSubscriptionInfoList } catch (_: SecurityException) { null }
        if (!activeList.isNullOrEmpty()) {
          subId = activeList[0].subscriptionId
        }
      }
      if (subId != SubscriptionManager.INVALID_SUBSCRIPTION_ID) {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
          getSystemService(SmsManager::class.java).createForSubscriptionId(subId)
        } else {
          @Suppress("DEPRECATION")
          SmsManager.getSmsManagerForSubscriptionId(subId)
        }
      }
    }
    return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
      getSystemService(SmsManager::class.java) ?: @Suppress("DEPRECATION") SmsManager.getDefault()
    } else {
      @Suppress("DEPRECATION")
      SmsManager.getDefault()
    }
  }

  override fun configureFlutterEngine(engine: FlutterEngine) {
    super.configureFlutterEngine(engine)
    MethodChannel(engine.dartExecutor.binaryMessenger, "safehelm/sms").setMethodCallHandler { call, result ->
      if (call.method != "sendSms") { result.notImplemented(); return@setMethodCallHandler }
      val phone = call.argument<String>("phone"); val body = call.argument<String>("body")
      if (phone.isNullOrBlank() || body.isNullOrBlank()) { result.error("INVALID", "Phone or body missing", null); return@setMethodCallHandler }
      try {
        val sms = getSmsManager()
        val parts = sms.divideMessage(body)
        if (parts.size > 1) {
          sms.sendMultipartTextMessage(phone, null, parts, null, null)
        } else {
          sms.sendTextMessage(phone, null, body, null, null)
        }
        result.success(true)
      } catch (e: Exception) {
        result.error("SMS_FAILED", e.message, null)
      }
    }
    MethodChannel(engine.dartExecutor.binaryMessenger, "safehelm/platform").setMethodCallHandler { call, result ->
      if (call.method == "getSdkInt") {
        result.success(Build.VERSION.SDK_INT)
      } else {
        result.notImplemented()
      }
    }
  }
}