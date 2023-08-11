package com.example.hap_nav

import android.app.Activity
import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import com.badoo.reaktive.disposable.CompositeDisposable
import com.badoo.reaktive.disposable.Disposable
import com.badoo.reaktive.observable.distinctUntilChanged
import com.badoo.reaktive.observable.subscribe
import com.pison.core.client.*
import com.pison.core.shared.connection.*
import com.pison.core.shared.haptic.*
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import kotlinx.coroutines.GlobalScope
import kotlinx.coroutines.launch
import java.io.File
import java.io.FileOutputStream

class PisonHelper: FlutterPlugin, ActivityAware, MethodCallHandler {
    private final var TAG = "PisonHelper"

    private lateinit var context: Context
    private lateinit var activity: Activity

    lateinit var methodChannel: MethodChannel

    private var connectionsDisposable: Disposable? = null
    private var deviceMonitorDisposable: Disposable? = null

    private var imuStreamHandler: IMUStreamHandler? = null
    private var gestureStreamHandler: GestureStreamHandler? = null

    private var gestureDisposable: Disposable? = null
    private var imuDisposable: Disposable? = null

    private var INEHMappedHaptic: String? = null
    private var FHEHMappedHaptic: String? = null
    private var TEHMappedHaptic: String? = null

    private lateinit var pisonServer: PisonRemoteServer
    private var pisonRemoteDevice: PisonRemoteClassifiedDevice? = null

