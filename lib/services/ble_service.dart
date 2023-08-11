import 'dart:async';
import 'dart:developer';
import 'dart:typed_data';
import 'package:flutter/cupertino.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:get_it/get_it.dart';
import 'package:hap_nav/utils/device_manager.dart';
import 'package:hap_nav/utils/enums.dart';
import 'package:permission_handler/permission_handler.dart';

class BleService {
  final String _arduinoWriteCharacteristic =
      "6e400002-b5a3-f393-e0a9-e50e24dcca9e";
  final FlutterBluePlus flutterBlue = FlutterBluePlus.instance;

  ValueNotifier<List<BluetoothDevice>> scannedDevices = ValueNotifier([]);
  ValueNotifier<BluetoothDevice?> connectedDevice = ValueNotifier(null);
  ValueNotifier<BluetoothDeviceState?> connectedDeviceState = ValueNotifier(null);

  BluetoothCharacteristic? bleWriteCharacteristic;

  void verifyPermissions() async {
    await [
      Permission.bluetooth,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.location
    ].request();
  }

  void startBleScan() {
    print("Starting scan here");
    scannedDevices.value = [];
    flutterBlue.startScan(
        scanMode: ScanMode.lowLatency);

    flutterBlue.scanResults.listen((results) {
      for (ScanResult r in results) {
        if (r.device.name.isNotEmpty) {
          final index = scannedDevices.value
              .indexWhere((element) => r.device.id.id == element.id.id);
          if (index >= 0) {
            var copyOfList = scannedDevices.value.toList();
            copyOfList[index] = r.device;
            scannedDevices.value = copyOfList;
          } else {
            scannedDevices.value = scannedDevices.value.toList()..add(r.device);
          }
        }
      }
    });
  }

  Future<void> stopBleScan() async {
    await flutterBlue.stopScan();
  }

  Future<Object?> connect(BluetoothDevice device) async {
    try {
      await flutterBlue.stopScan();
      await device.connect()
          .timeout(const Duration(seconds: 30));

      _deviceDidConnect(device);
      _startListeningToDeviceState(device);
    } on TimeoutException catch(e) {
      disconnect();
      return e;
    } catch (e) {
      disconnect();
      return e;
    }
    return null;
  }

  _startListeningToDeviceState(BluetoothDevice device) async {
    device.state.listen((event) {
      switch (event) {
        case BluetoothDeviceState.connected:
          _deviceDidConnect(device);
          break;
        case BluetoothDeviceState.disconnected:
          _deviceDidDisconnected();
          break;
        case BluetoothDeviceState.connecting:
          log("BLE Service is connecting to device.");
          break;
        case BluetoothDeviceState.disconnecting:
          log("BLE Service is disconnecting from device.");
          break;
      }
    });

    var services = await device.discoverServices();
    for (BluetoothService service in services) {
      for (BluetoothCharacteristic c in service.characteristics) {
        if (c.uuid.toString() == _arduinoWriteCharacteristic) {
          bleWriteCharacteristic = c;
        }
      }
    }
  }

  disconnect() {
    connectedDevice.value?.disconnect();
    connectedDevice.value = null;
    _deviceDidDisconnected();
  }

  Future<void> write(String input) async {
    if (bleWriteCharacteristic != null) {
      try {
        await bleWriteCharacteristic!
            .write(Uint8List.fromList("$input\r\n".codeUnits));
      } catch (e) {
        log("Error writing to characteristic. $e");
      }
    } else {
      log("No connected device");
    }
  }

  _deviceDidConnect(BluetoothDevice device) {
    connectedDevice.value = device;
    GetIt.instance<DeviceManager>().isArduinoConnected.value = true;
    GetIt.instance<DeviceManager>().hapticOutputDevice.value = HapticOutputTarget.arduino;
  }

  _deviceDidDisconnected() {
    GetIt.instance<DeviceManager>().isArduinoConnected.value = false;
    GetIt.instance<DeviceManager>().hapticOutputDevice.value = null;
  }
}
