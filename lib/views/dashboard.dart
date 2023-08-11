import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:get_it/get_it.dart';
import 'package:hap_nav/views/app_settings_view.dart';
import 'package:hap_nav/views/arduino_selection.dart';
import 'package:hap_nav/utils/device_manager.dart';
import 'package:hap_nav/utils/enums.dart';
import 'package:hap_nav/main.dart';
import 'package:hap_nav/views/lock_screen.dart';
import 'package:usb_serial/usb_serial.dart';

import '../utils/helper.dart';
import 'navigation.dart';

class Dashboard extends StatefulWidget {
  const Dashboard({Key? key}) : super(key: key);

  @override
  State<Dashboard> createState() => _DashboardState();
}

class _DashboardState extends State<Dashboard> {
  List<UsbDevice>? devices;

  final DeviceManager _deviceManager = GetIt.instance<DeviceManager>();

  @override
  void initState() {
    super.initState();
  }

  void handleError(error) {
    PlatformException err = error as PlatformException;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(err.message ?? err.toString())));
  }

  Future<void> openNavigation() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();

    if (!serviceEnabled) {
      log("Location services not enabled");
      if (context.mounted) showScaffoldMessage(context, "Location service is not enabled!");
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever ||
        permission == LocationPermission.unableToDetermine) {
      log("Location permission not granted");
      if (context.mounted) showScaffoldMessage(context, "Location permission is not granted! $permission");
      return;
    }

    openNavigationView();
  }

  void openNavigationView() {
    Navigator.push(
      context,
      MaterialPageRoute(
          builder: (context) =>
          const Navigation()),
    );
  }

  void showAndroidConnectionModal() {
    showModalBottomSheet(
        context: context,
        builder: (context) {
          return Wrap(
            children: [
              ListTile(
                leading: const Icon(Icons.usb),
                title: const Text('USB'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (context) =>
                        const ArduinoSelection(isBluetooth: false)),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.bluetooth),
                title: const Text('Bluetooth'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (context) =>
                        const ArduinoSelection(isBluetooth: true)),
                  );
                },
              ),
            ],
          );
        });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: ThemeColor.buildMaterialColor(Colors.blue.shade500),
        actions: [_navigationButton(), _lockButton()],
        title: ValueListenableBuilder(
          valueListenable: _deviceManager.isCommander,
          builder: (BuildContext context, bool value, Widget? child) {
            if (value) {
              return const Text("Commander Mode");
            } else {
              return ValueListenableBuilder(
                  valueListenable: _deviceManager.isParticipant,
                  builder: (context, value, widget) {
                    if (value) {
                      return const Text("Participant Mode");
                    } else {
                      return const SizedBox();
                    }
                  });
            }
          },
        ),
      ),
      body: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [_deviceStatusCard(), const AppSettingsView()],
      ),
    );
  }

  Widget _navigationButton() {
    return ValueListenableBuilder(
      valueListenable: _deviceManager.isCommander,
      builder: (BuildContext context,
          bool isCommander, Widget? child) {
        if (isCommander) {
          return IconButton(
            onPressed: () async {
              await openNavigation();
            },
            icon: const Icon(Icons.navigation),
          );
        }
        return const SizedBox();
      },
    );
  }

  Widget _lockButton() {
    return ValueListenableBuilder(
      valueListenable: _deviceManager.isParticipant,
      builder: (BuildContext context, bool isParticipant, Widget? widget) {
        if (isParticipant) {
          return IconButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (context) =>
                      const LockScreen()),
                );
              },
              icon: const Icon(Icons.lock, color: Colors.white));
        }
        return const SizedBox();
      },
    );
  }

  Widget _deviceStatusCard() {
    return Padding(
        padding: const EdgeInsets.all(8),
        child: Card(
            child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Device Status",
                        style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w500,
                            color: Colors.blueGrey),
                      ),
                      ValueListenableBuilder(
                        valueListenable: _deviceManager.hapticOutputDevice,
                        builder: (BuildContext context,
                            HapticOutputTarget? target, Widget? child) {
                          if (target == HapticOutputTarget.arduino) {
                            return const Text("Output Device: Arduino");
                          } else if (target == HapticOutputTarget.vulcan) {
                            return const Text("Output Device: Pison");
                          }
                          return const Text("Output Device: none");
                        },
                      )
                    ]))));
  }

  Widget _hapticEffectPanel() {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Card(
        child: ExpansionTile(
          title: const Text("Haptic Effect"),
          children: [
            Column(
              children: [
                Row(
                  children: const [
                    HapticEffectButton(
                        effect: HapticEffectType.subtle1, flex: 5),
                  ],
                ),
                Row(
                  children: const [
                    HapticEffectButton(
                        effect: HapticEffectType.medium1, flex: 5),
                  ],
                ),
                Row(
                  children: const [
                    HapticEffectButton(
                        effect: HapticEffectType.strong2, flex: 5),
                  ],
                ),
                Row(
                  children: const [
                    HapticEffectButton(
                        effect: HapticEffectType.subtle2, flex: 10)
                  ],
                ),
                Row(
                  children: const [
                    HapticEffectButton(
                        effect: HapticEffectType.strong3, flex: 10)
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class HapticEffectButton extends StatefulWidget {
  const HapticEffectButton({Key? key, required this.effect, required this.flex})
      : super(key: key);

  final HapticEffectType effect;
  final int flex;

  @override
  State<HapticEffectButton> createState() => _HapticEffectButtonState();
}

class _HapticEffectButtonState extends State<HapticEffectButton> {
  final DeviceManager _deviceManager = GetIt.instance<DeviceManager>();

  void handleUserInput() {
    if (_deviceManager.isCommander.value) {
      _deviceManager.handleCommanderInput();
    } else if (_deviceManager.isParticipant.value) {
      _deviceManager.handleParticipantInput();
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text("Input Received!"),
        backgroundColor: Colors.green,
      ));
    } else {
      _deviceManager.sendHaptic();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Expanded(
        flex: widget.flex,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: OutlinedButton(
              onPressed: () {
                _deviceManager.selectedHapticEffect.value = widget.effect;
                handleUserInput();
              },
              style: ButtonStyle(
                  backgroundColor: MaterialStateProperty.all(
                      widget.effect.buttonColor().withOpacity(0.8))),
              child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text(widget.effect.toCommandDescription(),
                      style: const TextStyle(color: Colors.white, fontSize: 20))
              )),
        ));
  }
}
