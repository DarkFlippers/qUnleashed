package com.darkflippers.qunleashed

import android.content.Context
import android.location.GnssStatus
import android.location.LocationManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private const val ENGINE_ID = "qunleashed_main"
    }

    private val gnssChannel = "qunleashed/gnss"
    private var gnssMethodChannel: MethodChannel? = null
    private var locationManager: LocationManager? = null
    private var gnssCallback: GnssStatus.Callback? = null
    private var satellitesInUse: Int = -1

    override fun getCachedEngineId(): String {
        if (FlutterEngineCache.getInstance().get(ENGINE_ID) == null) {
            val engine = FlutterEngine(applicationContext)
            engine.dartExecutor.executeDartEntrypoint(
                DartExecutor.DartEntrypoint.createDefault(),
            )
            FlutterEngineCache.getInstance().put(ENGINE_ID, engine)
        }
        return ENGINE_ID
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
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

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
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
