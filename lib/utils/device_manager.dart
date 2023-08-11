import 'dart:async';
import 'dart:developer';
import 'dart:ffi';
import 'package:firebase_core/firebase_core.dart';
import 'package:get/get.dart';
import 'package:get/get_core/src/get_main.dart';
import 'package:hap_nav/services/comm_service.dart';
import 'package:hap_nav/utils/firebase_options.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';
import 'package:hap_nav/utils/log_file_output.dart';
import 'package:hap_nav/services/ble_service.dart';
import 'package:hap_nav/services/nearby_service.dart';
import 'package:hap_nav/services/usb_service.dart';
import 'package:hap_nav/views/navigation.dart';
import 'package:intl/intl.dart';
import 'package:maps_toolkit/maps_toolkit.dart';
import 'package:permission_handler/permission_handler.dart';
import 'enums.dart';

class DeviceManager with WidgetsBindingObserver {
  static const platform = MethodChannel('pison/helper');

  final LogFileOutput _logger = GetIt.instance<LogFileOutput>();
  final UsbService usbService = UsbService();
  final BleService bleService = BleService();
  final NearbyService nearbyService = NearbyService();
  late final CommService commService = GetIt.instance<CommService>();

  ValueNotifier<String> deviceConnectionStatus = ValueNotifier("None connected");

  ValueNotifier<bool> isArduinoConnected = ValueNotifier(false);

  ValueNotifier<HapticEffectType?> selectedHapticEffect = ValueNotifier(null);

  ValueNotifier<HapticOutputTarget?> hapticOutputDevice = ValueNotifier(null);

  ValueNotifier<String> receivedInput = ValueNotifier("");

  HapticMotorType? hapticMotorType = HapticMotorType.lf;

  ValueNotifier<bool> isPisonWearableConnected = ValueNotifier(false);
  bool isGestureDetectionEnabled = false;

  ValueNotifier<bool> isCommander = ValueNotifier(false);
  ValueNotifier<bool> isParticipant = ValueNotifier(false);

  ValueNotifier<ParticipantPosition?> lastKnownPosition = ValueNotifier(null);
  ValueNotifier<DateTime?> lastUpdateDate = ValueNotifier(null);

  List<int> updateIntervalHistory = [];

  ValueNotifier<bool> isRecordingParticipantLocation = ValueNotifier(false);

  ValueNotifier<String?> errorMessage = ValueNotifier(null);
  ValueNotifier<String?> alertMessage = ValueNotifier(null);

  ValueNotifier<bool> isSessionActive = ValueNotifier(false);

  DeviceManager() {
    platform.setMethodCallHandler((MethodCall call) async {
      switch (call.method) {
        case "wearableConnectionUpdate":
        // Handle changes to Pison wearable connection
          bool isConnected = call.arguments;
          log("Did receive wearable update $isConnected");
          if (isConnected) {
            isPisonWearableConnected.value = isConnected;
            hapticOutputDevice.value = HapticOutputTarget.vulcan;
          } else {
            isPisonWearableConnected.value = false;
            hapticOutputDevice.value = null;
          }
          return;

        case "deviceListUpdate":
          return;
      }
    });

    verifyPermissions();
    initFirebase();

    isParticipant.addListener(() {
      if (isParticipant.value) {
        startTrackingLocation();
      } else {
        commService.disconnect();
        stopTrackingLocation();
      }
    });

    isCommander.addListener(() {
      if (isCommander.value) {
        commService.advertiseCommanderService();
      } else {
        commService.disconnect;
      }
    });
  }

