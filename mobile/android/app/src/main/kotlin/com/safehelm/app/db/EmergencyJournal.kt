package com.safehelm.app.db

import java.io.Closeable

data class DispatchDraft(
    val recipientPhone: String,
    val recipientName: String?,
    val messageBody: String,
    val partsTotal: Int = 1
)

sealed class TransitionResult {
    data class Success(val incident: IncidentRecord) : TransitionResult()
    data class NotFound(val incidentId: String) : TransitionResult()
    data class IllegalTransition(val currentState: IncidentState, val requestedState: IncidentState) : TransitionResult()
    data class DatabaseError(val message: String, val cause: Throwable? = null) : TransitionResult()
}

/**
 * Thread-safe native repository governing durable incident journaling and dispatch tracking.
 * Provides atomic transactions, idempotency guarantees, and state-transition enforcement.
 */
class EmergencyJournal(
    private val driver: SqliteDriver
) : Closeable {

    @Synchronized
    fun initSchema() {
        driver.beginTransaction()
        try {
            driver.execSQL(EmergencyDbHelper.CREATE_TABLE_INCIDENTS)
            driver.execSQL(EmergencyDbHelper.CREATE_TABLE_DISPATCHES)
            driver.execSQL(EmergencyDbHelper.CREATE_INDEX_INCIDENTS_STATE)
            driver.execSQL(EmergencyDbHelper.CREATE_INDEX_DISPATCHES_INCIDENT)
            driver.execSQL(EmergencyDbHelper.CREATE_INDEX_DISPATCHES_STATUS)
            driver.setTransactionSuccessful()
        } finally {
            driver.endTransaction()
        }
    }

    /**
     * Atomically ingests an incident into the journal before any asynchronous dispatch work begins.
     * Guaranteed idempotent: if an incident with [incidentId] already exists, returns DuplicateIgnored
     * without modifying the existing record.
     */
    @Synchronized
    fun ingestIncident(
        incidentId: String,
        eventType: String,
        triggerTimestampMs: Long,
        countdownDurationMs: Long = 15_000L,
        totalRecipients: Int = 0
    ): IngestResult {
        if (incidentId.isBlank()) {
            return IngestResult.DatabaseError("Incident ID cannot be blank")
        }

        driver.beginTransaction()
        try {
            val existing = getIncidentInternal(incidentId)
            if (existing != null) {
                driver.setTransactionSuccessful()
                return IngestResult.DuplicateIgnored(existing)
            }

            val now = System.currentTimeMillis()
            val sql = """
                INSERT INTO ${EmergencyDbHelper.TABLE_INCIDENTS} (
                    ${EmergencyDbHelper.COL_INCIDENT_ID},
                    ${EmergencyDbHelper.COL_EVENT_TYPE},
                    ${EmergencyDbHelper.COL_STATE},
                    ${EmergencyDbHelper.COL_TRIGGER_TIMESTAMP_MS},
                    ${EmergencyDbHelper.COL_COUNTDOWN_DURATION_MS},
                    ${EmergencyDbHelper.COL_CANCELLED_TIMESTAMP_MS},
                    ${EmergencyDbHelper.COL_LATITUDE},
                    ${EmergencyDbHelper.COL_LONGITUDE},
                    ${EmergencyDbHelper.COL_LOCATION_ACCURACY},
                    ${EmergencyDbHelper.COL_LOCATION_TIMESTAMP_MS},
                    ${EmergencyDbHelper.COL_LOCATION_SOURCE},
                    ${EmergencyDbHelper.COL_TOTAL_RECIPIENTS},
                    ${EmergencyDbHelper.COL_SUCCESSFUL_RECIPIENTS},
                    ${EmergencyDbHelper.COL_CREATED_AT_MS},
                    ${EmergencyDbHelper.COL_UPDATED_AT_MS}
                ) VALUES (?, ?, ?, ?, ?, NULL, NULL, NULL, NULL, NULL, 'UNAVAILABLE', ?, 0, ?, ?);
            """.trimIndent()

            driver.execSQL(
                sql,
                arrayOf(
                    incidentId,
                    eventType,
                    IncidentState.DETECTED.name,
                    triggerTimestampMs,
                    countdownDurationMs,
                    totalRecipients,
                    now,
                    now
                )
            )

            val newRecord = IncidentRecord(
                incidentId = incidentId,
                eventType = eventType,
                state = IncidentState.DETECTED,
                triggerTimestampMs = triggerTimestampMs,
                countdownDurationMs = countdownDurationMs,
                cancelledTimestampMs = null,
                location = LocationProvenance(null, null, null, null, "UNAVAILABLE"),
                totalRecipients = totalRecipients,
                successfulRecipients = 0,
                createdAtMs = now,
                updatedAtMs = now
            )

            driver.setTransactionSuccessful()
            return IngestResult.Ingested(newRecord)
        } catch (e: Exception) {
            return IngestResult.DatabaseError("Failed to ingest incident $incidentId: ${e.message}", e)
        } finally {
            driver.endTransaction()
        }
    }

    /**
     * Atomically executes a state transition on an existing incident.
     * Rejects invalid transitions according to [IncidentState.canTransitionTo].
     */
    @Synchronized
    fun transitionState(
        incidentId: String,
        expectedCurrentState: IncidentState? = null,
        nextState: IncidentState
    ): TransitionResult {
        driver.beginTransaction()
        try {
            val incident = getIncidentInternal(incidentId)
                ?: return TransitionResult.NotFound(incidentId)

            if (expectedCurrentState != null && incident.state != expectedCurrentState) {
                return TransitionResult.IllegalTransition(incident.state, nextState)
            }

            if (!incident.state.canTransitionTo(nextState)) {
                return TransitionResult.IllegalTransition(incident.state, nextState)
            }

            val now = System.currentTimeMillis()
            val cancelledTime = if (nextState == IncidentState.CANCELLED) now else incident.cancelledTimestampMs

            val sql = """
                UPDATE ${EmergencyDbHelper.TABLE_INCIDENTS}
                SET ${EmergencyDbHelper.COL_STATE} = ?,
                    ${EmergencyDbHelper.COL_CANCELLED_TIMESTAMP_MS} = ?,
                    ${EmergencyDbHelper.COL_UPDATED_AT_MS} = ?
                WHERE ${EmergencyDbHelper.COL_INCIDENT_ID} = ?;
            """.trimIndent()

            driver.execSQL(sql, arrayOf(nextState.name, cancelledTime, now, incidentId))

            val updated = incident.copy(
                state = nextState,
                cancelledTimestampMs = cancelledTime,
                updatedAtMs = now
            )

            driver.setTransactionSuccessful()
            return TransitionResult.Success(updated)
        } catch (e: Exception) {
            return TransitionResult.DatabaseError("State transition failed: ${e.message}", e)
        } finally {
            driver.endTransaction()
        }
    }

    /**
     * Updates the location provenance of an incident.
     * Guarantees distinct recording of GNSS acquisition timestamp vs system update timestamp.
     */
    @Synchronized
    fun updateLocation(
        incidentId: String,
        location: LocationProvenance
    ): Boolean {
        driver.beginTransaction()
        try {
            val now = System.currentTimeMillis()
            val sql = """
                UPDATE ${EmergencyDbHelper.TABLE_INCIDENTS}
                SET ${EmergencyDbHelper.COL_LATITUDE} = ?,
                    ${EmergencyDbHelper.COL_LONGITUDE} = ?,
                    ${EmergencyDbHelper.COL_LOCATION_ACCURACY} = ?,
                    ${EmergencyDbHelper.COL_LOCATION_TIMESTAMP_MS} = ?,
                    ${EmergencyDbHelper.COL_LOCATION_SOURCE} = ?,
                    ${EmergencyDbHelper.COL_UPDATED_AT_MS} = ?
                WHERE ${EmergencyDbHelper.COL_INCIDENT_ID} = ?;
            """.trimIndent()

            driver.execSQL(
                sql,
                arrayOf(
                    location.latitude,
                    location.longitude,
                    location.accuracyMeters,
                    location.acquisitionTimeMs,
                    location.source,
                    now,
                    incidentId
                )
            )
            driver.setTransactionSuccessful()
            return true
        } catch (_: Exception) {
            return false
        } finally {
            driver.endTransaction()
        }
    }

    /**
     * Atomically populates recipient-specific dispatch attempts for an incident.
     */
    @Synchronized
    fun createDispatchRecords(
        incidentId: String,
        drafts: List<DispatchDraft>
    ): Boolean {
        if (drafts.isEmpty()) return true

        driver.beginTransaction()
        try {
            val now = System.currentTimeMillis()
            val insertSql = """
                INSERT OR REPLACE INTO ${EmergencyDbHelper.TABLE_DISPATCHES} (
                    ${EmergencyDbHelper.COL_DISPATCH_ID},
                    ${EmergencyDbHelper.COL_DISPATCH_INCIDENT_ID},
                    ${EmergencyDbHelper.COL_RECIPIENT_PHONE},
                    ${EmergencyDbHelper.COL_RECIPIENT_NAME},
                    ${EmergencyDbHelper.COL_MESSAGE_BODY},
                    ${EmergencyDbHelper.COL_DISPATCH_STATUS},
                    ${EmergencyDbHelper.COL_RADIO_RESULT_CODE},
                    ${EmergencyDbHelper.COL_RETRY_COUNT},
                    ${EmergencyDbHelper.COL_LAST_ATTEMPT_MS},
                    ${EmergencyDbHelper.COL_NEXT_RETRY_MS},
                    ${EmergencyDbHelper.COL_PARTS_TOTAL},
                    ${EmergencyDbHelper.COL_PARTS_CONFIRMED},
                    ${EmergencyDbHelper.COL_DISPATCH_CREATED_AT_MS},
                    ${EmergencyDbHelper.COL_DISPATCH_UPDATED_AT_MS}
                ) VALUES (?, ?, ?, ?, ?, ?, NULL, 0, NULL, NULL, ?, 0, ?, ?);
            """.trimIndent()

            for (d in drafts) {
                val dispatchId = "${incidentId}_${d.recipientPhone.filter { it.isLetterOrDigit() }}"
                driver.execSQL(
                    insertSql,
                    arrayOf(
                        dispatchId,
                        incidentId,
                        d.recipientPhone,
                        d.recipientName,
                        d.messageBody,
                        DispatchStatus.PENDING.name,
                        d.partsTotal,
                        now,
                        now
                    )
                )
            }

            val updateIncidentSql = """
                UPDATE ${EmergencyDbHelper.TABLE_INCIDENTS}
                SET ${EmergencyDbHelper.COL_TOTAL_RECIPIENTS} = ?,
                    ${EmergencyDbHelper.COL_UPDATED_AT_MS} = ?
                WHERE ${EmergencyDbHelper.COL_INCIDENT_ID} = ?;
            """.trimIndent()
            driver.execSQL(updateIncidentSql, arrayOf(drafts.size, now, incidentId))

            driver.setTransactionSuccessful()
            return true
        } catch (_: Exception) {
            return false
        } finally {
            driver.endTransaction()
        }
    }

    /**
     * Updates an individual recipient dispatch record.
     */
    @Synchronized
    fun updateDispatchStatus(
        dispatchId: String,
        nextStatus: DispatchStatus,
        radioResultCode: Int? = null,
        incrementRetry: Boolean = false,
        partsConfirmedDelta: Int = 0
    ): Boolean {
        driver.beginTransaction()
        try {
            val querySql = "SELECT * FROM ${EmergencyDbHelper.TABLE_DISPATCHES} WHERE ${EmergencyDbHelper.COL_DISPATCH_ID} = ?;"
            val cursor = driver.rawQuery(querySql, arrayOf(dispatchId))
            if (!cursor.moveToFirst()) {
                cursor.close()
                return false
            }

            val currentStatusStr = cursor.getString(cursor.getColumnIndexOrThrow(EmergencyDbHelper.COL_DISPATCH_STATUS)) ?: ""
            val currentStatus = try { DispatchStatus.valueOf(currentStatusStr) } catch (_: Exception) { DispatchStatus.PENDING }
            val currentRetries = cursor.getInt(cursor.getColumnIndexOrThrow(EmergencyDbHelper.COL_RETRY_COUNT))
            val currentConfirmed = cursor.getInt(cursor.getColumnIndexOrThrow(EmergencyDbHelper.COL_PARTS_CONFIRMED))
            val incidentId = cursor.getString(cursor.getColumnIndexOrThrow(EmergencyDbHelper.COL_DISPATCH_INCIDENT_ID)) ?: ""
            cursor.close()

            if (!currentStatus.canTransitionTo(nextStatus)) {
                return false
            }

            val now = System.currentTimeMillis()
            val newRetries = if (incrementRetry) currentRetries + 1 else currentRetries
            val newConfirmed = currentConfirmed + partsConfirmedDelta

            val updateSql = """
                UPDATE ${EmergencyDbHelper.TABLE_DISPATCHES}
                SET ${EmergencyDbHelper.COL_DISPATCH_STATUS} = ?,
                    ${EmergencyDbHelper.COL_RADIO_RESULT_CODE} = ?,
                    ${EmergencyDbHelper.COL_RETRY_COUNT} = ?,
                    ${EmergencyDbHelper.COL_PARTS_CONFIRMED} = ?,
                    ${EmergencyDbHelper.COL_LAST_ATTEMPT_MS} = ?,
                    ${EmergencyDbHelper.COL_DISPATCH_UPDATED_AT_MS} = ?
                WHERE ${EmergencyDbHelper.COL_DISPATCH_ID} = ?;
            """.trimIndent()

            driver.execSQL(
                updateSql,
                arrayOf(
                    nextStatus.name,
                    radioResultCode,
                    newRetries,
                    newConfirmed,
                    now,
                    now,
                    dispatchId
                )
            )

            // Re-evaluate aggregate count for parent incident
            if (incidentId.isNotEmpty()) {
                val countSql = """
                    SELECT COUNT(*) FROM ${EmergencyDbHelper.TABLE_DISPATCHES}
                    WHERE ${EmergencyDbHelper.COL_DISPATCH_INCIDENT_ID} = ?
                      AND ${EmergencyDbHelper.COL_DISPATCH_STATUS} = '${DispatchStatus.TRANSMITTED.name}';
                """.trimIndent()
                val countCursor = driver.rawQuery(countSql, arrayOf(incidentId))
                var successCount = 0
                if (countCursor.moveToFirst()) {
                    successCount = countCursor.getInt(0)
                }
                countCursor.close()

                val updateParentSql = """
                    UPDATE ${EmergencyDbHelper.TABLE_INCIDENTS}
                    SET ${EmergencyDbHelper.COL_SUCCESSFUL_RECIPIENTS} = ?,
                        ${EmergencyDbHelper.COL_UPDATED_AT_MS} = ?
                    WHERE ${EmergencyDbHelper.COL_INCIDENT_ID} = ?;
                """.trimIndent()
                driver.execSQL(updateParentSql, arrayOf(successCount, now, incidentId))
            }

            driver.setTransactionSuccessful()
            return true
        } catch (_: Exception) {
            return false
        } finally {
            driver.endTransaction()
        }
    }

    @Synchronized
    fun getIncident(incidentId: String): IncidentRecord? {
        return getIncidentInternal(incidentId)
    }

    @Synchronized
    fun getActiveIncidents(): List<IncidentRecord> {
        val nonTerminal = IncidentState.values()
            .filter { !it.isTerminal() }
            .joinToString("','", "'", "'") { it.name }
        val sql = "SELECT * FROM ${EmergencyDbHelper.TABLE_INCIDENTS} WHERE ${EmergencyDbHelper.COL_STATE} IN ($nonTerminal) ORDER BY ${EmergencyDbHelper.COL_TRIGGER_TIMESTAMP_MS} DESC;"
        val cursor = driver.rawQuery(sql, null)
        val list = mutableListOf<IncidentRecord>()
        while (cursor.moveToNext()) {
            list.add(mapCursorToIncident(cursor))
        }
        cursor.close()
        return list
    }

    @Synchronized
    fun getAllIncidents(): List<IncidentRecord> {
        val sql = "SELECT * FROM ${EmergencyDbHelper.TABLE_INCIDENTS} ORDER BY ${EmergencyDbHelper.COL_TRIGGER_TIMESTAMP_MS} DESC;"
        val cursor = driver.rawQuery(sql, null)
        val list = mutableListOf<IncidentRecord>()
        while (cursor.moveToNext()) {
            list.add(mapCursorToIncident(cursor))
        }
        cursor.close()
        return list
    }

    @Synchronized
    fun getDispatchesForIncident(incidentId: String): List<DispatchRecord> {
        val sql = "SELECT * FROM ${EmergencyDbHelper.TABLE_DISPATCHES} WHERE ${EmergencyDbHelper.COL_DISPATCH_INCIDENT_ID} = ? ORDER BY ${EmergencyDbHelper.COL_DISPATCH_CREATED_AT_MS} ASC;"
        val cursor = driver.rawQuery(sql, arrayOf(incidentId))
        val list = mutableListOf<DispatchRecord>()
        while (cursor.moveToNext()) {
            list.add(mapCursorToDispatch(cursor))
        }
        cursor.close()
        return list
    }

    private fun getIncidentInternal(incidentId: String): IncidentRecord? {
        val sql = "SELECT * FROM ${EmergencyDbHelper.TABLE_INCIDENTS} WHERE ${EmergencyDbHelper.COL_INCIDENT_ID} = ?;"
        val cursor = driver.rawQuery(sql, arrayOf(incidentId))
        val result = if (cursor.moveToFirst()) {
            mapCursorToIncident(cursor)
        } else {
            null
        }
        cursor.close()
        return result
    }

    private fun mapCursorToIncident(c: CursorResult): IncidentRecord {
        val id = c.getString(c.getColumnIndexOrThrow(EmergencyDbHelper.COL_INCIDENT_ID)) ?: ""
        val type = c.getString(c.getColumnIndexOrThrow(EmergencyDbHelper.COL_EVENT_TYPE)) ?: ""
        val stateStr = c.getString(c.getColumnIndexOrThrow(EmergencyDbHelper.COL_STATE)) ?: ""
        val state = try { IncidentState.valueOf(stateStr) } catch (_: Exception) { IncidentState.DETECTED }
        val triggerTime = c.getLong(c.getColumnIndexOrThrow(EmergencyDbHelper.COL_TRIGGER_TIMESTAMP_MS))
        val countdownDur = c.getLong(c.getColumnIndexOrThrow(EmergencyDbHelper.COL_COUNTDOWN_DURATION_MS))
        val cancelledCol = c.getColumnIndexOrThrow(EmergencyDbHelper.COL_CANCELLED_TIMESTAMP_MS)
        val cancelledTime = if (c.isNull(cancelledCol)) null else c.getLong(cancelledCol)

        val latCol = c.getColumnIndexOrThrow(EmergencyDbHelper.COL_LATITUDE)
        val lat = if (c.isNull(latCol)) null else c.getDouble(latCol)
        val lonCol = c.getColumnIndexOrThrow(EmergencyDbHelper.COL_LONGITUDE)
        val lon = if (c.isNull(lonCol)) null else c.getDouble(lonCol)
        val accCol = c.getColumnIndexOrThrow(EmergencyDbHelper.COL_LOCATION_ACCURACY)
        val acc = if (c.isNull(accCol)) null else c.getFloat(accCol)
        val locTimeCol = c.getColumnIndexOrThrow(EmergencyDbHelper.COL_LOCATION_TIMESTAMP_MS)
        val locTime = if (c.isNull(locTimeCol)) null else c.getLong(locTimeCol)
        val locSource = c.getString(c.getColumnIndexOrThrow(EmergencyDbHelper.COL_LOCATION_SOURCE)) ?: "UNAVAILABLE"

        val totalRecipients = c.getInt(c.getColumnIndexOrThrow(EmergencyDbHelper.COL_TOTAL_RECIPIENTS))
        val successfulRecipients = c.getInt(c.getColumnIndexOrThrow(EmergencyDbHelper.COL_SUCCESSFUL_RECIPIENTS))
        val createdAt = c.getLong(c.getColumnIndexOrThrow(EmergencyDbHelper.COL_CREATED_AT_MS))
        val updatedAt = c.getLong(c.getColumnIndexOrThrow(EmergencyDbHelper.COL_UPDATED_AT_MS))

        return IncidentRecord(
            incidentId = id,
            eventType = type,
            state = state,
            triggerTimestampMs = triggerTime,
            countdownDurationMs = countdownDur,
            cancelledTimestampMs = cancelledTime,
            location = LocationProvenance(
                latitude = lat,
                longitude = lon,
                accuracyMeters = acc,
                acquisitionTimeMs = locTime,
                source = locSource
            ),
            totalRecipients = totalRecipients,
            successfulRecipients = successfulRecipients,
            createdAtMs = createdAt,
            updatedAtMs = updatedAt
        )
    }

    private fun mapCursorToDispatch(c: CursorResult): DispatchRecord {
        val dispatchId = c.getString(c.getColumnIndexOrThrow(EmergencyDbHelper.COL_DISPATCH_ID)) ?: ""
        val incidentId = c.getString(c.getColumnIndexOrThrow(EmergencyDbHelper.COL_DISPATCH_INCIDENT_ID)) ?: ""
        val phone = c.getString(c.getColumnIndexOrThrow(EmergencyDbHelper.COL_RECIPIENT_PHONE)) ?: ""
        val nameCol = c.getColumnIndexOrThrow(EmergencyDbHelper.COL_RECIPIENT_NAME)
        val name = if (c.isNull(nameCol)) null else c.getString(nameCol)
        val body = c.getString(c.getColumnIndexOrThrow(EmergencyDbHelper.COL_MESSAGE_BODY)) ?: ""

        val statusStr = c.getString(c.getColumnIndexOrThrow(EmergencyDbHelper.COL_DISPATCH_STATUS)) ?: ""
        val status = try { DispatchStatus.valueOf(statusStr) } catch (_: Exception) { DispatchStatus.PENDING }
        val radioCodeCol = c.getColumnIndexOrThrow(EmergencyDbHelper.COL_RADIO_RESULT_CODE)
        val radioCode = if (c.isNull(radioCodeCol)) null else c.getInt(radioCodeCol)

        val retryCount = c.getInt(c.getColumnIndexOrThrow(EmergencyDbHelper.COL_RETRY_COUNT))
        val lastAttemptCol = c.getColumnIndexOrThrow(EmergencyDbHelper.COL_LAST_ATTEMPT_MS)
        val lastAttempt = if (c.isNull(lastAttemptCol)) null else c.getLong(lastAttemptCol)
        val nextRetryCol = c.getColumnIndexOrThrow(EmergencyDbHelper.COL_NEXT_RETRY_MS)
        val nextRetry = if (c.isNull(nextRetryCol)) null else c.getLong(nextRetryCol)

        val partsTotal = c.getInt(c.getColumnIndexOrThrow(EmergencyDbHelper.COL_PARTS_TOTAL))
        val partsConfirmed = c.getInt(c.getColumnIndexOrThrow(EmergencyDbHelper.COL_PARTS_CONFIRMED))
        val createdAt = c.getLong(c.getColumnIndexOrThrow(EmergencyDbHelper.COL_DISPATCH_CREATED_AT_MS))
        val updatedAt = c.getLong(c.getColumnIndexOrThrow(EmergencyDbHelper.COL_DISPATCH_UPDATED_AT_MS))

        return DispatchRecord(
            dispatchId = dispatchId,
            incidentId = incidentId,
            recipientPhone = phone,
            recipientName = name,
            messageBody = body,
            status = status,
            radioResultCode = radioCode,
            retryCount = retryCount,
            lastAttemptMs = lastAttempt,
            nextRetryMs = nextRetry,
            partsTotal = partsTotal,
            partsConfirmed = partsConfirmed,
            createdAtMs = createdAt,
            updatedAtMs = updatedAt
        )
    }

    override fun close() {
        driver.close()
    }
}
