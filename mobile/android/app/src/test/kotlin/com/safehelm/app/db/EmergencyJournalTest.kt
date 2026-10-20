package com.safehelm.app.db

import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import java.io.File

class EmergencyJournalTest {

    private lateinit var driver: JdbcSqliteDriver
    private lateinit var journal: EmergencyJournal
    private var tempDbFile: File? = null

    @Before
    fun setUp() {
        driver = JdbcSqliteDriver.inMemory()
        journal = EmergencyJournal(driver)
        journal.initSchema()
    }

    @After
    fun tearDown() {
        journal.close()
        tempDbFile?.delete()
    }

    @Test
    fun testSchemaCreationAndEmptyQuery() {
        val incidents = journal.getAllIncidents()
        assertTrue("Initial database should have no incidents", incidents.isEmpty())
        val active = journal.getActiveIncidents()
        assertTrue("Initial database should have no active incidents", active.isEmpty())
    }

    @Test
    fun testIngestIncident_Success() {
        val triggerTime = 1729480000000L
        val result = journal.ingestIncident(
            incidentId = "SH-A1B2-1-101",
            eventType = "ACCIDENT",
            triggerTimestampMs = triggerTime,
            countdownDurationMs = 15000L,
            totalRecipients = 3
        )

        assertTrue("Result should be Ingested", result is IngestResult.Ingested)
        val ingested = (result as IngestResult.Ingested).incident
        assertEquals("SH-A1B2-1-101", ingested.incidentId)
        assertEquals("ACCIDENT", ingested.eventType)
        assertEquals(IncidentState.DETECTED, ingested.state)
        assertEquals(triggerTime, ingested.triggerTimestampMs)
        assertEquals("UNAVAILABLE", ingested.location.source)
        assertNull("Latitude should be null initially", ingested.location.latitude)
        assertEquals(3, ingested.totalRecipients)
        assertEquals(0, ingested.successfulRecipients)

        val retrieved = journal.getIncident("SH-A1B2-1-101")
        assertNotNull("Incident should be retrievable", retrieved)
        assertEquals("SH-A1B2-1-101", retrieved?.incidentId)
    }

    @Test
    fun testIngestIncident_IdempotentDeduplication() {
        val id = "SH-DEDUP-001"
        val res1 = journal.ingestIncident(id, "ACCIDENT", 1000L)
        assertTrue("First ingestion must succeed", res1 is IngestResult.Ingested)

        // Attempt duplicate ingestion (e.g. repeated BLE packet)
        val res2 = journal.ingestIncident(id, "ACCIDENT", 2000L)
        assertTrue("Second ingestion with same ID must return DuplicateIgnored", res2 is IngestResult.DuplicateIgnored)

        val all = journal.getAllIncidents()
        assertEquals("Database must contain exactly 1 incident despite duplicate ingestion", 1, all.size)
        assertEquals(1000L, all[0].triggerTimestampMs)
    }

    @Test
    fun testLegalStateTransitions_CompleteFlow() {
        val id = "SH-FLOW-001"
        journal.ingestIncident(id, "ACCIDENT", 1000L)

        // DETECTED -> COUNTDOWN
        val t1 = journal.transitionState(id, IncidentState.DETECTED, IncidentState.COUNTDOWN)
        assertTrue(t1 is TransitionResult.Success)
        assertEquals(IncidentState.COUNTDOWN, (t1 as TransitionResult.Success).incident.state)

        // COUNTDOWN -> DISPATCHING
        val t2 = journal.transitionState(id, IncidentState.COUNTDOWN, IncidentState.DISPATCHING)
        assertTrue(t2 is TransitionResult.Success)
        assertEquals(IncidentState.DISPATCHING, (t2 as TransitionResult.Success).incident.state)

        // DISPATCHING -> SUBMITTED_TO_RIL
        val t3 = journal.transitionState(id, IncidentState.DISPATCHING, IncidentState.SUBMITTED_TO_RIL)
        assertTrue(t3 is TransitionResult.Success)

        // SUBMITTED_TO_RIL -> DISPATCHED
        val t4 = journal.transitionState(id, IncidentState.SUBMITTED_TO_RIL, IncidentState.DISPATCHED)
        assertTrue(t4 is TransitionResult.Success)

        // DISPATCHED -> FOLLOWUP_SAFE
        val t5 = journal.transitionState(id, IncidentState.DISPATCHED, IncidentState.FOLLOWUP_SAFE)
        assertTrue(t5 is TransitionResult.Success)
        assertTrue("FOLLOWUP_SAFE must be terminal", (t5 as TransitionResult.Success).incident.state.isTerminal())
    }