  Future<void> initFirebase() async {
    await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform);
  }

  Future<void> verifyPermissions() async {
    await [
      Permission.bluetooth,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.bluetoothAdvertise,
      Permission.location,
      Permission.nearbyWifiDevices,
      Permission.storage,
      Permission.manageExternalStorage
    ].request();
  }

  void startRecordingParticipantLocation() {
    isRecordingParticipantLocation.value = true;
  }

  void stopRecordingParticipantLocation() {
    isRecordingParticipantLocation.value = false;
  }

  void refreshDeviceConnectionStatus() {
    if (isArduinoConnected.value) {
      deviceConnectionStatus.value = "Arduino Connected";
    } else if (isPisonWearableConnected.value) {
      deviceConnectionStatus.value = "Vulcan Connected";
    }
  }

  void sendHaptic() {
    switch (hapticOutputDevice.value) {
      case HapticOutputTarget.arduino:
        _sendHapticToArduino();
        break;
      case HapticOutputTarget.vulcan:
        _sendHapticToPison();
        break;
      case null:
        log("Haptic Output Device is null!");
        break;
    }
  }

  void startTrackingLocation() {
    log("Enabling position tracking");
    commService.startListeningForLocation();
    // _locationService.startTrackingPosition();
  }

  void stopTrackingLocation() {
    log("Disabling position tracking");
    commService.stopListeningForLocation();
    // _locationService.stopTrackingPosition();
  }

  void startSession() {
    isSessionActive.value = true;
    commService.sendMessage("START SESSION, ${lastKnownPosition.value?.latitude}, ${lastKnownPosition.value?.longitude}, ${convertCurrentTimeStamp()}");
    HapticFeedback.lightImpact();
  }

  void stopSession() {
    isSessionActive.value = false;
    commService.sendMessage("STOP SESSION, ${lastKnownPosition.value?.latitude}, ${lastKnownPosition.value?.longitude}, ${convertCurrentTimeStamp()}");
    HapticFeedback.lightImpact();
  }

  String convertCurrentTimeStamp() {
    DateFormat format = DateFormat("kk:mm:ss.SSS");
    return format.format(DateTime.now());
  }

  // PARTICIPANT METHODS

  Future<void> handleIncomingMessageFromCommander(String input) async {
    // If the input contains a comma, it is likely the participant position
    log("Handling incoming message $input");
    if (input.contains("LEFT")) {
      sendLeftHaptic(input);
      _logger.logToFile("$input, ${convertCurrentTimeStamp()}");
    } else if (input.contains("RIGHT")) {
      sendRightHaptic(input);
      _logger.logToFile("$input, ${convertCurrentTimeStamp()}");
    } else if (input.contains("START SESSION") || input.contains("STOP SESSION")) {
      _logger.logToFile(input);
    } else if (input.contains(",")) {
      handlePositionInput(input);
      lastUpdateDate.value = DateTime.now();
    } else {
      await handleHapticEffectInput(input);
    }
  }

  void sendLeftHaptic(String input) {
    if (bleService.connectedDevice.value != null) {
      bleService.write("1");
    } else {
      log("BLE Service is not connected");
    }
  }

  void sendRightHaptic(String input) {
    if (bleService.connectedDevice.value != null) {
      bleService.write("2");
    } else {
      log("BLE Service is not connected");
    }
  }

  void handlePositionInput(String input) {
    log("Got position input: $input");
    var arrays = input.split(",");
    if (arrays.length == 2) {
      var lat = double.parse(arrays[0]);
      var lng = double.parse(arrays[1]);

      if (lastKnownPosition.value != null) {
        var distanceToLastPosition = SphericalUtil.computeDistanceBetween(LatLng(lastKnownPosition.value!.latitude, lastKnownPosition.value!.longitude), LatLng(lat, lng));
        if (distanceToLastPosition < 20) {
          lastKnownPosition.value = ParticipantPosition(lat, lng);
        }
      } else {
        lastKnownPosition.value = ParticipantPosition(lat, lng);
      }
    } else {
      log("Received input is not in position format.");
    }
  }

  Future<void> handleHapticEffectInput(String input) async {
    HapticEffectType incomingEffect = HapticEffectType.values
        .firstWhere((e) => e.serialOutputValue() == int.parse(input));
    selectedHapticEffect.value = incomingEffect;

    sendHaptic();

    _logger.logToFile(
        "Commander , ${incomingEffect.toCommandDescription()} , ${lastKnownPosition.value?.latitude} , ${lastKnownPosition.value?.longitude} , ${convertCurrentTimeStamp()}");
  }

  void handleParticipantInput() {
    HapticFeedback.lightImpact();
    logParticipantInput();
  }

  Future<void> logParticipantInput() async {
    _logger.logToFile(
        "Participant , ${selectedHapticEffect.value!.toCommandDescription()} , ${lastKnownPosition.value?.latitude} , ${lastKnownPosition.value?.longitude} , ${convertCurrentTimeStamp()}");
  }

  // COMMANDER METHODS

  void handleCommanderInput() {
    commService.sendMessage(selectedHapticEffect.value!.serialOutputValue().toString());
  }

  // PISON HELPER METHODS

  Future<void> didToggleGestureRecognition() async {
    try {
      if (isGestureDetectionEnabled) {
        await platform.invokeMethod('subscribeToGestures', {});
      } else {
        await platform.invokeMethod('unsubscribeFromGestures', {});
      }
    } on PlatformException catch (e) {
      return Future.error(e);
    }
  }

  Future<void> _sendHapticToPison() async {
    if (selectedHapticEffect.value != null) {
      try {
        await platform.invokeMethod('sendHaptic', {
          "hapticEffect": selectedHapticEffect.value!
              .toDisplayString()
              .replaceAll(' ', '')
              .toLowerCase()
        });
      } on PlatformException catch (e) {
        return Future.error(e);
      }
    }
  }

  Future<void> setupVulcanConnection() async {
    try {
      await platform.invokeMethod('setupConnection', {});
    } on PlatformException catch (e) {
      isPisonWearableConnected.value = false;
      return Future.error(e);
    }
  }

  Future<void> disconnectVulcan() async {
    try {
      await platform.invokeMethod('disconnect', {});
      isPisonWearableConnected.value = false;
    } on PlatformException catch (e) {
      return Future.error(e);
    }
  }

  // Arduino Helper Methods

  void disconnectArduino() {
    if (usbService.connectedDevice.value != null) {
      usbService.disconnect();
    } else if (bleService.connectedDevice.value != null) {
      bleService.disconnect();
    } else {
      log("No device found to disconnect from.");
    }
  }

  Future<void> _sendHapticToArduino() async {
    int output = 0;
    if (selectedHapticEffect.value != null) {
      output = selectedHapticEffect.value!.serialOutputValue();
    }

    if (hapticMotorType != null) {
      switch (hapticMotorType!) {
        case HapticMotorType.lfi:
          output = output;
          break;
        case HapticMotorType.lf:
          output = output + 8;
          break;
        case HapticMotorType.mf:
          output = output + 16;
          break;
        case HapticMotorType.hf:
          output = output + 24;
      }
    }

    if (usbService.connectedDevice.value != null) {
      usbService.write(output.toString());
    } else if (bleService.connectedDevice.value != null) {
      bleService.write(output.toString());
    }
  }
}
