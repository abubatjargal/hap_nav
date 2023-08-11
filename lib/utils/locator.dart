import 'package:get_it/get_it.dart';
import 'package:hap_nav/services/comm_service.dart';
import 'package:hap_nav/utils/log_file_output.dart';
import 'package:hap_nav/utils/device_manager.dart';

final getIt = GetIt.instance;

void setupServices() {
  getIt.registerLazySingleton<DeviceManager>(() => DeviceManager());
  getIt.registerLazySingleton<LogFileOutput>(() => LogFileOutput());
  getIt.registerLazySingleton<CommService>(() => CommService());
}