    @Test
    fun testIllegalStateTransitions_Rejected() {
        val id = "SH-ILLEGAL-001"
        journal.ingestIncident(id, "ACCIDENT", 1000L)

        // Illegal: DETECTED directly to DISPATCHED
        val t1 = journal.transitionState(id, IncidentState.DETECTED, IncidentState.DISPATCHED)
        assertTrue("Skipping dispatch sequence must be rejected", t1 is TransitionResult.IllegalTransition)
        assertEquals(IncidentState.DETECTED, (t1 as TransitionResult.IllegalTransition).currentState)
        assertEquals(IncidentState.DISPATCHED, t1.requestedState)

        // Verify incident state is unchanged
        assertEquals(IncidentState.DETECTED, journal.getIncident(id)?.state)

        // Cancel the incident
        val cancel = journal.transitionState(id, IncidentState.DETECTED, IncidentState.CANCELLED)
        assertTrue(cancel is TransitionResult.Success)

        // Illegal: Transitioning out of terminal CANCELLED state
        val t2 = journal.transitionState(id, IncidentState.CANCELLED, IncidentState.DISPATCHING)
        assertTrue("Transition out of CANCELLED must be rejected", t2 is TransitionResult.IllegalTransition)
        assertEquals(IncidentState.CANCELLED, journal.getIncident(id)?.state)
    }

    @Test
    fun testCancellationRecordsTimestamp() {
        val id = "SH-CANCEL-001"
        journal.ingestIncident(id, "ACCIDENT", 1000L)
        val beforeCancel = System.currentTimeMillis()

        val res = journal.transitionState(id, null, IncidentState.CANCELLED)
        assertTrue(res is TransitionResult.Success)

        val incident = journal.getIncident(id)
        assertNotNull(incident)
        assertNotNull("Cancelled timestamp must be set", incident?.cancelledTimestampMs)
        assertTrue(incident!!.cancelledTimestampMs!! >= beforeCancel)
    }

    @Test
    fun testLocationProvenance_DistinguishesLiveVsStale() {
        val id = "SH-LOC-001"
        journal.ingestIncident(id, "ACCIDENT", 1000L)

        val gpsTime = 1729480100000L
        val loc = LocationProvenance(
            latitude = 37.7749,
            longitude = -122.4194,
            accuracyMeters = 4.5f,
            acquisitionTimeMs = gpsTime,
            source = "GPS_LIVE"
        )

        val updated = journal.updateLocation(id, loc)
        assertTrue("Location update must succeed", updated)

        val incident = journal.getIncident(id)
        assertNotNull(incident)
        assertEquals(37.7749, incident!!.location.latitude!!, 0.0001)
        assertEquals(-122.4194, incident.location.longitude!!, 0.0001)
        assertEquals(4.5f, incident.location.accuracyMeters!!, 0.01f)
        assertEquals(gpsTime, incident.location.acquisitionTimeMs)
        assertEquals("GPS_LIVE", incident.location.source)

        // Test staleness helper
        assertFalse("Recent coordinate must not be stale", loc.isStale(gpsTime + 30_000L, 60_000L))
        assertTrue("Coordinate older than threshold must be marked stale", loc.isStale(gpsTime + 90_000L, 60_000L))
    }

