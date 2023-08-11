package com.example.hap_nav
import android.app.Activity
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.EventChannel.StreamHandler

class IMUStreamHandler(activity: Activity, pisonHelper: PisonHelper) : StreamHandler {
    private var eventSink: EventChannel.EventSink? = null
    private lateinit var activity: Activity
    private lateinit var pisonHelper: PisonHelper

    init {
        this.activity = activity
        this.pisonHelper = pisonHelper
    }

    fun sink(event: Float) {
        activity.runOnUiThread {
            eventSink?.success(event)
        }
    }

    override fun onListen(args: Any?, event: EventChannel.EventSink?) {
        eventSink = event
        pisonHelper.subscribeToIMU()
    }

    override fun onCancel(args: Any?) {
        eventSink = null
        pisonHelper.unsubscribeFromIMU()
    }
}