import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:get_it/get_it.dart';
import 'package:hap_nav/utils/device_manager.dart';
import 'package:loader_overlay/loader_overlay.dart';
import 'package:usb_serial/usb_serial.dart';

class ArduinoSelection extends StatefulWidget {
  final bool isBluetooth;

  const ArduinoSelection({Key? key, required this.isBluetooth})
      : super(key: key);

  @override
  State<ArduinoSelection> createState() => _ArduinoSelectionState();
}

class _ArduinoSelectionState extends State<ArduinoSelection> {
  final DeviceManager _deviceManager = GetIt.instance<DeviceManager>();

  // If connected successfully, show success message and return to previous screen
  void didConnectToDevice() {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text("USB Device Connected")));
    Navigator.pop(context);
  }

  // If encountered error while connecting, show error message
  void handleError(error) {
    PlatformException err = error as PlatformException;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(err.message ?? err.toString())));
  }

  @override
  void dispose() {
    super.dispose();
    _deviceManager.bleService.stopBleScan();
  }

  @override
  Widget build(BuildContext context) {
    setState(() {
      if (widget.isBluetooth) {
        _deviceManager.bleService.startBleScan();
      } else {
        _deviceManager.usbService.updateUsbDevices();
      }
    });
    return Scaffold(
        appBar: AppBar(title: const Text("Connect Arduino")),
        body: widget.isBluetooth
            ? const BluetoothDevices()
            : UsbDevices(
          onConnect: (BuildContext _) {
            didConnectToDevice();
          },
          onError: (BuildContext _, Object obj) {
            handleError(obj);
          },
        ),
        floatingActionButton: widget.isBluetooth ? StreamBuilder<bool>(
          stream: FlutterBluePlus.instance.isScanning,
          initialData: false,
          builder: (c, snapshot) {
            if (snapshot.data!) {
              return FloatingActionButton(
                onPressed: () => FlutterBluePlus.instance.stopScan(),
                backgroundColor: Colors.red,
                child: const Icon(Icons.stop),
              );
            } else {
              return FloatingActionButton(
                  child: const Icon(Icons.search),
                  onPressed: () => FlutterBluePlus.instance
                      .startScan(timeout: const Duration(seconds: 4)));
            }
          },
        ) : FloatingActionButton(
            child: const Icon(Icons.refresh),
            onPressed: () {
              if (widget.isBluetooth) {
                _deviceManager.bleService.startBleScan();
              } else {
                _deviceManager.usbService.updateUsbDevices();
              }
            })
    );
  }
}

class UsbDevices extends StatefulWidget {
  final Function(BuildContext) onConnect;
  final Function(BuildContext, Object) onError;
  const UsbDevices({Key? key, required this.onConnect, required this.onError})
      : super(key: key);

  @override
  State<UsbDevices> createState() => _UsbDevicesState();
}

class _UsbDevicesState extends State<UsbDevices> {
  final DeviceManager _deviceManager = DeviceManager();

  late Function(BuildContext) onConnect;
  late Function(BuildContext, Object) onError;

  @override
  void setState(VoidCallback fn) {
    // TODO: implement setState
    super.setState(fn);
    onConnect = widget.onConnect;
    onError = widget.onError;
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: _deviceManager.usbService.devices,
      builder:
          (BuildContext context, List<UsbDevice>? devices, Widget? widget) {
        if (devices?.isNotEmpty ?? false) {
          return ListView.builder(
            shrinkWrap: true,
            itemCount: devices!.length,
            itemBuilder: (BuildContext context, index) {
              return ListTile(
                onTap: () {
                  _deviceManager.usbService.connect(devices[index]).then((_) {
                    onConnect(context);
                  }).onError((error, stackTrace) {
                    onError(context, error!);
                  });
                },
                title: Text(devices[index].productName ?? "Unknown"),
                subtitle: Text(devices[index].manufacturerName ?? ""),
              );
            },
          );
        } else {
          return const Center(child: Text("No devices connected"));
        }
      },
    );
  }
}

class BluetoothDevices extends StatefulWidget {
  const BluetoothDevices({Key? key}) : super(key: key);

  @override
  State<BluetoothDevices> createState() => _BluetoothDevicesState();
}

class _BluetoothDevicesState extends State<BluetoothDevices> {
  final DeviceManager _deviceManager = GetIt.instance<DeviceManager>();

  void didConnectToDevice() {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Bluetooth Device Connected")));
    Navigator.pop(context);
  }

  void handleConnectionError(String? msg) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(msg ?? "Encountered error connecting to device.")));
  }

  void _connectDevice(BluetoothDevice device) {
    _deviceManager.bleService.connect(device)
        .then((error) => {
      if (error == null) {
        didConnectToDevice(),
        context.loaderOverlay.hide()
      } else {
        handleConnectionError(error.toString()),
        context.loaderOverlay.hide()
      }
    });
    context.loaderOverlay.show();
  }

  @override
  Widget build(BuildContext context) {
    return LoaderOverlay(
      child: ValueListenableBuilder(
        valueListenable: _deviceManager.bleService.scannedDevices,
        builder: (BuildContext context, List<BluetoothDevice> devices,
            Widget? widget) {
          return ListView.builder(
            shrinkWrap: true,
            itemCount: devices.length,
            itemBuilder: (BuildContext context, index) {
              return ListTile(
                onTap: () {
                  _connectDevice(devices[index]);
                },
                title: Text(devices[index].name),
                subtitle: Text(devices[index].id.id),
              );
            },
          );
        },
      ),
    );
  }
}
