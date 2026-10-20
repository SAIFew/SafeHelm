package com.safehelm.app.db

import android.database.Cursor
import android.database.sqlite.SQLiteDatabase
import java.io.Closeable

/**
 * Abstraction layer for SQLite database operations.
 * Allows pure in-memory JDBC SQLite drivers for rapid, deterministic JVM unit tests,
 * and delegates directly to Android's native android.database.sqlite.SQLiteDatabase in production.
 */
interface SqliteDriver : Closeable {
    fun execSQL(sql: String)
    fun execSQL(sql: String, bindArgs: Array<Any?>)
    fun rawQuery(sql: String, selectionArgs: Array<String>? = null): CursorResult
    fun beginTransaction()
    fun setTransactionSuccessful()
    fun endTransaction()
    fun inTransaction(): Boolean
}

/**
 * Universal cursor interface for accessing tabular query results across drivers.
 */
interface CursorResult : Closeable {
    fun moveToNext(): Boolean
    fun moveToFirst(): Boolean
    fun getCount(): Int
    fun isAfterLast(): Boolean
    fun getString(columnIndex: Int): String?
    fun getLong(columnIndex: Int): Long
    fun getInt(columnIndex: Int): Int
    fun getDouble(columnIndex: Int): Double
    fun getFloat(columnIndex: Int): Float
    fun isNull(columnIndex: Int): Boolean
    fun getColumnIndex(columnName: String): Int
    fun getColumnIndexOrThrow(columnName: String): Int
}

/**
 * Production driver wrapping Android's native SQLiteDatabase.
 */
class AndroidSqliteDriver(val db: SQLiteDatabase) : SqliteDriver {
    override fun execSQL(sql: String) = db.execSQL(sql)

    override fun execSQL(sql: String, bindArgs: Array<Any?>) = db.execSQL(sql, bindArgs)

    override fun rawQuery(sql: String, selectionArgs: Array<String>?): CursorResult {
        val cursor = db.rawQuery(sql, selectionArgs)
        return AndroidCursorResult(cursor)
    }

    override fun beginTransaction() = db.beginTransaction()

    override fun setTransactionSuccessful() = db.setTransactionSuccessful()

    override fun endTransaction() = db.endTransaction()

    override fun inTransaction(): Boolean = db.inTransaction()

    override fun close() {
        if (db.isOpen) {
            db.close()
        }
    }
}

/**
 * Android Cursor adapter wrapping android.database.Cursor.
 */
class AndroidCursorResult(private val cursor: Cursor) : CursorResult {
    override fun moveToNext(): Boolean = cursor.moveToNext()
    override fun moveToFirst(): Boolean = cursor.moveToFirst()
    override fun getCount(): Int = cursor.count
    override fun isAfterLast(): Boolean = cursor.isAfterLast
    override fun getString(columnIndex: Int): String? = if (cursor.isNull(columnIndex)) null else cursor.getString(columnIndex)
    override fun getLong(columnIndex: Int): Long = cursor.getLong(columnIndex)
    override fun getInt(columnIndex: Int): Int = cursor.getInt(columnIndex)
    override fun getDouble(columnIndex: Int): Double = cursor.getDouble(columnIndex)
    override fun getFloat(columnIndex: Int): Float = cursor.getFloat(columnIndex)
    override fun isNull(columnIndex: Int): Boolean = cursor.isNull(columnIndex)
    override fun getColumnIndex(columnName: String): Int = cursor.getColumnIndex(columnName)
    override fun getColumnIndexOrThrow(columnName: String): Int = cursor.getColumnIndexOrThrow(columnName)
    override fun close() = cursor.close()
}
