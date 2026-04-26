package com.nikolareljin.spankmobile

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.content.pm.PackageManager
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.MediaPlayer
import android.os.Build
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.FlutterInjector
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.loader.FlutterLoader
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private lateinit var preferences: SharedPreferences
    private lateinit var sensorManager: SensorManager
    private lateinit var audioManager: AudioManager
    private lateinit var flutterLoader: FlutterLoader
    private var mediaPlayer: MediaPlayer? = null
    // Speakerphone state captured before any spank playback begins; null when idle.
    private var preSpeakerphoneState: Boolean? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        preferences = getSharedPreferences("spank_mobile", Context.MODE_PRIVATE)
        sensorManager = getSystemService(Context.SENSOR_SERVICE) as SensorManager
        audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        flutterLoader = FlutterInjector.instance().flutterLoader()

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "spank/methods",
        ).setMethodCallHandler(::handleMethod)

        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "spank/motion",
        ).setStreamHandler(MotionStreamHandler())
    }

    override fun onDestroy() {
        mediaPlayer?.release()
        mediaPlayer = null
        super.onDestroy()
    }

    private fun handleMethod(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "loadSettings" -> result.success(
                mapOf(
                    "threshold" to preferences.getFloat("threshold", 1.8f).toDouble(),
                    "sampleIntervalMs" to preferences.getInt("sampleIntervalMs", 40),
                    "cooldownMs" to preferences.getInt("cooldownMs", 1200),
                    "soundPack" to preferences.getString("soundPack", "pain"),
                    "volume" to preferences.getFloat("volume", 1.0f).toDouble(),
                    "dryRun" to preferences.getBoolean("dryRun", false),
                    "callMode" to preferences.getBoolean("callMode", false),
                    "audioMode" to preferences.getString("audioMode", "private"),
                ),
            )

            "saveSettings" -> {
                val args = call.arguments as? Map<*, *>
                if (args == null) {
                    result.error("bad_args", "Expected settings map.", null)
                    return
                }

                preferences.edit()
                    .putFloat("threshold", (args["threshold"] as Number).toFloat())
                    .putInt("sampleIntervalMs", (args["sampleIntervalMs"] as Number).toInt())
                    .putInt("cooldownMs", (args["cooldownMs"] as Number).toInt())
                    .putString("soundPack", args["soundPack"] as String)
                    .putFloat("volume", (args["volume"] as Number).toFloat())
                    .putBoolean("dryRun", args["dryRun"] as Boolean)
                    .putBoolean("callMode", args["callMode"] as Boolean)
                    .putString("audioMode", args["audioMode"] as String)
                    .apply()
                result.success(null)
            }

            "playAsset" -> {
                val args = call.arguments as? Map<*, *>
                val assetPath = args?.get("assetPath") as? String
                val volume = ((args?.get("volume") as? Number)?.toFloat() ?: 1.0f)
                    .coerceIn(0f, 1f)
                val audioMode = args?.get("audioMode") as? String ?: "shared"
                if (assetPath.isNullOrBlank()) {
                    result.error("bad_args", "Missing assetPath.", null)
                    return
                }

                try {
                    playAsset(assetPath, volume, audioMode)
                    result.success(null)
                } catch (err: Exception) {
                    result.error("playback_failed", err.message, null)
                }
            }

            "startForegroundService" -> {
                requestNotificationPermissionIfNeeded()
                val intent = Intent(this, SpankForegroundService::class.java)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    startForegroundService(intent)
                } else {
                    startService(intent)
                }
                result.success(null)
            }

            "stopForegroundService" -> {
                stopService(Intent(this, SpankForegroundService::class.java))
                result.success(null)
            }

            else -> result.notImplemented()
        }
    }

    private fun requestNotificationPermissionIfNeeded() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            if (ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS)
                != PackageManager.PERMISSION_GRANTED
            ) {
                ActivityCompat.requestPermissions(
                    this,
                    arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                    0,
                )
            }
        }
    }

    private fun playAsset(assetPath: String, volume: Float, audioMode: String) {
        // Restore speakerphone before releasing the old player: its completion
        // callback won't run once released, so routing would be left dangling.
        preSpeakerphoneState?.let { audioManager.isSpeakerphoneOn = it }
        mediaPlayer?.release()
        mediaPlayer = null

        val key = flutterLoader.getLookupKeyForAsset(assetPath)
        val descriptor = assets.openFd(key)
        val player = MediaPlayer()
        player.setDataSource(descriptor.fileDescriptor, descriptor.startOffset, descriptor.length)
        descriptor.close()

        val originalSpeakerOn = audioManager.isSpeakerphoneOn
        preSpeakerphoneState = originalSpeakerOn

        if (audioMode == "private") {
            // Route to earpiece — only the user hears it.
            audioManager.isSpeakerphoneOn = false
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                player.setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_VOICE_COMMUNICATION)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                        .build(),
                )
            } else {
                @Suppress("DEPRECATION")
                player.setAudioStreamType(AudioManager.STREAM_VOICE_CALL)
            }
        } else {
            // Route to loudspeaker — call mic picks it up, others hear it.
            audioManager.isSpeakerphoneOn = true
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                player.setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_MEDIA)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build(),
                )
            } else {
                @Suppress("DEPRECATION")
                player.setAudioStreamType(AudioManager.STREAM_MUSIC)
            }
        }

        player.setVolume(volume, volume)
        player.setOnCompletionListener {
            it.release()
            audioManager.isSpeakerphoneOn = originalSpeakerOn
            preSpeakerphoneState = null
            if (mediaPlayer === it) {
                mediaPlayer = null
            }
        }
        try {
            player.prepare()
            player.start()
        } catch (err: Exception) {
            audioManager.isSpeakerphoneOn = originalSpeakerOn
            preSpeakerphoneState = null
            player.release()
            throw err
        }
        mediaPlayer = player
    }

    private inner class MotionStreamHandler : EventChannel.StreamHandler, SensorEventListener {
        private var eventSink: EventChannel.EventSink? = null
        private var sampleIntervalMs: Int = 40
        private var lastEmitMs: Long = 0

        override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
            sampleIntervalMs = ((arguments as? Map<*, *>)?.get("sampleIntervalMs") as? Number)
                ?.toInt()
                ?.coerceAtLeast(16)
                ?: 40
            eventSink = events

            val sensor = sensorManager.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)
            if (sensor == null) {
                events.error("sensor_unavailable", "Accelerometer is not available.", null)
                eventSink = null
                return
            }

            lastEmitMs = 0
            sensorManager.registerListener(this, sensor, sampleIntervalMs * 1000)
        }

        override fun onCancel(arguments: Any?) {
            sensorManager.unregisterListener(this)
            eventSink = null
        }

        override fun onSensorChanged(event: SensorEvent) {
            val sink = eventSink ?: return
            val nowMs = System.currentTimeMillis()
            if (lastEmitMs != 0L && nowMs - lastEmitMs < sampleIntervalMs) {
                return
            }

            lastEmitMs = nowMs
            sink.success(
                mapOf(
                    "timestampMs" to nowMs,
                    "x" to event.values[0].toDouble(),
                    "y" to event.values[1].toDouble(),
                    "z" to event.values[2].toDouble(),
                ),
            )
        }

        override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) = Unit
    }
}
