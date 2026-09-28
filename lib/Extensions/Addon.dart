import 'package:flutter/material.dart';
import 'package:get/get_rx/src/rx_types/rx_types.dart';

abstract class Addon {
  String get id;
  String get name;
  IconData get icon;
  final installed = false.obs;
  final downloading = false.obs;
  final progress = 0.0.obs;
  final hasUpdate = false.obs;
  Future<void> install();
  Future<void> uninstall();
  Future<void> update();
  Future<bool> checkForUpdate();
  Future<bool> isInstalled();
}
