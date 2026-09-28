import 'dart:io';

import 'TorrServerController.dart';
import 'TorrServerControllerIos.dart';
import 'TorrServerControllerSubprocess.dart';

export 'Exceptions.dart';
export 'Models/TorrentInfo.dart';
export 'Models/TorrServerSettings.dart';
export 'PortFinder.dart';
export 'RestClient.dart';
export 'TorrServerAddon.dart';
export 'TorrServerController.dart';
export 'TorrServerControllerIos.dart';
export 'TorrServerControllerSubprocess.dart';

TorrServerController createTorrServerController() {
  return Platform.isIOS
      ? TorrServerControllerIos()
      : TorrServerControllerSubprocess();
}