    @Test
    fun testDispatchRecordsAndRecipientTracking() {
        val id = "SH-DISPATCH-001"
        journal.ingestIncident(id, "ACCIDENT", 1000L)

        val drafts = listOf(
            DispatchDraft("+15551234567", "Alice", "SafeHelm Emergency Alert"),
            DispatchDraft("+15559876543", "Bob", "SafeHelm Emergency Alert")
        )

        val created = journal.createDispatchRecords(id, drafts)
        assertTrue("Dispatch records creation must succeed", created)

        val dispatches = journal.getDispatchesForIncident(id)
        assertEquals(2, dispatches.size)
        assertEquals("+15551234567", dispatches[0].recipientPhone)
        assertEquals(DispatchStatus.PENDING, dispatches[0].status)

        val d1Id = dispatches[0].dispatchId

        // Transition d1 to SUBMITTED_TO_RIL
        val u1 = journal.updateDispatchStatus(d1Id, DispatchStatus.SUBMITTED_TO_RIL)
        assertTrue(u1)

        // Transition d1 to TRANSMITTED
        val u2 = journal.updateDispatchStatus(d1Id, DispatchStatus.TRANSMITTED, radioResultCode = -1, partsConfirmedDelta = 1)
        assertTrue(u2)

        // Check that successful recipients on parent incident updated to 1
        val parent = journal.getIncident(id)
        assertEquals(1, parent?.successfulRecipients)

        // Illegal dispatch transition: TRANSMITTED back to PENDING
        val illegal = journal.updateDispatchStatus(d1Id, DispatchStatus.PENDING)
        assertFalse("Transitioning terminal dispatch back to PENDING must be rejected", illegal)
    }

    @Test
    fun testProcessTerminationSimulation_ReopeningDatabase() {
        tempDbFile = File.createTempFile("safehelm_test_", ".db")
        val filePath = tempDbFile!!.absolutePath

        // 1. Process A: Ingest incident and transition to DISPATCHING
        val driverA = JdbcSqliteDriver.file(filePath)
        val journalA = EmergencyJournal(driverA)
        journalA.initSchema()

        journalA.ingestIncident("SH-PERSIST-999", "ACCIDENT", 5000L, 15000L, 2)
        journalA.transitionState("SH-PERSIST-999", null, IncidentState.DISPATCHING)
        journalA.updateLocation(
            "SH-PERSIST-999",
            LocationProvenance(12.9716, 77.5946, 8.0f, 5010L, "GPS_LIVE")
        )
        journalA.createDispatchRecords(
            "SH-PERSIST-999",
            listOf(DispatchDraft("+919876543210", "Paramedic", "Critical crash alert"))
        )

        // Simulate abrupt process termination: close driverA
        journalA.close()

        // 2. Process B: App relaunched after process death
        val driverB = JdbcSqliteDriver.file(filePath)
        val journalB = EmergencyJournal(driverB)

        val active = journalB.getActiveIncidents()
        assertEquals("Must recover 1 active incident after process restart", 1, active.size)
        val recovered = active[0]
        assertEquals("SH-PERSIST-999", recovered.incidentId)
        assertEquals(IncidentState.DISPATCHING, recovered.state)
        assertEquals(12.9716, recovered.location.latitude!!, 0.0001)
        assertEquals(77.5946, recovered.location.longitude!!, 0.0001)

        val dispatches = journalB.getDispatchesForIncident("SH-PERSIST-999")
        assertEquals(1, dispatches.size)
        assertEquals("+919876543210", dispatches[0].recipientPhone)
        assertEquals(DispatchStatus.PENDING, dispatches[0].status)

        journalB.close()
    }

    @Test
    fun testBlankIncidentId_Rejected() {
        val res = journal.ingestIncident("", "ACCIDENT", 1000L)
        assertTrue("Blank incident ID must return DatabaseError", res is IngestResult.DatabaseError)
    }
}
