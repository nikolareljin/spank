package com.nikolareljin.spankmobile

import android.content.Context
import android.content.SharedPreferences
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.MediaPlayer
import android.os.Build
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
    private lateinit var flutterLoader: FlutterLoader
    private var mediaPlayer: MediaPlayer? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        preferences = getSharedPreferences("spank_mobile", Context.MODE_PRIVATE)
        sensorManager = getSystemService(Context.SENSOR_SERVICE) as SensorManager
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
                    .apply()
                result.success(null)
            }

            "playAsset" -> {
                val args = call.arguments as? Map<*, *>
                val assetPath = args?.get("assetPath") as? String
                val volume = ((args?.get("volume") as? Number)?.toFloat() ?: 1.0f)
                    .coerceIn(0f, 1f)
                if (assetPath.isNullOrBlank()) {
                    result.error("bad_args", "Missing assetPath.", null)
                    return
                }

                try {
                    playAsset(assetPath, volume)
                    result.success(null)
                } catch (err: Exception) {
                    result.error("playback_failed", err.message, null)
                }
            }

            else -> result.notImplemented()
        }
    }

    private fun playAsset(assetPath: String, volume: Float) {
        mediaPlayer?.release()
        mediaPlayer = null

        val key = flutterLoader.getLookupKeyForAsset(assetPath)
        val descriptor = assets.openFd(key)
        val player = MediaPlayer()
        player.setDataSource(descriptor.fileDescriptor, descriptor.startOffset, descriptor.length)
        descriptor.close()

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

        player.setVolume(volume, volume)
        player.setOnCompletionListener {
            it.release()
            if (mediaPlayer === it) {
                mediaPlayer = null
            }
        }
        player.prepare()
        player.start()
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
