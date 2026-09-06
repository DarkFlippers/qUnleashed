package com.darkflippers.qunleashed.widget

import android.appwidget.AppWidgetManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import com.darkflippers.qunleashed.MainActivity

/**
 * Widget taps and pin confirmations. A tap on a configured widget goes to
 * Dart on the shared engine — started cold here when the app is not running.
 * The receiver returns at once: broadcasts to one receiver are delivered in
 * series, so holding it would queue the next tap behind this one. A tap on an
 * unconfigured widget opens the app on the key picker.
 */
class KeyWidgetReceiver : BroadcastReceiver() {
    companion object {
        const val ACTION_TAP = "com.darkflippers.qunleashed.widget.TAP"
        const val ACTION_PIN_DONE = "com.darkflippers.qunleashed.widget.PIN_DONE"
        const val EXTRA_PICK_WIDGET = "widget_pick"
    }

    override fun onReceive(context: Context, intent: Intent) {
        val widgetId = intent.getIntExtra(
            AppWidgetManager.EXTRA_APPWIDGET_ID,
            AppWidgetManager.INVALID_APPWIDGET_ID,
        )
        if (widgetId == AppWidgetManager.INVALID_APPWIDGET_ID) return
        when (intent.action) {
            ACTION_PIN_DONE -> {
                KeyWidgetStore.commitPending(context, widgetId)
                KeyWidgetRenderer.update(context, widgetId)
            }
            ACTION_TAP -> onTap(context, widgetId)
        }
    }

    private fun onTap(context: Context, widgetId: Int) {
        val key = KeyWidgetStore.get(context, widgetId)
        if (key == null) {
            val open = Intent(context, MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                .putExtra(EXTRA_PICK_WIDGET, widgetId)
            context.startActivity(open)
            return
        }
        // Answer the tap before Dart is even up: a cold engine takes a moment
        // to boot, and the caption must move the instant the finger lifts.
        if (KeyWidgetStore.state(widgetId) == "idle") {
            KeyWidgetStore.setState(widgetId, "connecting")
            KeyWidgetRenderer.update(context, widgetId)
        }
        val engine = FlutterEngineHolder.getOrCreate(context, FlutterEngineHolder.ENTRYPOINT_WIDGET)
        HomeWidgetChannel.send(engine, widgetId, key)
    }
}
