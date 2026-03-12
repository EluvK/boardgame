import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get_storage/get_storage.dart';

import 'src/home/home_page.dart';
import 'src/utils/storage_box.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await GetStorage.init(StorageBox.boxName);
  runApp(const LobbyApp());
}

class LobbyApp extends StatelessWidget {
  const LobbyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Boardgame Lobby',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0A7E8C)),
      ),
      home: kIsWeb
          ? const HomePage()
          : const Scaffold(
              body: Center(
                child: Text('This app is currently web-only.'),
              ),
            ),
    );
  }
}
