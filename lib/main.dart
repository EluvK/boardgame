import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:get_storage/get_storage.dart';

import 'src/i18n/app_i18n.dart';
import 'src/home/home_page.dart';
import 'src/utils/storage_box.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await GetStorage.init(StorageBox.boxName);
  await AppLocaleController.instance.init();
  runApp(const LobbyApp());
}

class LobbyApp extends StatelessWidget {
  const LobbyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Locale>(
      valueListenable: AppLocaleController.instance.localeNotifier,
      builder: (context, locale, _) {
        final t = AppI18n.fromLocale(locale);
        return MaterialApp(
          title: t.common.text(zh: '桌游大厅', en: 'Boardgame Lobby'),
          debugShowCheckedModeBanner: false,
          locale: locale,
          supportedLocales: const <Locale>[Locale('en'), Locale('zh')],
          localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0A7E8C)),
          ),
          home: kIsWeb
              ? const HomePage()
              : const Scaffold(
                  body: Center(
                    child: Text('This app is currently web-only / 当前仅支持 Web 端。'),
                  ),
              ),
        );
      },
    );
  }
}
