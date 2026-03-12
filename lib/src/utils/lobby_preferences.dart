import 'device_identity.dart';
import 'storage_box.dart';

class LobbyProfile {
  LobbyProfile({
    required this.deviceId,
    required this.userName,
    required this.serverUrl,
  });

  final String deviceId;
  final String userName;
  final String serverUrl;
}

class LobbyPreferences {
  static const String _userNameKey = 'lobby_user_name';
  static const String _serverUrlKey = 'lobby_server_url';
  static const String _defaultServerUrl = 'http://127.0.0.1:17980';

  static Future<LobbyProfile> loadProfile() async {
    final box = StorageBox.box;
    final deviceId = await DeviceIdentity.getOrCreateId();

    var userName = box.read<String>(_userNameKey);
    if (userName == null || userName.trim().isEmpty) {
      userName = DeviceIdentity.defaultUserName(deviceId);
      await box.write(_userNameKey, userName);
    }

    var serverUrl = box.read<String>(_serverUrlKey);
    if (serverUrl == null || serverUrl.trim().isEmpty) {
      serverUrl = _defaultServerUrl;
      await box.write(_serverUrlKey, serverUrl);
    }

    return LobbyProfile(
      deviceId: deviceId,
      userName: userName,
      serverUrl: serverUrl,
    );
  }

  static Future<void> saveUserName(String value) async {
    await StorageBox.box.write(_userNameKey, value);
  }

  static Future<void> saveServerUrl(String value) async {
    await StorageBox.box.write(_serverUrlKey, value);
  }
}
