import 'package:get_storage/get_storage.dart';

class StorageBox {
  static const String boxName = 'BoardgameStorage';

  static GetStorage get box => GetStorage(boxName);
}
