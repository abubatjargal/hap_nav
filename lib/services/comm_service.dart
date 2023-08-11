import 'dart:async';
import 'dart:convert';
import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';
import 'package:hap_nav/utils/device_manager.dart';

import '../utils/log_file_output.dart';

class CommService {
  static const wifiDirectPlatformChannel = MethodChannel('channels/wifi');
  static const connectionTimeoutDuration = 30;

  late final _deviceManager = GetIt.instance<DeviceManager>();

  Timer? connectionAuditTimer;

  ValueNotifier<bool?> connected = ValueNotifier(false);
  ValueNotifier<String?> connectionQuality = ValueNotifier(null);

  late final LogFileOutput _logger = GetIt.instance<LogFileOutput>();

  CommService() {
    wifiDirectPlatformChannel.setMethodCallHandler(methodHandler);
  }

  Future<dynamic> methodHandler(MethodCall methodCall) async {
    switch (methodCall.method) {
      case "onConnect":
        log("Connected!");
        connected.value = true;
        return;
      case "onDisconnect":
        log("Disconnected!");
        connected.value = false;
        if (_deviceManager.isCommander.value) {
          _deviceManager.alertMessage.value = "Participant disconnected";
        }
        connectionAuditTimer?.cancel();
        return;
      case "onError":
        final msg = methodCall.arguments as String;
        log("Error! $msg");
        if (_deviceManager.isCommander.value) {
          _deviceManager.errorMessage.value = "Participant connected";
        }
        connectionAuditTimer?.cancel();
        return;
      case "receivedMessage":
        _deviceManager.handleIncomingMessageFromCommander(methodCall.arguments as String);
        return;
      case "messageSendFailed":
        log("MESSAGE FAILED TO SEND!");
        if (_deviceManager.isCommander.value) {
          _deviceManager.errorMessage.value = "Message failed to send. Please check connection and try again.";
        }
        return;
      case "updateLocation":
        final position = methodCall.arguments as String;
        if (_deviceManager.isRecordingParticipantLocation.value && position.isNotEmpty) {
          _logger.logToFile("PARTICIPANT POSITION, $position, ${_deviceManager.convertCurrentTimeStamp()}");
        }
        if (connected.value != null && connected.value!) {
          sendMessage(position);
        }
    }
  }

  Future<void> sendMessage(String  message) async {
    try {
      await wifiDirectPlatformChannel.invokeMethod("sendMsg", message);
    } on PlatformException catch (e) {
      log("Error sending message: $e");
    }
  }

  Future<void> discoverWifiDevices() async {
    try {
      connected.value = null;
      await wifiDirectPlatformChannel.invokeMethod("discoverWifiDevices");
    } on PlatformException catch (e) {
      log("Error starting wifi device discovery: $e");
    }
  }

  Future<void> advertiseCommanderService() async {
    try {
      await wifiDirectPlatformChannel.invokeMethod("advertiseCommanderService");
    } on PlatformException catch (e) {
      log("Error advertising commander service: $e");
    }
  }

  Future<void> disconnect() async {
    try {
      connected.value = null;
      await wifiDirectPlatformChannel.invokeMethod("disconnect").then((value) => {
        connected.value = false
      }).onError((error, stackTrace) => {
        connected.value = false,
      });
      connectionAuditTimer?.cancel();
    } on PlatformException catch (e) {
      log("Error advertising commander service: $e");
    }
  }

  Future<void> startListeningForLocation() async {
    try {
      await wifiDirectPlatformChannel.invokeMethod("startListeningForLocation");
    } on PlatformException catch (e) {
      log("Error starting to listen for location: $e");
    }
  }

  Future<void> stopListeningForLocation() async {
    try {
      await wifiDirectPlatformChannel.invokeMethod("stopListeningForLocation");
    } on PlatformException catch (e) {
      log("Error stopping listening for location: $e");
    }
  }
}