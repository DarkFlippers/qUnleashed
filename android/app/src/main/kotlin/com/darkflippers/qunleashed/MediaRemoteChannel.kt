package com.darkflippers.qunleashed

import android.content.Context
import android.content.Intent
import android.media.MediaMetadata
import android.media.VolumeProvider
import android.media.session.MediaSession
import android.media.session.PlaybackState
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.KeyEvent
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Android MediaSession bridge used by Wrist Remote.
 *
 * A wearable can keep talking to Android as if it were controlling music while
 * qUnleashed turns those transport/volume commands into semantic media inputs
 * and forwards them to Dart over a MethodChannel.
 *
 * Gesture recognition lives in Dart so single taps only incur the double-tap
 * window when the corresponding double-tap action is actually assigned.
 *
 * This object is owned by the cached FlutterEngine rather than MainActivity, so
 * recreating or destroying the Activity does not tear down the MediaSession.
 */
class MediaRemoteChannel(
    context: Context,
    flutterEngine: FlutterEngine,
) {
    companion object {
        private const val CHANNEL = "qunleashed/media_remote"
        private const val TAG = "WristRemote"

        private const val ACTIONS =
            PlaybackState.ACTION_PLAY or
                PlaybackState.ACTION_PAUSE or
                PlaybackState.ACTION_PLAY_PAUSE or
                PlaybackState.ACTION_SKIP_TO_NEXT or
                PlaybackState.ACTION_SKIP_TO_PREVIOUS
    }

    private val appContext = context.applicationContext
    private val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
    private val mainHandler = Handler(Looper.getMainLooper())

    private var mediaSession: MediaSession? = null

    init {
        trace("bridge attached to FlutterEngine pid=${android.os.Process.myPid()}")
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    try {
                        start()
                        result.success(null)
                    } catch (error: Throwable) {
                        Log.e(TAG, "Failed to start MediaSession", error)
                        result.error("media_session_start_failed", error.message, null)
                    }
                }
                "stop" -> {
                    try {
                        stop()
                        result.success(null)
                    } catch (error: Throwable) {
                        Log.e(TAG, "Failed to stop MediaSession", error)
                        result.error("media_session_stop_failed", error.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun start() {
        if (mediaSession != null) {
            trace("start ignored: MediaSession already active")
            return
        }

        trace("creating MediaSession pid=${android.os.Process.myPid()}")
        val session = MediaSession(appContext, "qUnleashed Wrist Remote")
        // Publish ownership immediately so any cleanup path can release a
        // partially configured session. start() itself is synchronous on the
        // platform thread, so stop() cannot interleave with this block.
        mediaSession = session

        try {
            session.setCallback(
                object : MediaSession.Callback() {
                    override fun onPlay() = sendInput("playPause")

                    override fun onPause() = sendInput("playPause")

                    override fun onSkipToPrevious() = sendInput("previous")

                    override fun onSkipToNext() = sendInput("next")

                    override fun onMediaButtonEvent(mediaButtonIntent: Intent): Boolean {
                        @Suppress("DEPRECATION")
                        val event = mediaButtonIntent.getParcelableExtra<KeyEvent>(Intent.EXTRA_KEY_EVENT)
                            ?: return super.onMediaButtonEvent(mediaButtonIntent)
                        if (event.action != KeyEvent.ACTION_DOWN || event.repeatCount != 0) return true

                        // Returning true is intentional: it keeps the same key
                        // from falling through to onPlay/onPause/onSkipTo* and
                        // producing a second Flipper press.
                        return when (event.keyCode) {
                            KeyEvent.KEYCODE_MEDIA_PREVIOUS -> {
                                sendInput("previous")
                                true
                            }
                            KeyEvent.KEYCODE_MEDIA_NEXT -> {
                                sendInput("next")
                                true
                            }
                            KeyEvent.KEYCODE_MEDIA_PLAY,
                            KeyEvent.KEYCODE_MEDIA_PAUSE,
                            KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE,
                            -> {
                                sendInput("playPause")
                                true
                            }
                            else -> super.onMediaButtonEvent(mediaButtonIntent)
                        }
                    }
                },
                mainHandler,
            )

            session.setPlaybackState(
                PlaybackState.Builder()
                    .setActions(ACTIONS)
                    // Keep the fake player "playing" so it remains the preferred
                    // media-button target while Wrist Remote is explicitly enabled.
                    .setState(
                        PlaybackState.STATE_PLAYING,
                        PlaybackState.PLAYBACK_POSITION_UNKNOWN,
                        1.0f,
                    )
                    .build(),
            )
            session.setMetadata(
                MediaMetadata.Builder()
                    .putString(MediaMetadata.METADATA_KEY_TITLE, "Flipper Remote")
                    .putString(MediaMetadata.METADATA_KEY_ARTIST, "qUnleashed · Wrist Remote")
                    .putString(MediaMetadata.METADATA_KEY_ALBUM, "qUnleashed")
                    .build(),
            )
            session.setPlaybackToRemote(
                object : VolumeProvider(VolumeProvider.VOLUME_CONTROL_RELATIVE, 100, 50) {
                    override fun onAdjustVolume(direction: Int) {
                        when {
                            direction > 0 -> sendInput("volumeUp")
                            direction < 0 -> sendInput("volumeDown")
                        }
                    }
                },
            )
            session.isActive = true
            trace("MediaSession active")
        } catch (error: Throwable) {
            mediaSession = null
            runCatching { session.isActive = false }
            runCatching { session.release() }
            throw error
        }
    }

    private fun stop() {
        val session = mediaSession
        if (session == null) {
            trace("stop ignored: no MediaSession")
            return
        }

        // Clear first so even a release failure cannot leave future start()
        // calls believing this session is still usable.
        mediaSession = null
        trace("releasing MediaSession")
        try {
            session.isActive = false
        } finally {
            session.release()
        }
    }

    private fun sendInput(input: String) {
        trace("media command -> $input")
        mainHandler.post {
            channel.invokeMethod("button", input)
        }
    }

    private fun trace(message: String) {
        if (Log.isLoggable(TAG, Log.DEBUG)) {
            Log.d(TAG, message)
        }
    }
}
