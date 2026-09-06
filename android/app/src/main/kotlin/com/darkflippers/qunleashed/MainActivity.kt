package com.darkflippers.qunleashed

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.location.GnssStatus
import android.location.LocationManager
import android.os.Build
import com.darkflippers.qunleashed.widget.FlutterEngineHolder
import com.darkflippers.qunleashed.widget.HomeWidgetChannel
import com.darkflippers.qunleashed.widget.KeyWidgetReceiver
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val gnssChannel = "qunleashed/gnss"
    private var gnssMethodChannel: MethodChannel? = null
    private var locationManager: LocationManager? = null
    private var gnssCallback: GnssStatus.Callback? = null
    private var satellitesInUse: Int = -1

    override fun getCachedEngineId(): String {
        FlutterEngineHolder.getOrCreate(this, FlutterEngineHolder.ENTRYPOINT_MAIN)
        return FlutterEngineHolder.ENGINE_ID
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // The engine may have been started cold by a widget tap: bring it up
        // to the full app now that there is a screen.
        HomeWidgetChannel.attach(this, flutterEngine)
        HomeWidgetChannel.activity = this
        HomeWidgetChannel.promote(flutterEngine)
        handleWidgetIntent(intent)
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, gnssChannel)
        gnssMethodChannel = channel
        channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "start" -> {
                        startGnss()
                        result.success(null)
                    }
                    "stop" -> {
                        stopGnss()
                        result.success(null)
                    }
                    "count" -> result.success(
                        if (satellitesInUse >= 0) satellitesInUse else null,
                    )
                    else -> result.notImplemented()
                }
            }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleWidgetIntent(intent)
    }

    private fun handleWidgetIntent(intent: Intent?) {
        if (intent == null) return
        val widgetId = intent.getIntExtra(
            KeyWidgetReceiver.EXTRA_PICK_WIDGET,
            AppWidgetManager.INVALID_APPWIDGET_ID,
        )
        if (widgetId == AppWidgetManager.INVALID_APPWIDGET_ID) return
        intent.removeExtra(KeyWidgetReceiver.EXTRA_PICK_WIDGET)
        FlutterEngineHolder.existing()?.let { HomeWidgetChannel.pick(it, widgetId) }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        if (HomeWidgetChannel.activity === this) HomeWidgetChannel.activity = null
        gnssMethodChannel?.setMethodCallHandler(null)
        gnssMethodChannel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    private fun startGnss() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N || gnssCallback != null) return
        val manager =
            getSystemService(Context.LOCATION_SERVICE) as? LocationManager ?: return
        val callback = object : GnssStatus.Callback() {
            override fun onSatelliteStatusChanged(status: GnssStatus) {
                var used = 0
                for (i in 0 until status.satelliteCount) {
                    if (status.usedInFix(i)) used++
                }
                satellitesInUse = used
            }
        }
        try {
            manager.registerGnssStatusCallback(callback, null)
            locationManager = manager
            gnssCallback = callback
        } catch (_: SecurityException) {
            satellitesInUse = -1
        }
    }

    private fun stopGnss() {
        val callback = gnssCallback
        if (callback != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            locationManager?.unregisterGnssStatusCallback(callback)
        }
        locationManager = null
        gnssCallback = null
        satellitesInUse = -1
    }

    override fun onDestroy() {
        stopGnss()
        super.onDestroy()
    }
}
