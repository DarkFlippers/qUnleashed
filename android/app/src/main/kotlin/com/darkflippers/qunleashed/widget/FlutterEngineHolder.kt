package com.darkflippers.qunleashed.widget

import android.content.Context
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor

/**
 * The one Dart isolate of the process. The activity and the home-screen
 * widgets share it: whoever comes first creates it — the activity on `main`,
 * a widget tap on `widgetMain` — and the other side attaches to the same
 * engine, so a link brought up by a widget carries over into the app.
 */
object FlutterEngineHolder {
    const val ENGINE_ID = "qunleashed_main"
    const val ENTRYPOINT_MAIN = "main"
    const val ENTRYPOINT_WIDGET = "widgetMain"

    fun existing(): FlutterEngine? = FlutterEngineCache.getInstance().get(ENGINE_ID)

    fun getOrCreate(context: Context, entrypoint: String): FlutterEngine {
        existing()?.let { return it }
        val appContext = context.applicationContext
        val engine = FlutterEngine(appContext)
        val bundle = FlutterInjector.instance().flutterLoader().findAppBundlePath()
        engine.dartExecutor.executeDartEntrypoint(
            DartExecutor.DartEntrypoint(bundle, entrypoint),
        )
        FlutterEngineCache.getInstance().put(ENGINE_ID, engine)
        HomeWidgetChannel.attach(appContext, engine)
        return engine
    }
}
