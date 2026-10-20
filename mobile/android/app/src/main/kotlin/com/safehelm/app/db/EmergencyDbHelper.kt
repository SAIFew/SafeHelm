package com.safehelm.app.db

import android.content.Context
import android.database.DatabaseErrorHandler
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import android.util.Log
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream

/**
 * SQLiteOpenHelper for SafeHelm emergency incidents and dispatches.
 * Configured with Write-Ahead Logging (WAL) and safe corruption recovery.
 */
class EmergencyDbHelper(
    context: Context,
    dbName: String = DATABASE_NAME
) : SQLiteOpenHelper(
    context,
    dbName,
    null,
    DATABASE_VERSION,
    SafeCorruptionErrorHandler(context, dbName)
) {

    companion object {
        const val TAG = "EmergencyDbHelper"
        const val DATABASE_NAME = "safehelm_emergency.db"
        const val DATABASE_VERSION = 1

        // Table: emergency_incidents
        const val TABLE_INCIDENTS = "emergency_incidents"
        const val COL_INCIDENT_ID = "incident_id"
        const val COL_EVENT_TYPE = "event_type"
        const val COL_STATE = "state"
        const val COL_TRIGGER_TIMESTAMP_MS = "trigger_timestamp_ms"
        const val COL_COUNTDOWN_DURATION_MS = "countdown_duration_ms"
        const val COL_CANCELLED_TIMESTAMP_MS = "cancelled_timestamp_ms"
        const val COL_LATITUDE = "latitude"
        const val COL_LONGITUDE = "longitude"
        const val COL_LOCATION_ACCURACY = "location_accuracy"
        const val COL_LOCATION_TIMESTAMP_MS = "location_timestamp_ms"
        const val COL_LOCATION_SOURCE = "location_source"
        const val COL_TOTAL_RECIPIENTS = "total_recipients"
        const val COL_SUCCESSFUL_RECIPIENTS = "successful_recipients"
        const val COL_CREATED_AT_MS = "created_at_ms"
        const val COL_UPDATED_AT_MS = "updated_at_ms"

        // Table: emergency_dispatches
        const val TABLE_DISPATCHES = "emergency_dispatches"
        const val COL_DISPATCH_ID = "dispatch_id"
        const val COL_DISPATCH_INCIDENT_ID = "incident_id"
        const val COL_RECIPIENT_PHONE = "recipient_phone"
        const val COL_RECIPIENT_NAME = "recipient_name"
        const val COL_MESSAGE_BODY = "message_body"
        const val COL_DISPATCH_STATUS = "status"
        const val COL_RADIO_RESULT_CODE = "radio_result_code"
        const val COL_RETRY_COUNT = "retry_count"
        const val COL_LAST_ATTEMPT_MS = "last_attempt_ms"
        const val COL_NEXT_RETRY_MS = "next_retry_ms"
        const val COL_PARTS_TOTAL = "parts_total"
        const val COL_PARTS_CONFIRMED = "parts_confirmed"
        const val COL_DISPATCH_CREATED_AT_MS = "created_at_ms"
        const val COL_DISPATCH_UPDATED_AT_MS = "updated_at_ms"

        val CREATE_TABLE_INCIDENTS = """
            CREATE TABLE IF NOT EXISTS $TABLE_INCIDENTS (
                $COL_INCIDENT_ID TEXT PRIMARY KEY,
                $COL_EVENT_TYPE TEXT NOT NULL,
                $COL_STATE TEXT NOT NULL,
                $COL_TRIGGER_TIMESTAMP_MS INTEGER NOT NULL,
                $COL_COUNTDOWN_DURATION_MS INTEGER NOT NULL,
                $COL_CANCELLED_TIMESTAMP_MS INTEGER,
                $COL_LATITUDE REAL,
                $COL_LONGITUDE REAL,
                $COL_LOCATION_ACCURACY REAL,
                $COL_LOCATION_TIMESTAMP_MS INTEGER,
                $COL_LOCATION_SOURCE TEXT NOT NULL,
                $COL_TOTAL_RECIPIENTS INTEGER NOT NULL DEFAULT 0,
                $COL_SUCCESSFUL_RECIPIENTS INTEGER NOT NULL DEFAULT 0,
                $COL_CREATED_AT_MS INTEGER NOT NULL,
                $COL_UPDATED_AT_MS INTEGER NOT NULL
            );
        """.trimIndent()

        val CREATE_TABLE_DISPATCHES = """
            CREATE TABLE IF NOT EXISTS $TABLE_DISPATCHES (
                $COL_DISPATCH_ID TEXT PRIMARY KEY,
                $COL_DISPATCH_INCIDENT_ID TEXT NOT NULL,
                $COL_RECIPIENT_PHONE TEXT NOT NULL,
                $COL_RECIPIENT_NAME TEXT,
                $COL_MESSAGE_BODY TEXT NOT NULL,
                $COL_DISPATCH_STATUS TEXT NOT NULL,
                $COL_RADIO_RESULT_CODE INTEGER,
                $COL_RETRY_COUNT INTEGER NOT NULL DEFAULT 0,
                $COL_LAST_ATTEMPT_MS INTEGER,
                $COL_NEXT_RETRY_MS INTEGER,
                $COL_PARTS_TOTAL INTEGER NOT NULL DEFAULT 1,
                $COL_PARTS_CONFIRMED INTEGER NOT NULL DEFAULT 0,
                $COL_DISPATCH_CREATED_AT_MS INTEGER NOT NULL,
                $COL_DISPATCH_UPDATED_AT_MS INTEGER NOT NULL,
                FOREIGN KEY($COL_DISPATCH_INCIDENT_ID) REFERENCES $TABLE_INCIDENTS($COL_INCIDENT_ID) ON DELETE CASCADE
            );
        """.trimIndent()

        val CREATE_INDEX_INCIDENTS_STATE =
            "CREATE INDEX IF NOT EXISTS idx_incidents_state ON $TABLE_INCIDENTS($COL_STATE);"
        val CREATE_INDEX_DISPATCHES_INCIDENT =
            "CREATE INDEX IF NOT EXISTS idx_dispatches_incident ON $TABLE_DISPATCHES($COL_DISPATCH_INCIDENT_ID);"
        val CREATE_INDEX_DISPATCHES_STATUS =
            "CREATE INDEX IF NOT EXISTS idx_dispatches_status ON $TABLE_DISPATCHES($COL_DISPATCH_STATUS);"
    }

    override fun onConfigure(db: SQLiteDatabase) {
        super.onConfigure(db)
        db.enableWriteAheadLogging()
        db.setForeignKeyConstraintsEnabled(true)
    }

    override fun onCreate(db: SQLiteDatabase) {
        db.beginTransaction()
        try {
            db.execSQL(CREATE_TABLE_INCIDENTS)
            db.execSQL(CREATE_TABLE_DISPATCHES)
            db.execSQL(CREATE_INDEX_INCIDENTS_STATE)
            db.execSQL(CREATE_INDEX_DISPATCHES_INCIDENT)
            db.execSQL(CREATE_INDEX_DISPATCHES_STATUS)
            db.setTransactionSuccessful()
            Log.i(TAG, "Emergency database schema version $DATABASE_VERSION created successfully.")
        } finally {
            db.endTransaction()
        }
    }

    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
        Log.i(TAG, "Upgrading database from version $oldVersion to $newVersion")
        db.beginTransaction()
        try {
            // Versioned incremental migrations will be placed here as schema evolves
            // Example for future v2:
            // if (oldVersion < 2) { db.execSQL("ALTER TABLE ... ADD COLUMN ...") }
            db.setTransactionSuccessful()
        } finally {
            db.endTransaction()
        }
    }
}

/**
 * Custom corruption error handler that backs up a corrupt database file before recreating it,
 * preventing silent data destruction and allowing post-mortem forensics.
 */
class SafeCorruptionErrorHandler(
    private val context: Context,
    private val dbName: String
) : DatabaseErrorHandler {

    companion object {
        private const val TAG = "SafeCorruptionHandler"
    }

    override fun onCorruption(dbObj: SQLiteDatabase) {
        Log.e(TAG, "FATAL: Database corruption detected on $dbName!")
        val dbFile = context.getDatabasePath(dbName)
        if (dbFile.exists()) {
            val timestamp = System.currentTimeMillis()
            val backupFile = File(context.filesDir, "${dbName}.corrupt_$timestamp")
            try {
                FileInputStream(dbFile).use { input ->
                    FileOutputStream(backupFile).use { output ->
                        input.copyTo(output)
                    }
                }
                Log.w(TAG, "Corrupted database preserved at: ${backupFile.absolutePath}")
            } catch (e: Exception) {
                Log.e(TAG, "Failed to preserve corrupted database file", e)
            }
        }
    }
}
