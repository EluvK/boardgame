import 'package:uuid/uuid.dart';

import 'storage_box.dart';

class DeviceIdentity {
  static const String _deviceIdKey = 'device_unique_id';
  static const _uuid = Uuid();

  static Future<String> getOrCreateId() async {
    final box = StorageBox.box;
    final existing = box.read<String>(_deviceIdKey);
    if (existing != null && existing.isNotEmpty) {
      return existing;
    }

    final id = _uuid.v4();
    await box.write(_deviceIdKey, id);
    return id;
  }

  static String defaultUserName(String deviceId) {
    final short = deviceId.length >= 4 ? deviceId.substring(0, 4) : deviceId;
    return 'User-$short';
  }
}
