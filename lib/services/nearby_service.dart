import 'dart:async';
import 'dart:developer';
import 'dart:typed_data';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:hap_nav/utils/device_manager.dart';
import 'package:nearby_connections/nearby_connections.dart';
import 'package:shared_preferences/shared_preferences.dart';

class NearbyDevice {
  final String id;
  final String username;
  final String serviceId;

  NearbyDevice(this.id, this.username, this.serviceId);
}

class NearbyService {
  ValueNotifier<List<NearbyDevice>> nearbyDevices = ValueNotifier([]);
  ValueNotifier<String?> connectedDevice = ValueNotifier(null);
  ValueNotifier<bool?> connectionStatus = ValueNotifier(false);

  ValueNotifier<List<String>> connectedEndpoints = ValueNotifier([]);

  late final DeviceManager _deviceManager = GetIt.instance.get<DeviceManager>();

  Future<String> readDeviceName() async {
    final prefs = await SharedPreferences.getInstance();
    const key = 'deviceName';
    final value = prefs.getString(key);
    return value ?? "unknown device";
  }

  Future<void> startAdvertising() async {
    try {
      await Nearby().startAdvertising("commander", Strategy.P2P_CLUSTER,
          onConnectionInitiated: (String id, ConnectionInfo info) {
            log("Invite from $id");
            onConnectionInitiated(id);
          }, onConnectionResult: (String id, Status status) {
            switch (status) {
              case Status.CONNECTED:
                log("Connected to $id");
                connectedEndpoints.value = connectedEndpoints.value.toList()..add(id);
                connectionStatus.value = true;
                stopDiscovery();
                break;
              case Status.REJECTED:
                log("Connection rejected");
                connectionStatus.value = false;
                break;
              case Status.ERROR:
                log("Error when connecting");
                connectionStatus.value = false;
                break;
            }
          }, onDisconnected: (String id) {
            log("Disconnected from device $id");
            connectedEndpoints.value = connectedEndpoints.value.toList()..remove(id);
            connectionStatus.value = false;
          }, serviceId: "com.abu.haptic_designer");
    } catch (e) {
      log(e.toString());
    }
  }

  Future<void> startDiscovery() async {
    nearbyDevices.value = [];
    String deviceName = await readDeviceName();
    try {
      log("Attempting to start discovery");
      await Nearby().startDiscovery(deviceName, Strategy.P2P_CLUSTER,
          onEndpointFound: (String id, String username, String serviceId) {
            log("Found endpoint with id: $id, username: $username, and serviceId: $serviceId");
            var device = NearbyDevice(id, username, serviceId);
            var copyOfList = nearbyDevices.value.toList();
            copyOfList.add(device);
            nearbyDevices.value = copyOfList;
            onEndpointFound(id, username, serviceId);
          }, onEndpointLost: (String? id) {
            log("Lost endpoint connection to $id");
          }, serviceId: "com.abu.haptic_designer");

      connectionStatus.value = null;
    } catch (e) {
      log("Error starting discovery. ${e.toString()}");
    }
  }

  onEndpointFound(String id, String username, String serviceId) {
    Nearby().requestConnection(username, id, onConnectionInitiated: (id, info) {
      onConnectionInitiated(id);
    }, onConnectionResult: (id, status) {
      switch (status) {
        case Status.CONNECTED:
          log("Did Connect");
          connectedDevice.value = id;
          connectionStatus.value = true;
          stopDiscovery();
          _deviceManager.isParticipant.value = true;
          break;
        case Status.REJECTED:
          log("Did Reject");
          connectionStatus.value = false;
          _deviceManager.isParticipant.value = false;
          break;
        case Status.ERROR:
          log("Did Encounter Error");
          connectionStatus.value = false;
          _deviceManager.isParticipant.value = false;
          break;
      }
    }, onDisconnected: (id) {
      log("Did Disconnect");
      connectedDevice.value = null;
      connectionStatus.value = false;
      _deviceManager.isParticipant.value = false;
    });
  }

  void onConnectionInitiated(String endpointId) {
    log("Accepting invite");
    Nearby().acceptConnection(endpointId,
        onPayLoadRecieved: (String endpointId, Payload payload) {
          log("Did receive payload");
          payloadReceived(payload);
        }, onPayloadTransferUpdate:
            (String endpointId, PayloadTransferUpdate payloadTransferUpdate) {
          switch (payloadTransferUpdate.status) {
            case PayloadStatus.SUCCESS:
              log("Payload update: Success");
              break;
            case PayloadStatus.CANCELED:
              log("Payload update: Cancelled");
              break;
            case PayloadStatus.FAILURE:
              log("Payload update: Failed");
              break;
            case PayloadStatus.IN_PROGRESS:
              log("Payload update: In Progress");
              break;
            case PayloadStatus.NONE:
              log("Payload update: None");
              break;
          }
        });
  }

  void disconnectDevices() {
    if (connectedDevice.value == null) {
      log("Connected device is null");
    } else {
      Nearby().disconnectFromEndpoint(connectedDevice.value!).then((_) {
        connectionStatus.value = false;
        _deviceManager.isParticipant.value = false;
      });
    }
  }

  void payloadReceived(Payload payload) {
    String input = String.fromCharCodes(payload.bytes!);
    log("Received payload from ${payload.uri} : $input");
    _deviceManager.handleIncomingMessageFromCommander(input);
  }

  void sendToDevice(String payload) {
    for (String id in connectedEndpoints.value) {
      Nearby()
          .sendBytesPayload(id, Uint8List.fromList("$payload\r\n".codeUnits));
    }
  }

  void stopDiscovery() {
    Nearby().stopDiscovery();
  }

  void stopAdvertising() {
    Nearby().stopAdvertising();
  }
}
