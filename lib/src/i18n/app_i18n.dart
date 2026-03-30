import 'package:flutter/widgets.dart';

import '../utils/storage_box.dart';

class AppLocaleController {
  AppLocaleController._();

  static const String _storageKey = 'app_locale_code';
  static final AppLocaleController instance = AppLocaleController._();

  final ValueNotifier<Locale> localeNotifier = ValueNotifier<Locale>(const Locale('en'));

  Locale get currentLocale => localeNotifier.value;

  bool get isZh => currentLocale.languageCode.toLowerCase().startsWith('zh');

  Future<void> init() async {
    final saved = StorageBox.box.read<String>(_storageKey)?.trim().toLowerCase() ?? '';
    if (saved == 'zh' || saved == 'en') {
      localeNotifier.value = Locale(saved);
      return;
    }

    final platform = WidgetsBinding.instance.platformDispatcher.locale;
    localeNotifier.value = platform.languageCode.toLowerCase().startsWith('zh')
        ? const Locale('zh')
        : const Locale('en');
  }

  Future<void> toggle() async {
    await setLocale(isZh ? const Locale('en') : const Locale('zh'));
  }

  Future<void> setLocale(Locale next) async {
    final code = next.languageCode.toLowerCase().startsWith('zh') ? 'zh' : 'en';
    localeNotifier.value = Locale(code);
    await StorageBox.box.write(_storageKey, code);
  }
}

class AppI18n {
  AppI18n._({required this.isZh});

  final bool isZh;

  factory AppI18n.of(BuildContext context) {
    final locale = Localizations.maybeLocaleOf(context);
    return AppI18n.fromLocale(locale);
  }

  factory AppI18n.fromLocale(Locale? locale) {
    final languageCode = locale?.languageCode.toLowerCase() ?? 'en';
    return AppI18n._(isZh: languageCode.startsWith('zh'));
  }

  ScopedI18n get common => ScopedI18n(isZh: isZh);

  ScopedI18n get lobby => ScopedI18n(isZh: isZh);

  ScopedI18n get room => ScopedI18n(isZh: isZh);

  ScopedI18n get acquire => ScopedI18n(isZh: isZh);
}

class ScopedI18n {
  const ScopedI18n({required this.isZh});

  final bool isZh;

  String text({required String zh, required String en}) {
    return isZh ? zh : en;
  }
}
