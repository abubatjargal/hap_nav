import 'dart:developer';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:usb_serial/usb_serial.dart';

class UsbService {
  ValueNotifier<List<UsbDevice>?> devices = ValueNotifier([]);
  ValueNotifier<UsbDevice?> connectedDevice = ValueNotifier(null);
  UsbPort? connectedDevicePort;

  UsbService() {
    UsbSerial.usbEventStream?.listen((event) {
      if (event.event == UsbEvent.ACTION_USB_ATTACHED) {}
    });
  }

  Future<void> updateUsbDevices() async {
    devices.value = await UsbSerial.listDevices();
  }

  Future<void> connect(UsbDevice device) async {
    connectedDevicePort = await device.create();

    if (connectedDevicePort == null) {
      log("Device port is null. Connect to usb device failed");
      return;
    }

    if (await connectedDevicePort!.open()) {
      log("Port failed to open when connecting to usb device.");
    }

    connectedDevicePort!.setPortParameters(
        115200, UsbPort.DATABITS_8, UsbPort.STOPBITS_1, UsbPort.PARITY_NONE);

    connectedDevice.value = device;

    // UNCOMMENT ONLY IF NEED TO READ SERIAL INPUT FROM USB DEVICE
    // print first result and close port.
    connectedDevicePort!.inputStream!.listen((Uint8List event) {
      log(event.toString());
    });
  }

  void disconnect() {
    connectedDevicePort?.close();
    connectedDevicePort = null;
    connectedDevice.value = null;
  }

  Future<void> write(String input) async {
    if (connectedDevicePort == null) {
      log("Usb device port is null. Write to device failed.");
      return;
    }
    log("Writing to USB Device");
    await connectedDevicePort!
        .write(Uint8List.fromList("$input\r\n".codeUnits));
  }
}