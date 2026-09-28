import 'package:get/get.dart';

import 'Engines/TorrentEngine/TorrServerAddon.dart';
import 'Extensions/Addon.dart';
import 'Logger.dart';

class AddonManager extends GetxService {
  final List<Addon> addons = [TorrServerAddon()];

  @override
  void onInit() {
    super.onInit();

    for (final addon in addons) {
      addon
          .isInstalled()
          .then((value) {
            addon.installed.value = value;
          })
          .catchError((Object e) {
            Logger.log('Failed to check if addon ${addon.id} is installed: $e');
          });
    }
  }

  T get<T extends Addon>() {
    return addons.firstWhere(
          (addon) => addon is T,
          orElse: () => throw StateError("Addon $T not registered."),
        )
        as T;
  }

  Addon? byId(String id) {
    for (final addon in addons) {
      if (addon.id == id) return addon;
    }
    return null;
  }

  Future<void> checkForUpdates() async {
    await Future.wait(
      addons.map((addon) async {
        try {
          await addon.checkForUpdate();
        } catch (e) {
          Logger.log('Update check failed for addon ${addon.id}: $e');
        }
      }),
    );
  }

  Future<void> autoUpdate() async {
    await Future.wait(
      addons.map((addon) async {
        try {
          if (await addon.checkForUpdate()) {
            await addon.update();
          }
        } catch (e) {
          Logger.log('Auto-update failed for addon ${addon.id}: $e');
        }
      }),
    );
  }
}
