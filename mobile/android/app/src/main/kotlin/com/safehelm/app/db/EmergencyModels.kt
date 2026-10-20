package com.safehelm.app.db

/**
 * Strict state machine governing the life-safety incident lifecycle.
 * Any transition not explicitly permitted by [canTransitionTo] is rejected.
 */
enum class IncidentState {
    DETECTED,
    COUNTDOWN,
    CANCELLED,
    DISPATCHING,
    SUBMITTED_TO_RIL,
    DISPATCHED,
    PARTIAL_FAILURE,
    QUEUED_OFFLINE,
    FAILED_TERMINAL,
    EXPIRED,
    FOLLOWUP_SAFE;

    fun isTerminal(): Boolean = this in setOf(CANCELLED, FAILED_TERMINAL, EXPIRED, FOLLOWUP_SAFE)

    fun canTransitionTo(next: IncidentState): Boolean {
        if (this == next) return true // Idempotent self-transition
        return when (this) {
            DETECTED -> next in setOf(COUNTDOWN, DISPATCHING, CANCELLED)
            COUNTDOWN -> next in setOf(CANCELLED, DISPATCHING)
            DISPATCHING -> next in setOf(SUBMITTED_TO_RIL, QUEUED_OFFLINE, FAILED_TERMINAL)
            SUBMITTED_TO_RIL -> next in setOf(DISPATCHED, PARTIAL_FAILURE, QUEUED_OFFLINE, FAILED_TERMINAL)
            QUEUED_OFFLINE -> next in setOf(SUBMITTED_TO_RIL, EXPIRED, CANCELLED)
            PARTIAL_FAILURE -> next in setOf(SUBMITTED_TO_RIL, FAILED_TERMINAL, FOLLOWUP_SAFE)
            DISPATCHED -> next in setOf(FOLLOWUP_SAFE)
            CANCELLED, FAILED_TERMINAL, EXPIRED, FOLLOWUP_SAFE -> false // Terminal states
        }
    }
}

/**
 * Per-recipient dispatch status tracking.
 */
enum class DispatchStatus {
    PENDING,
    SUBMITTED_TO_RIL,
    TRANSMITTED,
    QUEUED_OFFLINE,
    FAILED_TERMINAL,
    DELIVERED_REPORT;

    fun isTerminal(): Boolean = this in setOf(TRANSMITTED, FAILED_TERMINAL, DELIVERED_REPORT)

    fun canTransitionTo(next: DispatchStatus): Boolean {
        if (this == next) return true
        return when (this) {
            PENDING -> next in setOf(SUBMITTED_TO_RIL, QUEUED_OFFLINE, FAILED_TERMINAL)
            SUBMITTED_TO_RIL -> next in setOf(TRANSMITTED, QUEUED_OFFLINE, FAILED_TERMINAL, PENDING)
            QUEUED_OFFLINE -> next in setOf(PENDING, FAILED_TERMINAL)
            TRANSMITTED -> next in setOf(DELIVERED_REPORT)
            FAILED_TERMINAL, DELIVERED_REPORT -> false
        }
    }
}

/**
 * Location provenance data model strictly separating capture time from persistence time.
 */
data class LocationProvenance(
    val latitude: Double?,
    val longitude: Double?,
    val accuracyMeters: Float?,
    val acquisitionTimeMs: Long?,
    val source: String // 'GPS_LIVE', 'LAST_KNOWN', 'NETWORK', 'UNAVAILABLE'
) {
    fun isStale(currentTimeMs: Long, thresholdMs: Long = 120_000L): Boolean {
        if (acquisitionTimeMs == null) return true
        return (currentTimeMs - acquisitionTimeMs) > thresholdMs
    }
}

/**
 * High-level incident record stored in SQLite emergency_incidents table.
 */
data class IncidentRecord(
    val incidentId: String,
    val eventType: String,
    val state: IncidentState,
    val triggerTimestampMs: Long,
    val countdownDurationMs: Long,
    val cancelledTimestampMs: Long? = null,
    val location: LocationProvenance,
    val totalRecipients: Int,
    val successfulRecipients: Int = 0,
    val createdAtMs: Long,
    val updatedAtMs: Long
)

/**
 * Recipient-level dispatch attempt record stored in SQLite emergency_dispatches table.
 */
data class DispatchRecord(
    val dispatchId: String,
    val incidentId: String,
    val recipientPhone: String,
    val recipientName: String?,
    val messageBody: String,
    val status: DispatchStatus,
    val radioResultCode: Int? = null,
    val retryCount: Int = 0,
    val lastAttemptMs: Long? = null,
    val nextRetryMs: Long? = null,
    val partsTotal: Int = 1,
    val partsConfirmed: Int = 0,
    val createdAtMs: Long,
    val updatedAtMs: Long
)

/**
 * Result of ingesting an emergency incident into the journal.
 */
sealed class IngestResult {
    data class Ingested(val incident: IncidentRecord) : IngestResult()
    data class DuplicateIgnored(val existingIncident: IncidentRecord) : IngestResult()
    data class DatabaseError(val message: String, val cause: Throwable? = null) : IngestResult()
}
