package com.example.hap_nav

import android.Manifest
import android.content.BroadcastReceiver
import android.content.ContentValues.TAG
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.wifi.aware.AttachCallback
import android.net.wifi.aware.DiscoverySession
import android.net.wifi.aware.DiscoverySessionCallback
import android.net.wifi.aware.PeerHandle
import android.net.wifi.aware.PublishConfig
import android.net.wifi.aware.PublishDiscoverySession
import android.net.wifi.aware.ServiceDiscoveryInfo
import android.net.wifi.aware.SubscribeConfig
import android.net.wifi.aware.SubscribeDiscoverySession
import android.net.wifi.aware.WifiAwareManager
import android.net.wifi.aware.WifiAwareNetworkInfo
import android.net.wifi.aware.WifiAwareNetworkSpecifier
import android.net.wifi.aware.WifiAwareSession
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.annotation.RequiresApi
import androidx.core.app.ActivityCompat
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.net.Inet6Address
import java.net.ServerSocket

class WifiAwareService(
    private val context: Context,
    val onConnect: () -> Unit,
    val onDisconnect: () -> Unit,
    val onError: (String) -> Unit,
    val onMessageReceived: (String) -> Unit,
    val messageSendFailed: () -> Unit
) {
    private var hasWifiAwareFeature: Boolean = false

    private var currentSession: WifiAwareSession? = null

    private var publishDiscoverySession: PublishDiscoverySession? = null
    private var subscribeDiscoverySession: SubscribeDiscoverySession? = null

    private var wifiAwareManager: WifiAwareManager? = null

    private var connectivityManager: ConnectivityManager

    private var socket: ServerSocket? = null

    private var isEstablishingConnection = false

    private var peerAwareInfo: WifiAwareNetworkInfo? = null
    private var peerIpv6: Inet6Address? = null
    private var peerPort: Int? = null
    private var peerNetwork: Network? = null

    private var peerHandle: PeerHandle? = null

    private var discoveredPublishers: Set<PeerHandle> = emptySet()

    private var isConnected: Boolean = false

    private val networkCallback = object : ConnectivityManager.NetworkCallback() {
        override fun onAvailable(network: Network) {
            super.onAvailable(network)
            Log.d(TAG, "Network available.")
            peerNetwork = network
            isEstablishingConnection = false
            isConnected = true
            onConnect()
        }

        override fun onUnavailable() {
            super.onUnavailable()
            Log.d(TAG, "Network unavailable.")
            isEstablishingConnection = false
            isConnected = false
            onDisconnect()
        }

        override fun onCapabilitiesChanged(network: Network, networkCapabilities: NetworkCapabilities) {
            super.onCapabilitiesChanged(network, networkCapabilities)
            Log.d(TAG, "Network capabilities changed.")
            peerAwareInfo = networkCapabilities.transportInfo as WifiAwareNetworkInfo
            peerIpv6 = peerAwareInfo!!.peerIpv6Addr
            peerPort = peerAwareInfo!!.port
            isEstablishingConnection = false
        }

        override fun onLost(network: Network) {
            super.onLost(network)
            Log.d(TAG, "Network lost.")
            isEstablishingConnection = false
            onDisconnect()
            isConnected = false
        }
    }

    private val attachCallback = object : AttachCallback() {
        override fun onAttached(session: WifiAwareSession?) {
            Log.d(TAG, "Attached to session")
            currentSession = session
        }
        override fun onAttachFailed() {
            Log.e(TAG, "Session failed")
            currentSession = null
            onError("Session failed.")
        }
        override fun onAwareSessionTerminated() {
            Log.d(TAG, "Aware session terminated")
            currentSession = null
        }
    }

    private val discoverySessionCallback = object : DiscoverySessionCallback() {


        override fun onMessageReceived(peerHandle: PeerHandle?, message: ByteArray?) {
            if (message != null) {
                val msg = String(message)
                Log.d(TAG,"MESSAGE RECEIVED: $msg")
                if (msg == "COMPLETE_CONNECT" && subscribeDiscoverySession != null && peerHandle != null) {
                    establishConnectionWithPeer(peerHandle, subscribeDiscoverySession!!, null)
                } else if (msg == "INIT_CONNECT") {
                    socket = java.net.ServerSocket((0..65535).random())
                    socket!!.reuseAddress = true
                    socket
                    android.util.Log.d(android.content.ContentValues.TAG,"Establishing connection to peer")
                    if (publishDiscoverySession != null && !isEstablishingConnection && socket != null && peerHandle != null) {
                        establishConnectionWithPeer(peerHandle, publishDiscoverySession!!, socket?.localPort)
                    }
                } else if (peerNetwork != null) {
                    onMessageReceived(msg)
                }
            }
        }
    }

    init {
        wifiAwareManager = context.getSystemService(Context.WIFI_AWARE_SERVICE) as WifiAwareManager
        connectivityManager = context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager

        val filter = IntentFilter(WifiAwareManager.ACTION_WIFI_AWARE_STATE_CHANGED)
        val myReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) {
                // discard current sessions
                currentSession?.close()
                if (wifiAwareManager?.isAvailable == true) {
                    Log.d(TAG, "Received ACTION_WIFI_AWARE_STATE_CHANGED. Re-registering session.")
                    register()
                } else {
                    Log.e(TAG, "WIFI Aware Service is not available!")
                }
            }
        }
        context.registerReceiver(myReceiver, filter)
        register()
    }

    fun register() {
        if (wifiAwareManager != null) {
            Log.d(TAG, "Registering Wifi Aware")
            wifiAwareManager?.attach(attachCallback, null)
        } else {
            Log.e(TAG, "WifiAwareManager is null")
        }
    }

    fun subscribe(result: MethodChannel.Result) {
        if (ActivityCompat.checkSelfPermission(
                context,
                Manifest.permission.ACCESS_FINE_LOCATION
            ) != PackageManager.PERMISSION_GRANTED || ActivityCompat.checkSelfPermission(
                context,
                Manifest.permission.NEARBY_WIFI_DEVICES
            ) != PackageManager.PERMISSION_GRANTED
        ) {
            Log.e(TAG, "Required Permissions Not Granted")
            result.error("PERMISSION_DENIED", "Required permissions were not granted.", null)
            return
        }

        if (currentSession == null) {
            Log.e(TAG, "WIFI Aware Session is null!")
            result.error("Null Session", "Wifi Aware Session is null!", null)
            return
        }

        Log.d(TAG, "Subscribing to service")

        val config: SubscribeConfig = SubscribeConfig.Builder()
            .setServiceName("COMMANDER_SERVICE")
            .build()

        currentSession!!.subscribe(config, object : DiscoverySessionCallback() {
            override fun onSubscribeStarted(session: SubscribeDiscoverySession) {
                super.onSubscribeStarted(session)
                Log.d(TAG, "Did start subscribing")
                subscribeDiscoverySession = session
                result.success(null)
            }

            override fun onServiceDiscovered(
                peerHandle: PeerHandle?,
                serviceSpecificInfo: ByteArray?,
                matchFilter: MutableList<ByteArray>?
            ) {
                super.onServiceDiscovered(peerHandle, serviceSpecificInfo, matchFilter)
                if (subscribeDiscoverySession == null) {
                    Log.e(TAG, "Subscribe discovery session is null.")
                    return
                }
                if (peerHandle == null) {
                    Log.e(TAG, "Peer handle is null.")
                    return
                }
                if (isEstablishingConnection) {
                    Log.e(TAG, "Looks like we're already establishing a connection. Skipping INIT_CONNECT.")
                    return
                }
                Log.d(TAG,"Discovered publisher. Sending INIT_CONNECT message.")
                subscribeDiscoverySession!!.sendMessage(peerHandle, 0, "INIT_CONNECT".toByteArray())
                isEstablishingConnection = true
            }

            override fun onMessageReceived(peerHandle: PeerHandle?, message: ByteArray?) {
                super.onMessageReceived(peerHandle, message)
                if (peerHandle == null) {
                    Log.e(TAG, "Received message, but peer handle is null.")
                }
                if (message == null) {
                    Log.e(TAG, "Received message, but the content is null.")
                    return
                }
                if (subscribeDiscoverySession == null) {
                    Log.e(TAG, "Subscribe discover session is null. Cannot establish connection with publisher.")
                    return
                }
                val msg = String(message)
                Log.d(TAG, "Message received from publisher: $msg")
                if (msg == "COMPLETE_CONNECT") {
                    Log.d(TAG, "Establishing connection to publisher.")
                    establishConnectionWithPeer(peerHandle!!, subscribeDiscoverySession!!, null)
                } else {
                    onMessageReceived(msg)
                }
            }

            override fun onMessageSendFailed(messageId: Int) {
                super.onMessageSendFailed(messageId)
                if (isConnected) {
                    messageSendFailed()
                }
            }

            override fun onSessionTerminated() {
                super.onSessionTerminated()
                Log.d(TAG, "Session terminated.")
                onDisconnect()
            }

        }, null)
    }

    fun advertise(result: MethodChannel.Result) {
        if (ActivityCompat.checkSelfPermission(
                context,
                Manifest.permission.ACCESS_FINE_LOCATION
            ) != PackageManager.PERMISSION_GRANTED || ActivityCompat.checkSelfPermission(
                context,
                Manifest.permission.NEARBY_WIFI_DEVICES
            ) != PackageManager.PERMISSION_GRANTED
        ) {
            Log.e(TAG,"Required Permissions Not Granted")
            result.error("PERMISSION_DENIED", "Required permissions were not granted.", null)
            return
        }

        if (currentSession == null) {
            Log.e(TAG, "WIFI Aware Session is null!")
            result.error("Null Session", "Wifi Aware Session is null!", null)
            return
        }

        Log.d(TAG, "Advertising service")

        val config: PublishConfig = PublishConfig.Builder()
            .setServiceName("COMMANDER_SERVICE")
            .build()

        currentSession!!.publish(config, object : DiscoverySessionCallback() {
            override fun onPublishStarted(session: PublishDiscoverySession) {
                super.onPublishStarted(session)
                Log.d(TAG,"Service publish started.")
                publishDiscoverySession = session
                result.success(null)
            }

            override fun onMessageReceived(peerHandle: PeerHandle, message: ByteArray) {
                super.onMessageReceived(peerHandle, message)
                val msg = String(message);
                Log.d(TAG, "Message received from subscriber: $msg")

                if (msg == "INIT_CONNECT") {
                    socket = ServerSocket(0)
                    if (publishDiscoverySession == null) {
                        Log.e(TAG, "Publish discover session is null!")
                        return
                    }
                    if (socket == null) {
                        Log.e(TAG, "Publisher socket is null!")
                        return
                    }
                    if (isEstablishingConnection) {
                        Log.d(TAG,"Looks like we're already establishing a connection. Skipping this establish connection to peer.")
                        return
                    }
                    Log.d(TAG,"Establishing connection to subscriber.")
                    establishConnectionWithPeer(peerHandle, publishDiscoverySession!!, socket!!.localPort)
                } else {
                    onMessageReceived(msg)
                }
            }

            override fun onMessageSendFailed(messageId: Int) {
                super.onMessageSendFailed(messageId)
                if (isConnected) {
                    messageSendFailed()
                }
            }

            override fun onSessionTerminated() {
                super.onSessionTerminated()
                Log.d(TAG, "Session terminated.")
                onDisconnect()
            }
        }, null)
    }

    private fun establishConnectionWithPeer(peerHandle: PeerHandle, discoverySession: DiscoverySession, port: Int?) {
        val networkSpecifier: WifiAwareNetworkSpecifier = if (port == null) {
            WifiAwareNetworkSpecifier.Builder(discoverySession, peerHandle)
                .setPskPassphrase("somePassword")
                .build()
        } else {
            WifiAwareNetworkSpecifier.Builder(discoverySession, peerHandle)
                .setPskPassphrase("somePassword")
                .setPort(port)
                .build()
        }

        val myNetworkRequest = NetworkRequest.Builder()
            .addTransportType(NetworkCapabilities.TRANSPORT_WIFI_AWARE)
            .setNetworkSpecifier(networkSpecifier)
            .build()

        connectivityManager.requestNetwork(myNetworkRequest, networkCallback)
        isEstablishingConnection = true

        if (publishDiscoverySession != null) {
            Log.d(TAG,"Publisher requested connection. Sending COMPLETE_CONNECT message to subscriber.")
            publishDiscoverySession?.sendMessage(peerHandle, 2345, "COMPLETE_CONNECT".toByteArray())
        }

        this.peerHandle = peerHandle
    }

    fun disconnect(result: MethodChannel.Result) {
        if (subscribeDiscoverySession != null) {
            subscribeDiscoverySession!!.close()
            subscribeDiscoverySession = null
            discoveredPublishers = emptySet()
        }
        if (publishDiscoverySession != null) {
            publishDiscoverySession!!.close()
            publishDiscoverySession = null
        }
        isEstablishingConnection = false
        connectivityManager.unregisterNetworkCallback(networkCallback)
        result.success(null)
    }

    fun sendMessage(msg: String, result: MethodChannel.Result?) {
        if (peerHandle != null) {
            if (publishDiscoverySession != null) {
                publishDiscoverySession!!.sendMessage(peerHandle!!, 1553, msg.toByteArray())
                result?.success(null)
                return
            } else if (subscribeDiscoverySession != null) {
                subscribeDiscoverySession!!.sendMessage(peerHandle!!, 1553, msg.toByteArray())
                result?.success(null)
                return
            } else {
                Log.e(TAG, "Both Discovery Sessions are null!")
                result?.error("Error sending message.", "There is a problem with the device connection.", null)
                return
            }
        } else {
            Log.e(TAG, "Peer Handle is null!")
            result?.error("Error sending message", "Peer handle is null!", null);
            return
        }
    }
}