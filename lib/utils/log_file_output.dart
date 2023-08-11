import 'dart:developer';
import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/cupertino.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LogFileOutput {
  LogFileOutput();

  File? file;

  final format = DateFormat("MM-dd-yyyy hh:mm a");

  ValueNotifier<String> fileName = ValueNotifier("unknown");
  ValueNotifier<List<File>> logFiles = ValueNotifier([]);
  ValueNotifier<bool> isUploading = ValueNotifier(false);

  void logToFile(String text) {
    if (file != null) {
      file!.writeAsString("$text\n", mode: FileMode.writeOnlyAppend);
    }
  }

  Future<void> loadLogList() async {
    Directory directory = await getApplicationDocumentsDirectory();
    logFiles.value = Directory("${directory.path}/park experiment logs/")
        .listSync().map((e) {
      return File(e.path);
    }).toList();
  }

  void refreshLogFile() {
    refreshFileName().then((_) {
      getApplicationDocumentsDirectory().then((directory) {
        file = File("${directory.path}/park experiment logs/${fileName.value}");
        if (!file!.existsSync()) {
          file!.create(recursive: true);
        }
      });
    });
    loadLogList();
  }

  Future<void> refreshFileName() async {
    String deviceName = await readDeviceName();
    fileName.value = "${deviceName}_${format.format(DateTime.now())}.txt";
  }

  Future<void> uploadLogs() async {
    await loadLogList();
    isUploading.value = true;
    final storageRef = FirebaseStorage.instance.ref();

    for (final file in logFiles.value) {
      String fileName = file.path.split('/').last;

      final logFileRef = storageRef.child("park experiment logs/$fileName");

      if (logFiles.value.last == file) {
        await logFileRef.putFile(file).then((snapshot) {
          return snapshot;
        }).onError((error, stackTrace) {
          return Future.error(error!);
        });
      } else {
        await logFileRef.getDownloadURL().then((_) {
          log("File $fileName already exists");
        }).onError((error, stackTrace) async {
          log("File $fileName does not exist. So uploading");
          await logFileRef.putFile(file).then((snapshot) {
            return snapshot;
          }).onError((error, stackTrace) {
            return Future.error(error!);
          });
        });
      }
    }

    isUploading.value = false;
  }

  Future<String> readDeviceName() async {
    final prefs = await SharedPreferences.getInstance();
    const key = 'deviceName';
    final value = prefs.getString(key);
    return value ?? "unknown device";
  }
}
