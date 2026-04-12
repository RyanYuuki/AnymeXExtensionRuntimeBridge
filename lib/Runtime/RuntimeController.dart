import 'package:get/get.dart';

import '../Logger.dart';

class RuntimeController extends GetxController {
  static RuntimeController get it => Get.put(RuntimeController());

  final status = "Idle".obs;
  final downloadProgress = 0.0.obs;
  final sizeInfo = "".obs;
  final isDownloading = false.obs;
  final isReady = false.obs;
  final error = "".obs;

  void updateStatus(String s) {
    status.value = s;
    Logger.log("[Runtime] $s");
  }

  void updateProgress(double p, String info) {
    downloadProgress.value = p;
    sizeInfo.value = info;
  }

  void setError(String e) {
    error.value = e;
    isDownloading.value = false;
    Logger.log("[Runtime Error] $e");
  }

  void setReady(bool ready) {
    isReady.value = ready;
    isDownloading.value = false;
  }
}
