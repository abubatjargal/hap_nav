package com.example.hap_nav

import android.Manifest
import android.content.ContentValues.TAG
import android.content.pm.PackageManager
import android.location.Location
import android.os.Build
import android.os.Looper
import android.util.Log
import androidx.annotation.RequiresApi
import androidx.core.app.ActivityCompat
import com.google.android.gms.location.FusedLocationProviderClient
import com.google.android.gms.location.Granularity
import com.google.android.gms.location.LocationAvailability
import com.google.android.gms.location.LocationCallback
import com.google.android.gms.location.LocationRequest
import com.google.android.gms.location.LocationResult
import com.google.android.gms.location.LocationServices
import com.google.android.gms.location.Priority
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val PISON_CHANNEL = "pison/helper"
    private val WIFI_CHANNEL = "channels/wifi"

    private lateinit var pisonHelper: PisonHelper

    private lateinit var pisonMethodChannel: MethodChannel
    private lateinit var wifiMethodChannel: MethodChannel

    private lateinit var wifiAwareService: WifiAwareService

    private lateinit var imuStreamHandler: IMUStreamHandler
    private lateinit var gestureStreamHandler: GestureStreamHandler

    private lateinit var fusedLocationClient: FusedLocationProviderClient

    private val vulcanIMUChannel = "pison/telemetry"
    private val vulcanGestureChannel = "pison/gesture"

    private val locationCallback = object : LocationCallback() {
        override fun onLocationAvailability(p0: LocationAvailability) {
            super.onLocationAvailability(p0)
            Log.d(TAG, "Location Availability Changed: Available ${p0.isLocationAvailable}")
        }

        override fun onLocationResult(p0: LocationResult) {
            super.onLocationResult(p0)
            activity.runOnUiThread {
                wifiMethodChannel.invokeMethod("updateLocation", "${p0.lastLocation?.latitude}, ${p0.lastLocation?.longitude}")
            }
        }
    }

    @RequiresApi(Build.VERSION_CODES.S)
    private fun startListeningForLocation() {
        if (ActivityCompat.checkSelfPermission(
                this,
                Manifest.permission.ACCESS_FINE_LOCATION
            ) != PackageManager.PERMISSION_GRANTED && ActivityCompat.checkSelfPermission(
                this,
                Manifest.permission.ACCESS_COARSE_LOCATION
            ) != PackageManager.PERMISSION_GRANTED
        ) {
            Log.e(TAG, "ERROR: LOCATION PERMISSION MISSING")
            return
        }

        val locationRequest = LocationRequest.Builder(1000)
            .setPriority(Priority.PRIORITY_HIGH_ACCURACY)
            .setGranularity(Granularity.GRANULARITY_FINE)
            .build()

        fusedLocationClient.requestLocationUpdates(locationRequest, locationCallback, Looper.getMainLooper())
    }

    private fun stopListeningForLocation() {
        fusedLocationClient.removeLocationUpdates(locationCallback)
    }

    @RequiresApi(Build.VERSION_CODES.S)
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        wifiAwareService = WifiAwareService(this, onConnect = {
            activity.runOnUiThread {
                wifiMethodChannel.invokeMethod("onConnect", null)
            }
        },  onDisconnect = {
            activity.runOnUiThread {
                wifiMethodChannel.invokeMethod("onDisconnect", null)
            }
        }, onError = { errorMsg ->
            activity.runOnUiThread {
                wifiMethodChannel.invokeMethod("onError", errorMsg)
            }
        }, onMessageReceived = { msg ->
            activity.runOnUiThread {
                wifiMethodChannel.invokeMethod("receivedMessage", msg)
            }
        }, messageSendFailed = {
            activity.runOnUiThread {
                wifiMethodChannel.invokeMethod("messageSendFailed", null)
            }
        } )

        pisonHelper = PisonHelper()

        imuStreamHandler = IMUStreamHandler(this, pisonHelper)
        gestureStreamHandler = GestureStreamHandler(this, pisonHelper)

        pisonHelper.setIMUStreamHandler(imuStreamHandler)
        pisonHelper.setGestureStreamHandler(gestureStreamHandler)

        fusedLocationClient = LocationServices.getFusedLocationProviderClient(this)

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, vulcanIMUChannel)
            .setStreamHandler(imuStreamHandler)

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, vulcanGestureChannel)
            .setStreamHandler(gestureStreamHandler)

        pisonMethodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, PISON_CHANNEL)
        pisonMethodChannel.setMethodCallHandler { call, result ->
            when {
                call.method.equals("setupConnection") -> {
                    pisonHelper.setupConnection(applicationContext, call, result)
                }

                call.method.equals("disconnect") -> {
                    pisonHelper.disconnect(result)
                }

                call.method.equals("sendHaptic") -> {
                    pisonHelper.sendHaptic(call, result)
                }

                call.method.equals("subscribeToGestures") -> {
                    pisonHelper.subscribeToGestures()
                }

                call.method.equals("unsubscribeFromGestures") -> {
                    pisonHelper.unsubscribeFromGestures()
                }

                call.method.equals("updateGestureMapping") -> {
                    pisonHelper.updateGestureMapping(call, result)
                }
            }

            pisonHelper.methodChannel = pisonMethodChannel
        }

        wifiMethodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, WIFI_CHANNEL)
        wifiMethodChannel.setMethodCallHandler {
                call, result ->
            when (call.method) {
                "discoverWifiDevices" -> wifiAwareService.subscribe(result)
                "advertiseCommanderService" -> wifiAwareService.advertise(result)
                "disconnect" -> wifiAwareService.disconnect(result)
                "sendMsg" -> wifiAwareService.sendMessage(call.arguments as String, result)
                "startListeningForLocation" -> startListeningForLocation()
                "stopListeningForLocation" -> stopListeningForLocation()
            }
        }
    }
}