    var knownGestures: List<String> = listOf("DEBOUNCE_LDA_INEH")

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        Log.d(TAG, "Did attach to engine!")
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        TODO("Not yet implemented")
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        Log.d(TAG, "Did attach to activity!")
    }

    override fun onDetachedFromActivity() {
        TODO("Not yet implemented")
    }

    override fun onDetachedFromActivityForConfigChanges() {
        TODO("Not yet implemented")
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        TODO("Not yet implemented")
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        TODO("Not yet implemented")
    }

    fun flushExistingLogs() {
        val file = File(context.filesDir, "sessionLog.txt")
        val result = file.delete()
        if (result) {
            Log.d(TAG, "Flushed file successfully.")
        } else {
            Log.d(TAG, "Failed to flush file.")
        }
    }

    fun setupConnection(appContext: Context, call: MethodCall, result: MethodChannel.Result) {
        Log.d(TAG, "Setting up connection..")
        val sdk = newPisonSdkInstance(appContext)
        pisonServer = sdk.bindToLocalServer()

        connectionsDisposable?.dispose()
        connectionsDisposable = pisonServer.monitorConnections().subscribe(onNext = {
            when (it) {
                is ConnectedDeviceUpdate -> {
                    onDeviceConnected(it.connectedDevice)
                    result.success(true)
                }
                is DisconnectedDeviceUpdate -> {
                    Log.d(TAG, "Pison device disconnected!")
                    wearableConnectionUpdate(false);
                }
                is ConnectedFailedUpdate -> {
                    println("Error connecting to Pison Device: ${it.reason}")
                    wearableConnectionUpdate(false);
                }
            }
        }, onError = {
            Log.d(TAG, "error while monitoring connections: $it")
            result.error("Error monitoring connection.", it.message, null)
        })
    }

    fun disconnect(result: MethodChannel.Result) {
        connectionsDisposable?.dispose();
        result.success(null);
    }

    private fun onDeviceConnected(connectedDevice: ConnectedDevice) {
        Log.d(TAG, "Device connected.")

        deviceMonitorDisposable?.dispose()

        deviceMonitorDisposable =
            pisonServer.monitorDevice(connectedDevice).subscribe(onNext = { remoteDevice ->
                pisonRemoteDevice = remoteDevice

                GlobalScope.launch {
                    pisonRemoteDevice?.sendHaptic(HapticOnCommand(0))
                }

                wearableConnectionUpdate(true);
            })
    }

    fun setIMUStreamHandler(handler: IMUStreamHandler) {
        this.imuStreamHandler = handler
    }

    fun subscribeToIMU() {
        imuDisposable?.dispose()
        imuDisposable = CompositeDisposable()

        if (pisonRemoteDevice != null) {
            pisonRemoteDevice!!.monitorImu().distinctUntilChanged().subscribe(onNext = { imu ->
                writeToFile("IMU:${System.currentTimeMillis()}|GYRO_X:${imu.gyro.x}|GYRO_X:${imu.gyro.x}|GYRO_Z:${imu.gyro.z}|ACC_X:${imu.acceleration.x}|ACC_Y:${imu.acceleration.y}|ACC_Z:${imu.acceleration.z}")
            }, onComplete = {
                Log.d(TAG,"MONITOR DEVICE FRAMES HAS COMPLETED.")
            }).also { (imuDisposable as CompositeDisposable).add(it) }

            Log.d(TAG, "Did subscribe to IMU.")
        }

        flushExistingLogs()
    }

    fun unsubscribeFromIMU() {
        Log.d(TAG, "Did unsubscribe from IMU.")
        imuDisposable?.dispose()
    }

    fun setGestureStreamHandler(handler: GestureStreamHandler) {
        this.gestureStreamHandler = handler
    }

    fun subscribeToGestures() {
        gestureDisposable?.dispose()
        gestureDisposable = CompositeDisposable()

        if (pisonRemoteDevice != null) {
            pisonRemoteDevice!!.monitorFrameTags().distinctUntilChanged().subscribe(onNext = { frameTag ->
                if (
                    frameTag.first() == "SHAKE_N_INEH") {

                    gestureStreamHandler?.sink(frameTag.first())
                    writeToFile("GESTURE|${System.currentTimeMillis()}:${frameTag.first()}")
                }
            }).also { (gestureDisposable as CompositeDisposable).add(it) }

            Log.d(TAG, "Did subscribe to gestures.")
        }
    }

    fun unsubscribeFromGestures() {
        Log.d(TAG, "Did unsubscribe from gestures.")
        gestureDisposable?.dispose()
    }

    fun updateGestureMapping(call: MethodCall, result: MethodChannel.Result) {
        Log.d(TAG, "MAPPING UPDATED: ${call.arguments}")
        if (call.argument<String>("INEHMappedHaptic")?.isNotEmpty() == true) {
            INEHMappedHaptic = call.argument<String>("INEHMappedHaptic")
        }
        if (call.argument<String>("FHEHMappedHaptic")?.isNotEmpty() == true) {
            FHEHMappedHaptic = call.argument<String>("FHEHMappedHaptic")
        }
        if (call.argument<String>("TEHMappedHaptic")?.isNotEmpty() == true) {
            TEHMappedHaptic = call.argument<String>("TEHMappedHaptic")
        }
    }

    fun sendHaptic(call: MethodCall, result: MethodChannel.Result) {
        val hapticEffectString = call.argument<String>("hapticEffect")

        if (pisonRemoteDevice == null) {
            Log.d(TAG, "No device is connected.")
            result.error("No device connected", null, null)
        } else {
            Log.d(TAG, "Doing haptic stuff.")

            if (hapticEffectString != null) {
                if (hapticEffectString.isNotEmpty()) {
                    Log.d(TAG, "Attempting send haptic $hapticEffectString.")

                    sendHapticFor(hapticEffectString)

                    result.success("Did haptic")
                } else {
                    Log.d(TAG, "Invalid parameters. (Haptic Effect: $hapticEffectString)")
                }
            } else {
                Log.d(TAG, "No haptic effect was provided.")
            }
        }
    }

    private fun sendHapticFor(effectString: String) {
        when(effectString) {
            "subtle1" -> {
                GlobalScope.launch {
                    pisonRemoteDevice?.sendHaptic(HapticQueueCommand(
                        listOf(
                            HapticQueueStep(100, 25, 500),
                            HapticQueueStep(100, 25, 500),
                            HapticQueueStep(100, 25, 1500),
                            HapticQueueStep(100, 25, 500),
                            HapticQueueStep(100, 25, 500),
                            HapticQueueStep(100, 25, 1500),
                        )
                    ))
                }
            }
            "subtle2" -> {
                GlobalScope.launch {
                    pisonRemoteDevice?.sendHaptic(HapticQueueCommand(
                        listOf(
                            HapticQueueStep(100, 25, 50),
                            HapticQueueStep(100, 25, 50),
                            HapticQueueStep(100, 25, 300),
                            HapticQueueStep(100, 25, 50),
                            HapticQueueStep(100, 25, 50),
                            HapticQueueStep(100, 25, 50),
                        )
                    ))
                }
            }
            "subtle3" -> {
                GlobalScope.launch {
                    for (i in 1..4) {
                        pisonRemoteDevice?.sendHaptic(HapticQueueCommand(
                            listOf(
                                HapticQueueStep(100, 25, 300),
                                HapticQueueStep(100, 25, 300),
                                HapticQueueStep(100, 25, 250),
                                HapticQueueStep(100, 25, 200),
                                HapticQueueStep(100, 25, 150),
                                HapticQueueStep(100, 25, 1000),
                            )
                        ))
                    }
                }
            }
            "medium1" -> {
                GlobalScope.launch {
                    for (i in 1..2) {
                        pisonRemoteDevice?.sendHaptic(HapticQueueCommand(
                            listOf(
                                HapticQueueStep(100, 100, 250),
                                HapticQueueStep(100, 50, 150),
                                HapticQueueStep(100, 50, 250),
                                HapticQueueStep(100, 100, 750),
                            )
                        ))
                    }
                }
            }
            "medium2" -> {
                GlobalScope.launch {
                    for (i in 1..4) {
                        pisonRemoteDevice?.sendHaptic(HapticQueueCommand(
                            listOf(
                                HapticQueueStep(100, 50, 125),
                                HapticQueueStep(100, 27, 75),
                                HapticQueueStep(100, 27, 125),
                                HapticQueueStep(100, 50, 375),
                            )
                        ))
                    }
                }
            }
            "strong1" -> {
                GlobalScope.launch {
                    for (i in 1..20) {
                        pisonRemoteDevice?.sendHaptic(HapticPulseCommand(100, 50))
                        pisonRemoteDevice?.sendHaptic(HapticPulseCommand(0, 50))
                    }
                }
            }
            "strong2" -> {
                GlobalScope.launch {
                    pisonRemoteDevice?.sendHaptic(HapticBurstCommand(100, 50, 60))
                }
            }
            "strong3" -> {
                GlobalScope.launch {
                    for (i in 1..2) {
                        pisonRemoteDevice?.sendHaptic(HapticQueueCommand(
                            listOf(
                                HapticQueueStep(100, 25, 100),
                                HapticQueueStep(100, 25, 100),
                                HapticQueueStep(100, 100, 200),
                            )
                        ))
                    }
                }
            }
        }
    }

    private fun wearableConnectionUpdate(isConnected: Boolean) {
        Handler(Looper.getMainLooper()).post {
            methodChannel.invokeMethod("wearableConnectionUpdate", isConnected)
        }
    }

    private fun writeToFile(input: String) {
        var file = File(context.filesDir, "sessionLog.txt")
        FileOutputStream(file, true).bufferedWriter().use { out ->
            out.write(input + "\n")
        }
    }
}