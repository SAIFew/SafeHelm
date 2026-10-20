package com.safehelm.app.db

import java.sql.Connection
import java.sql.DriverManager
import java.sql.ResultSet
import java.sql.Statement

/**
 * JVM-compatible SQLite driver using org.xerial:sqlite-jdbc.
 * Used for running native unit tests without requiring an Android device or emulator.
 */
class JdbcSqliteDriver(private val connection: Connection) : SqliteDriver {

    private var transactionSuccessful = false

    companion object {
        fun inMemory(): JdbcSqliteDriver {
            val conn = DriverManager.getConnection("jdbc:sqlite::memory:")
            return JdbcSqliteDriver(conn)
        }

        fun file(path: String): JdbcSqliteDriver {
            val conn = DriverManager.getConnection("jdbc:sqlite:$path")
            return JdbcSqliteDriver(conn)
        }
    }

    override fun execSQL(sql: String) {
        connection.createStatement().use { it.execute(sql) }
    }

    override fun execSQL(sql: String, bindArgs: Array<Any?>) {
        connection.prepareStatement(sql).use { stmt ->
            bindArgs.forEachIndexed { idx, arg ->
                when (arg) {
                    null -> stmt.setNull(idx + 1, java.sql.Types.NULL)
                    is String -> stmt.setString(idx + 1, arg)
                    is Long -> stmt.setLong(idx + 1, arg)
                    is Int -> stmt.setInt(idx + 1, arg)
                    is Double -> stmt.setDouble(idx + 1, arg)
                    is Float -> stmt.setFloat(idx + 1, arg)
                    is ByteArray -> stmt.setBytes(idx + 1, arg)
                    else -> stmt.setString(idx + 1, arg.toString())
                }
            }
            stmt.executeUpdate()
        }
    }

    override fun rawQuery(sql: String, selectionArgs: Array<String>?): CursorResult {
        val stmt = connection.prepareStatement(
            sql,
            ResultSet.TYPE_FORWARD_ONLY,
            ResultSet.CONCUR_READ_ONLY
        )
        selectionArgs?.forEachIndexed { idx, arg ->
            stmt.setString(idx + 1, arg)
        }
        val rs = stmt.executeQuery()
        return JdbcCursorResult(stmt, rs)
    }

    override fun beginTransaction() {
        connection.autoCommit = false
        transactionSuccessful = false
    }

    override fun setTransactionSuccessful() {
        transactionSuccessful = true
    }

    override fun endTransaction() {
        try {
            if (transactionSuccessful) {
                connection.commit()
            } else {
                connection.rollback()
            }
        } finally {
            connection.autoCommit = true
            transactionSuccessful = false
        }
    }

    override fun inTransaction(): Boolean = !connection.autoCommit

    override fun close() {
        if (!connection.isClosed) {
            connection.close()
        }
    }
}

class JdbcCursorResult(
    private val statement: Statement,
    private val rs: ResultSet
) : CursorResult {

    private var cachedRows: List<Map<String, Any?>>? = null
    private var currentIndex = -1
    private var columnNames: List<String> = emptyList()

    init {
        val list = mutableListOf<Map<String, Any?>>()
        val md = rs.metaData
        val cols = mutableListOf<String>()
        for (i in 1..md.columnCount) {
            cols.add(md.getColumnLabel(i).lowercase())
        }
        columnNames = cols

        while (rs.next()) {
            val row = mutableMapOf<String, Any?>()
            for (i in 1..md.columnCount) {
                val colName = md.getColumnLabel(i).lowercase()
                val value = rs.getObject(i)
                row[colName] = if (rs.wasNull()) null else value
            }
            list.add(row)
        }
        cachedRows = list
        rs.close()
        statement.close()
    }

    override fun moveToNext(): Boolean {
        val rows = cachedRows ?: return false
        if (currentIndex + 1 < rows.size) {
            currentIndex++
            return true
        }
        currentIndex = rows.size
        return false
    }

    override fun moveToFirst(): Boolean {
        val rows = cachedRows ?: return false
        if (rows.isNotEmpty()) {
            currentIndex = 0
            return true
        }
        return false
    }

    override fun getCount(): Int = cachedRows?.size ?: 0

    override fun isAfterLast(): Boolean = currentIndex >= (cachedRows?.size ?: 0)

    override fun getString(columnIndex: Int): String? {
        val value = getCurrentRow()?.get(columnNames[columnIndex]) ?: return null
        return value.toString()
    }

    override fun getLong(columnIndex: Int): Long {
        val value = getCurrentRow()?.get(columnNames[columnIndex]) ?: return 0L
        return when (value) {
            is Number -> value.toLong()
            is String -> value.toLongOrNull() ?: 0L
            else -> 0L
        }
    }

    override fun getInt(columnIndex: Int): Int {
        val value = getCurrentRow()?.get(columnNames[columnIndex]) ?: return 0
        return when (value) {
            is Number -> value.toInt()
            is String -> value.toIntOrNull() ?: 0
            else -> 0
        }
    }

    override fun getDouble(columnIndex: Int): Double {
        val value = getCurrentRow()?.get(columnNames[columnIndex]) ?: return 0.0
        return when (value) {
            is Number -> value.toDouble()
            is String -> value.toDoubleOrNull() ?: 0.0
            else -> 0.0
        }
    }

    override fun getFloat(columnIndex: Int): Float {
        val value = getCurrentRow()?.get(columnNames[columnIndex]) ?: return 0.0f
        return when (value) {
            is Number -> value.toFloat()
            is String -> value.toFloatOrNull() ?: 0.0f
            else -> 0.0f
        }
    }

    override fun isNull(columnIndex: Int): Boolean {
        val col = columnNames.getOrNull(columnIndex) ?: return true
        return getCurrentRow()?.get(col) == null
    }

    override fun getColumnIndex(columnName: String): Int {
        return columnNames.indexOf(columnName.lowercase())
    }

    override fun getColumnIndexOrThrow(columnName: String): Int {
        val idx = getColumnIndex(columnName)
        if (idx < 0) throw IllegalArgumentException("Column $columnName not found in $columnNames")
        return idx
    }

    private fun getCurrentRow(): Map<String, Any?>? {
        val rows = cachedRows ?: return null
        if (currentIndex in rows.indices) {
            return rows[currentIndex]
        }
        return null
    }

    override fun close() {
        cachedRows = null
    }
}
