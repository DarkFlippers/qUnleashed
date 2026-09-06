package com.darkflippers.qunleashed.widget

import android.content.Context
import org.json.JSONObject

/** The file behind one widget, as Dart handed it over. */
data class WidgetKeyData(
    val name: String,
    val category: String,
    val remotePath: String,
    val holdToSend: Boolean,
) {
    fun toMap(): Map<String, Any> = mapOf(
        "name" to name,
        "category" to category,
        "remotePath" to remotePath,
        "holdToSend" to holdToSend,
    )

    fun toJson(): String = JSONObject(toMap()).toString()

    companion object {
        fun fromArguments(arguments: Any?): WidgetKeyData? {
            val map = arguments as? Map<*, *> ?: return null
            val name = map["name"] as? String ?: return null
            val category = map["category"] as? String ?: return null
            val remotePath = map["remotePath"] as? String ?: return null
            return WidgetKeyData(name, category, remotePath, map["holdToSend"] == true)
        }

        fun fromJson(raw: String): WidgetKeyData? = try {
            val json = JSONObject(raw)
            WidgetKeyData(
                json.getString("name"),
                json.getString("category"),
                json.getString("remotePath"),
                json.optBoolean("holdToSend", false),
            )
        } catch (_: Exception) {
            null
        }
    }
}

/**
 * Widget id → key, in the app's own preferences so both the receiver (no
 * Flutter yet) and Dart-driven updates read the same thing. Caption states
 * live in memory only: a fresh process starts every widget at rest.
 */
object KeyWidgetStore {
    private const val PREFS = "qunleashed_widgets"
    private const val PENDING = "pending_pin"

    private val states = HashMap<Int, String>()

    private fun prefs(context: Context) =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    private fun keyOf(widgetId: Int) = "w$widgetId"

    fun get(context: Context, widgetId: Int): WidgetKeyData? =
        prefs(context).getString(keyOf(widgetId), null)?.let(WidgetKeyData::fromJson)

    fun put(context: Context, widgetId: Int, key: WidgetKeyData) {
        prefs(context).edit().putString(keyOf(widgetId), key.toJson()).apply()
    }

    fun remove(context: Context, widgetId: Int) {
        prefs(context).edit().remove(keyOf(widgetId)).apply()
        states.remove(widgetId)
    }

    fun setPending(context: Context, key: WidgetKeyData) {
        prefs(context).edit().putString(PENDING, key.toJson()).apply()
    }

    /** Binds the key waiting on a pin request to the widget the launcher made. */
    fun commitPending(context: Context, widgetId: Int): Boolean {
        val store = prefs(context)
        val key = store.getString(PENDING, null)?.let(WidgetKeyData::fromJson) ?: return false
        store.edit().remove(PENDING).putString(keyOf(widgetId), key.toJson()).apply()
        return true
    }

    fun state(widgetId: Int): String = states[widgetId] ?: "idle"

    fun setState(widgetId: Int, state: String) {
        if (state == "idle") states.remove(widgetId) else states[widgetId] = state
    }
}
