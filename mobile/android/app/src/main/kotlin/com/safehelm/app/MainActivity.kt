package com.safehelm.app

import android.app.Activity
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.media.AudioAttributes
import android.media.Ringtone
import android.media.RingtoneManager
import android.os.Build
import android.os.Bundle
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.telephony.SmsManager
import android.telephony.SubscriptionManager
import android.util.Log
import androidx.core.content.ContextCompat
import com.safehelm.app.db.AndroidSqliteDriver
import com.safehelm.app.db.DispatchDraft
import com.safehelm.app.db.DispatchStatus
import com.safehelm.app.db.EmergencyDbHelper
import com.safehelm.app.db.EmergencyJournal
import com.safehelm.app.db.IncidentRecord
import com.safehelm.app.db.IncidentState
import com.safehelm.app.db.IngestResult
import com.safehelm.app.db.LocationProvenance
import com.safehelm.app.db.TransitionResult
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    companion object {
        private const val TAG = "SafeHelmMMainActivity"
        const val ACTION_SMS_SENT = "com.safehelm.app.SMS_SENT"
        const val EXTRA_DISPATCH_ID = "extra_dispatch_id"
        const val EXTRA_INCIDENT_ID = "extra_incident_id"
        const val EXTRA_PHONE = "extra_phone"
        const val EXTRA_PART_INDEX = "extra_part_index"
        const val EXTRA_PARTS_TOTAL = "extra_parts_total"
    }

    private var ringtone: Ringtone? = null
    private var vibrator: Vibrator? = null

    // Native SQLite Emergency Journal
    private lateinit var dbHelper: EmergencyDbHelper
    private lateinit var journal: EmergencyJournal

    // Live SMS radio status stream to Flutter
    private var smsEventSink: EventChannel.EventSink? = null

    private val smsStatusReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action != ACTION_SMS_SENT) return
            val dispatchId = intent.getStringExtra(EXTRA_DISPATCH_ID) ?: return
            val incidentId = intent.getStringExtra(EXTRA_INCIDENT_ID) ?: return
            val phone = intent.getStringExtra(EXTRA_PHONE) ?: ""
            val partIndex = intent.getIntExtra(EXTRA_PART_INDEX, 0)
            val partsTotal = intent.getIntExtra(EXTRA_PARTS_TOTAL, 1)

            val code = resultCode
            val status = when (code) {
                Activity.RESULT_OK -> DispatchStatus.TRANSMITTED
                SmsManager.RESULT_ERROR_NO_SERVICE,
                SmsManager.RESULT_ERROR_RADIO_OFF -> DispatchStatus.QUEUED_OFFLINE
                else -> DispatchStatus.FAILED_TERMINAL
            }

            Log.i(TAG, "[SMS_CALLBACK] Dispatch $dispatchId (Part ${partIndex + 1}/$partsTotal): ResultCode=$code Status=$status")

            // Update persistent journal in SQLite
            try {
                journal.updateDispatchStatus(
                    dispatchId = dispatchId,
                    nextStatus = status,
                    radioResultCode = code,
                    partsConfirmedDelta = if (code == Activity.RESULT_OK) 1 else 0
                )
            } catch (e: Exception) {
                Log.e(TAG, "Failed to update journal on SMS callback", e)
            }

            // Stream live event to Flutter
            val eventPayload = mapOf(
                "dispatchId" to dispatchId,
                "incidentId" to incidentId,
                "phone" to phone,
                "partIndex" to partIndex,
                "partsTotal" to partsTotal,
                "resultCode" to code,
                "status" to status.name
            )
            runOnUiThread {
                smsEventSink?.success(eventPayload)
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Initialize SQLite Emergency Journal
        dbHelper = EmergencyDbHelper(applicationContext)
        val driver = AndroidSqliteDriver(dbHelper.writableDatabase)
        journal = EmergencyJournal(driver)
        journal.initSchema()

        // Register SMS BroadcastReceiver with Android 14+ RECEIVER_NOT_EXPORTED safety
        val filter = IntentFilter(ACTION_SMS_SENT)
        ContextCompat.registerReceiver(
            this,
            smsStatusReceiver,
            filter,
            ContextCompat.RECEIVER_NOT_EXPORTED
        )
    }

    override fun onDestroy() {
        try {
            unregisterReceiver(smsStatusReceiver)
        } catch (_: Exception) {}
        journal.close()
        stopAlarm()
        super.onDestroy()
    }

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

    private fun startAlarm() {
        try {
            if (ringtone == null) {
                var alertUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
                if (alertUri == null) {
                    alertUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
                }
                ringtone = RingtoneManager.getRingtone(applicationContext, alertUri)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                    ringtone?.audioAttributes = AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_ALARM)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build()
                }
            }
            if (ringtone?.isPlaying == false) {
                ringtone?.play()
            }

            if (vibrator == null) {
                vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    val vm = getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as? VibratorManager
                    vm?.defaultVibrator
                } else {
                    @Suppress("DEPRECATION")
                    getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
                }
            }

            val pattern = longArrayOf(0, 600, 200, 600, 200)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                vibrator?.vibrate(VibrationEffect.createWaveform(pattern, 0))
            } else {
                @Suppress("DEPRECATION")
                vibrator?.vibrate(pattern, 0)
            }
        } catch (_: Exception) {}
    }

    private fun stopAlarm() {
        try {
            ringtone?.stop()
            ringtone = null
            vibrator?.cancel()
        } catch (_: Exception) {}
    }

    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)

        // 1. SMS Channel with Tracked PendingIntents and Journal Persistence
        MethodChannel(engine.dartExecutor.binaryMessenger, "safehelm/sms").setMethodCallHandler { call, result ->
            if (call.method != "sendSms") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val phone = call.argument<String>("phone")
            val body = call.argument<String>("body")
            val incidentId = call.argument<String>("incidentId") ?: "SH-LOCAL-${System.currentTimeMillis()}"
            val contactName = call.argument<String>("contactName")

            if (phone.isNullOrBlank() || body.isNullOrBlank()) {
                result.error("INVALID", "Phone or body missing", null)
                return@setMethodCallHandler
            }

            try {
                val sms = getSmsManager()
                val parts = sms.divideMessage(body)
                val dispatchId = "${incidentId}_${phone.filter { it.isLetterOrDigit() }}"

                // Persist dispatch draft to SQLite before RIL handover
                journal.createDispatchRecords(
                    incidentId,
                    listOf(DispatchDraft(phone, contactName, body, parts.size))
                )

                // Create tracked PendingIntents for each part
                val sentIntents = ArrayList<PendingIntent>()
                for (i in 0 until parts.size) {
                    val sentIntent = Intent(ACTION_SMS_SENT).apply {
                        setPackage(packageName)
                        putExtra(EXTRA_DISPATCH_ID, dispatchId)
                        putExtra(EXTRA_INCIDENT_ID, incidentId)
                        putExtra(EXTRA_PHONE, phone)
                        putExtra(EXTRA_PART_INDEX, i)
                        putExtra(EXTRA_PARTS_TOTAL, parts.size)
                    }
                    val pi = PendingIntent.getBroadcast(
                        applicationContext,
                        (dispatchId.hashCode() + i),
                        sentIntent,
                        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                    )
                    sentIntents.add(pi)
                }

                if (parts.size > 1) {
                    sms.sendMultipartTextMessage(phone, null, parts, sentIntents, null)
                } else {
                    sms.sendTextMessage(phone, null, body, sentIntents[0], null)
                }

                journal.updateDispatchStatus(dispatchId, DispatchStatus.SUBMITTED_TO_RIL)

                result.success(
                    mapOf(
                        "accepted" to true,
                        "dispatchId" to dispatchId,
                        "incidentId" to incidentId,
                        "status" to "SUBMITTED_TO_RIL",
                        "parts" to parts.size
                    )
                )
            } catch (e: Exception) {
                Log.e(TAG, "sendSms exception: ${e.message}", e)
                result.error("SMS_FAILED", e.message, null)
            }
        }

        // 2. Live SMS Event Channel (Radio Callbacks)
        EventChannel(engine.dartExecutor.binaryMessenger, "safehelm/sms_events").setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    smsEventSink = events
                }

                override fun onCancel(arguments: Any?) {
                    smsEventSink = null
                }
            }
        )

        // 3. Native Emergency Journal Channel (Persistence, Ingestion, State Transitions)
        MethodChannel(engine.dartExecutor.binaryMessenger, "safehelm/journal").setMethodCallHandler { call, result ->
            when (call.method) {
                "ingestIncident" -> {
                    val id = call.argument<String>("incidentId") ?: ""
                    val type = call.argument<String>("eventType") ?: "ACCIDENT"
                    val triggerTime = call.argument<Long>("triggerTimestampMs") ?: System.currentTimeMillis()
                    val countdownDur = call.argument<Long>("countdownDurationMs") ?: 15_000L
                    val totalRecipients = call.argument<Int>("totalRecipients") ?: 0

                    val ingestRes = journal.ingestIncident(id, type, triggerTime, countdownDur, totalRecipients)
                    when (ingestRes) {
                        is IngestResult.Ingested -> {
                            result.success(
                                mapOf(
                                    "status" to "ingested",
                                    "incident" to incidentToMap(ingestRes.incident)
                                )
                            )
                        }
                        is IngestResult.DuplicateIgnored -> {
                            result.success(
                                mapOf(
                                    "status" to "duplicate_ignored",
                                    "incident" to incidentToMap(ingestRes.existingIncident)
                                )
                            )
                        }
                        is IngestResult.DatabaseError -> {
                            result.error("DB_ERROR", ingestRes.message, null)
                        }
                    }
                }

                "transitionState" -> {
                    val id = call.argument<String>("incidentId") ?: ""
                    val nextStateStr = call.argument<String>("nextState") ?: ""
                    val nextState = try { IncidentState.valueOf(nextStateStr) } catch (_: Exception) { null }

                    if (nextState == null) {
                        result.error("INVALID_STATE", "Unknown state $nextStateStr", null)
                        return@setMethodCallHandler
                    }

                    val transRes = journal.transitionState(id, null, nextState)
                    when (transRes) {
                        is TransitionResult.Success -> {
                            result.success(
                                mapOf(
                                    "success" to true,
                                    "state" to transRes.incident.state.name
                                )
                            )
                        }
                        is TransitionResult.NotFound -> {
                            result.error("NOT_FOUND", "Incident $id not found", null)
                        }
                        is TransitionResult.IllegalTransition -> {
                            result.error(
                                "ILLEGAL_TRANSITION",
                                "Cannot transition from ${transRes.currentState} to ${transRes.requestedState}",
                                null
                            )
                        }
                        is TransitionResult.DatabaseError -> {
                            result.error("DB_ERROR", transRes.message, null)
                        }
                    }
                }

                "updateLocation" -> {
                    val id = call.argument<String>("incidentId") ?: ""
                    val lat = call.argument<Double>("latitude")
                    val lon = call.argument<Double>("longitude")
                    val acc = call.argument<Double>("accuracy")?.toFloat()
                    val source = call.argument<String>("source") ?: "UNAVAILABLE"
                    val acqTime = call.argument<Long>("acquisitionTimeMs") ?: System.currentTimeMillis()

                    val ok = journal.updateLocation(
                        id,
                        LocationProvenance(lat, lon, acc, acqTime, source)
                    )
                    result.success(ok)
                }

                "getActiveIncidents" -> {
                    val active = journal.getActiveIncidents()
                    result.success(active.map { incidentToMap(it) })
                }

                "getAllIncidents" -> {
                    val all = journal.getAllIncidents()
                    result.success(all.map { incidentToMap(it) })
                }

                "getDispatches" -> {
                    val id = call.argument<String>("incidentId") ?: ""
                    val dispatches = journal.getDispatchesForIncident(id)
                    result.success(dispatches.map { dispatchToMap(it) })
                }

                else -> result.notImplemented()
            }
        }

        // 4. Platform Channel (SDK version)
        MethodChannel(engine.dartExecutor.binaryMessenger, "safehelm/platform").setMethodCallHandler { call, result ->
            if (call.method == "getSdkInt") {
                result.success(Build.VERSION.SDK_INT)
            } else {
                result.notImplemented()
            }
        }

        // 5. Foreground Service Channel
        MethodChannel(engine.dartExecutor.binaryMessenger, "safehelm/service").setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    val text = call.argument<String>("status") ?: "SafeHelm Active — Monitoring Helmet Connection"
                    SafeHelmForegroundService.start(applicationContext, text)
                    result.success(true)
                }
                "update" -> {
                    val text = call.argument<String>("status") ?: "SafeHelm Active"
                    SafeHelmForegroundService.update(applicationContext, text)
                    result.success(true)
                }
                "stop" -> {
                    SafeHelmForegroundService.stop(applicationContext)
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        // 6. Emergency Alarm & Siren Channel
        MethodChannel(engine.dartExecutor.binaryMessenger, "safehelm/alarm").setMethodCallHandler { call, result ->
            when (call.method) {
                "startAlarm" -> {
                    startAlarm()
                    result.success(true)
                }
                "stopAlarm" -> {
                    stopAlarm()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun incidentToMap(r: IncidentRecord): Map<String, Any?> = mapOf(
        "incidentId" to r.incidentId,
        "eventType" to r.eventType,
        "state" to r.state.name,
        "triggerTimestampMs" to r.triggerTimestampMs,
        "countdownDurationMs" to r.countdownDurationMs,
        "cancelledTimestampMs" to r.cancelledTimestampMs,
        "latitude" to r.location.latitude,
        "longitude" to r.location.longitude,
        "locationAccuracy" to r.location.accuracyMeters,
        "locationTimestampMs" to r.location.acquisitionTimeMs,
        "locationSource" to r.location.source,
        "totalRecipients" to r.totalRecipients,
        "successfulRecipients" to r.successfulRecipients,
        "createdAtMs" to r.createdAtMs,
        "updatedAtMs" to r.updatedAtMs
    )

    private fun dispatchToMap(d: com.safehelm.app.db.DispatchRecord): Map<String, Any?> = mapOf(
        "dispatchId" to d.dispatchId,
        "incidentId" to d.incidentId,
        "recipientPhone" to d.recipientPhone,
        "recipientName" to d.recipientName,
        "messageBody" to d.messageBody,
        "status" to d.status.name,
        "radioResultCode" to d.radioResultCode,
        "retryCount" to d.retryCount,
        "lastAttemptMs" to d.lastAttemptMs,
        "partsTotal" to d.partsTotal,
        "partsConfirmed" to d.partsConfirmed,
        "createdAtMs" to d.createdAtMs,
        "updatedAtMs" to d.updatedAtMs
    )
}