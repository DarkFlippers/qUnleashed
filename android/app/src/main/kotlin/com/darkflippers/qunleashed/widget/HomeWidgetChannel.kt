package com.darkflippers.qunleashed.widget

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Bridge between the widgets and Dart. Dart serves taps (`send`, `pick`),
 * turns a cold isolate into the app (`promote`) and reports the caption
 * state; the native side stores, pins and draws the widgets.
 */
object HomeWidgetChannel {
    private const val NAME = "qunleashed/home_widget"

    private val channels = HashMap<FlutterEngine, MethodChannel>()

    fun attach(context: Context, engine: FlutterEngine) {
        if (channels.containsKey(engine)) return
        val appContext = context.applicationContext
        val channel = MethodChannel(engine.dartExecutor.binaryMessenger, NAME)
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "pin" -> result.success(pin(appContext, call.arguments))
                "configure" -> {
                    val widgetId = call.argument<Int>("widgetId")
                    val key = WidgetKeyData.fromArguments(call.arguments)
                    if (widgetId == null || key == null) {
                        result.error("bad_args", "widgetId and key are required", null)
                    } else {
                        KeyWidgetStore.put(appContext, widgetId, key)
                        KeyWidgetRenderer.update(appContext, widgetId)
                        result.success(null)
                    }
                }
                "state" -> {
                    val widgetId = call.argument<Int>("widgetId")
                    val state = call.argument<String>("state")
                    if (widgetId == null || state == null) {
                        result.error("bad_args", "widgetId and state are required", null)
                    } else {
                        KeyWidgetStore.setState(widgetId, state)
                        KeyWidgetRenderer.update(appContext, widgetId)
                        result.success(null)
                    }
                }
                "settings" -> {
                    WidgetSettings.save(appContext, call.arguments)
                    KeyWidgetRenderer.updateAll(appContext)
                    result.success(null)
                }
                "palette" -> result.success(MaterialPalette.of(appContext)?.toMap())
                else -> result.notImplemented()
            }
        }
        channels[engine] = channel
    }

    fun send(engine: FlutterEngine, widgetId: Int, key: WidgetKeyData) {
        val args = HashMap<String, Any>(key.toMap())
        args["widgetId"] = widgetId
        channels[engine]?.invokeMethod("send", args)
    }

    fun pick(engine: FlutterEngine, widgetId: Int) {
        channels[engine]?.invokeMethod("pick", mapOf("widgetId" to widgetId))
    }

    fun promote(engine: FlutterEngine) {
        channels[engine]?.invokeMethod("promote", null)
    }

    private fun pin(context: Context, arguments: Any?): Boolean {
        val key = WidgetKeyData.fromArguments(arguments) ?: return false
        val manager = AppWidgetManager.getInstance(context)
        if (!manager.isRequestPinAppWidgetSupported) return false
        KeyWidgetStore.setPending(context, key)
        val done = Intent(context, KeyWidgetReceiver::class.java)
            .setAction(KeyWidgetReceiver.ACTION_PIN_DONE)
        val callback = PendingIntent.getBroadcast(
            context,
            0,
            done,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val provider = ComponentName(context, KeyWidgetProvider::class.java)
        return manager.requestPinAppWidget(provider, null, callback)
    }
}
