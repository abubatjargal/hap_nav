import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';
import 'package:hap_nav/services/comm_service.dart';
import 'package:hap_nav/utils/log_file_output.dart';
import 'package:hap_nav/views/arduino_selection.dart';
import 'package:hap_nav/utils/device_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../main.dart';
import '../utils/helper.dart';

class AppSettingsView extends StatefulWidget {
  const AppSettingsView({Key? key}) : super(key: key);

  @override
  State<AppSettingsView> createState() => _AppSettingsViewState();
}

class _AppSettingsViewState extends State<AppSettingsView> {
  final DeviceManager _deviceManager = GetIt.instance<DeviceManager>();
  final CommService _commService = GetIt.instance<CommService>();
  final LogFileOutput _logFileOutput = GetIt.instance<LogFileOutput>();

  final TextEditingController _deviceNameController = TextEditingController();

  late final LogFileOutput _logger = GetIt.instance<LogFileOutput>();

  String deviceNameDisplayString = "test";

  void showScaffoldMessage(String msg) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void handleError(error) {
    PlatformException err = error as PlatformException;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(err.message ?? err.toString())));
  }

  Future<String> readDeviceName() async {
    final prefs = await SharedPreferences.getInstance();
    const key = 'deviceName';
    final value = prefs.getString(key);
    return value ?? "";
  }

  Future<void> setDeviceName(String name) async {
    final deviceName = name.isEmpty ? "unknown_device" : name;
    final prefs = await SharedPreferences.getInstance();
    const key = 'deviceName';
    prefs.setString(key, deviceName);
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
  void initState() {
    super.initState();

    readDeviceName().then((value) {
      setState(() {
        _deviceNameController.text = value;
      });
    });

    _deviceManager.errorMessage.addListener(() {
      log(_deviceManager.errorMessage.value!);
      if (_deviceManager.errorMessage.value != null) {
        showAlertDialog(context, () => null, "Error", _deviceManager.errorMessage.value ?? "unknown error");
        HapticFeedback.lightImpact();
      }
    });
  }

  Widget participantSettings() {
    return Column(
      children: [
        const Divider(),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: Row(
            children: [
              const Text("Commander Device"),
              const Spacer(),
              ValueListenableBuilder(
                valueListenable: _commService.connected,
                builder: (BuildContext context, bool? isConnected,
                    Widget? child) {
                  if (isConnected == null) {
                    return const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(),
                    );
                  } else if (isConnected) {
                    return OutlinedButton(
                        onPressed: () {
                          _commService.disconnect();
                        },
                        child: const Text("Disconnect"));
                  } else {
                    return OutlinedButton(
                        onPressed: () {
                          _commService.discoverWifiDevices();
                        },
                        child: const Text("Connect"));
                  }
                },
              )
            ],
          ),
        ),
        const Divider(),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: Row(
            children: [
              const Text("Pison Vulcan"),
              const Spacer(),
              ValueListenableBuilder(
                  valueListenable:
                  _deviceManager.isPisonWearableConnected,
                  builder: (BuildContext context, bool isConnected,
                      Widget? child) {
                    if (isConnected) {
                      return OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.red,
                          ),
                          onPressed: () {
                            setState(() {
                              _deviceManager.disconnectVulcan();
                              showScaffoldMessage(
                                  "Vulcan Disconnected");
                            });
                          },
                          child: const Text("Disconnect"));
                    } else {
                      return OutlinedButton(
                          onPressed: () {
                            _deviceManager
                                .setupVulcanConnection()
                                .then((_) => {
                              showScaffoldMessage(
                                  "Vulcan Connected")
                            })
                                .onError((error, stackTrace) =>
                            {handleError(error)});
                          },
                          child: const Text("Connect"));
                    }
                  })
            ],
          ),
        ),
        const Divider(),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: Row(
            children: [
              const Text("Arduino"),
              const Spacer(),
              ValueListenableBuilder(
                  valueListenable: _deviceManager.isArduinoConnected,
                  builder: (BuildContext context, bool isConnected,
                      Widget? child) {
                    if (!isConnected) {
                      return OutlinedButton(
                          onPressed: () {
                            showAndroidConnectionModal();
                          },
                          child: const Text("Connect"));
                    } else {
                      return OutlinedButton(
                          style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.red),
                          onPressed: () {
                            setState(() {
                              _deviceManager.disconnectArduino();
                              showScaffoldMessage(
                                  "Arduino Disconnected");
                            });
                          },
                          child: const Text("Disconnect"));
                    }
                  })
            ],
          ),
        ),
        const Divider(),
        SizedBox(
            width: double.infinity,
            height: 50,
            child: Row(
              children: [
                const Text("Record Location to Logs"),
                const Spacer(),
                Switch(
                    value: _deviceManager.isRecordingParticipantLocation.value,
                    onChanged: (val) {
                      if (_logger.file == null) {
                        showAlertDialog(context, () => null, "No Log File", "Please refresh logs before enabling recording.");
                      } else {
                        setState(() {
                          _deviceManager.isRecordingParticipantLocation.value = val;
                        });
                      }
                    })
              ],
            )
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
                child: TextField(
                  scrollPadding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
                  controller: _deviceNameController,
                  decoration: const InputDecoration(
                      focusedBorder: OutlineInputBorder(
                          borderSide: BorderSide(
                              color: Colors.blueAccent, width: 1)),
                      enabledBorder: OutlineInputBorder(
                          borderSide:
                          BorderSide(color: Colors.grey, width: 1)),
                      hintText: "Device Name"),
                  onChanged: (value) {
                    setDeviceName(value);
                  },
                ))
          ],
        ),
        const SizedBox(height: 8),
        ValueListenableBuilder(
            valueListenable: _logger.isUploading,
            builder: (context, isUploading, widget) {
              if (isUploading == true) {
                return Row(
                  children: const [
                    Spacer(),
                    CircularProgressIndicator(),
                    SizedBox(width: 8),
                    Text("Uploading"),
                    Spacer()
                  ],
                );
              } else {
                return ValueListenableBuilder(
                    valueListenable: _deviceManager.isRecordingParticipantLocation,
                    builder: (BuildContext context, bool isRecording, Widget? widget) {
                      return Row(
                        children: [
                          Expanded(
                            child: SizedBox(
                                width: double.infinity,
                                child: OutlinedButton(
                                  style: OutlinedButton.styleFrom(
                                    minimumSize: const Size.fromHeight(50),
                                  ),
                                  onPressed: isRecording ? null : () {
                                    setState(() {
                                      _logFileOutput.refreshLogFile();
                                    });
                                  },
                                  child: Row(
                                    children: const [
                                      Icon(Icons.refresh),
                                      Text("Refresh Logs")
                                    ],
                                  ),
                                )),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: SizedBox(
                                width: double.infinity,
                                child: OutlinedButton(
                                  style: OutlinedButton.styleFrom(
                                    minimumSize: const Size.fromHeight(50),
                                  ),
                                  onPressed: isRecording ? null : () {
                                    setState(() {
                                      _logFileOutput.uploadLogs();
                                    });
                                  },
                                  child: Row(
                                    children: const [
                                      Icon(Icons.upload),
                                      Text("Upload Logs")
                                    ],
                                  ),
                                )),
                          )
                        ],
                      );
                    }
                );
              }
            }),
        Row(
          children: [
            Expanded(
                child: Padding(
                    padding: const EdgeInsets.fromLTRB(0, 16, 0, 16),
                    child: Text("Log Filename: ${_logger.fileName.value}")))
          ],
        ),
        const Divider(),
      ],
    );
  }

  Widget commanderSettings() {
    return Column(
      children: [
        ValueListenableBuilder(
            valueListenable: _commService.connected,
            builder: (context, isConnected, widget) {
              if (isConnected != null) {
                if (isConnected) {
                  return const Text("Participant connected", style: TextStyle(fontSize: 18, color: Colors.green));
                } else {
                  return const Text("No participants connected", style: TextStyle(fontSize: 18, color: Colors.grey));
                }
              }
              return const SizedBox();
            }),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            ValueListenableBuilder(
                valueListenable: _deviceManager.isCommander,
                builder: (context, value, child) {
                  if (!value) {
                    return Row(
                      children: [
                        const Text("Is Participant"),
                        const Spacer(),
                        Switch(
                            value: _deviceManager.isParticipant.value,
                            onChanged: (val) {
                              setState(() {
                                _deviceManager.isParticipant.value = val;
                              });
                            })
                      ],
                    );
                  } else {
                    return commanderSettings();
                  }
                }),
            ValueListenableBuilder(
                valueListenable: _deviceManager.isParticipant,
                builder: (context, value, child) {
                  if (!value) {
                    return Row(
                      children: [
                        const Text("Is Commander"),
                        const Spacer(),
                        Switch(
                            value: _deviceManager.isCommander.value,
                            onChanged: (val) {
                              setState(() {
                                _deviceManager.isCommander.value = val;
                              });
                            })
                      ],
                    );
                  } else {
                    return participantSettings();
                  }
                }),
          ],
        ),
      ),
    );
  }
}
