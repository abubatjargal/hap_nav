package com.example.hap_nav
import android.app.Activity
import io.flutter.plugin.common.EventChannel

class GestureStreamHandler(activity: Activity, pisonHelper: PisonHelper) : EventChannel.StreamHandler {
    private var eventSink: EventChannel.EventSink? = null
    private lateinit var activity: Activity
    private lateinit var pisonHelper: PisonHelper

    init {
        this.activity = activity
        this.pisonHelper = pisonHelper
    }

    fun sink(event: String) {
        activity.runOnUiThread {
            eventSink?.success(event)
        }
    }

    override fun onListen(args: Any?, event: EventChannel.EventSink?) {
        eventSink = event
        pisonHelper.subscribeToGestures()
    }

    override fun onCancel(args: Any?) {
        eventSink = null
        pisonHelper.unsubscribeFromGestures()
    }
}