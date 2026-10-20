import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// App languages. Each has UI strings (`app_<locale>.arb`) and content strings
/// (`content/strings/<tag>.json`). See docs/specs/i18n.md.
class AppLanguage {
  const AppLanguage(this.tag, this.locale, this.name);

  /// BCP 47 tag, also the content strings file name.
  final String tag;
  final Locale locale;

  /// Endonym: the language's name in itself, shown in the picker untranslated.
  final String name;

  static const all = [
    AppLanguage('en', Locale('en'), 'English'),
    AppLanguage('pt-BR', Locale('pt', 'BR'), 'Português (Brasil)'),
    AppLanguage('es', Locale('es'), 'Español'),
    AppLanguage('fr', Locale('fr'), 'Français'),
    AppLanguage('de', Locale('de'), 'Deutsch'),
  ];

  static AppLanguage? byTag(String? tag) {
    for (final l in all) {
      if (l.tag == tag) return l;
    }
    return null;
  }

  /// Best match for device locales: exact tag, then same language, else English.
  static AppLanguage resolve(List<Locale> device) {
    for (final d in device) {
      final exact = byTag(d.toLanguageTag());
      if (exact != null) return exact;
      for (final l in all) {
        if (l.locale.languageCode == d.languageCode) return l;
      }
    }
    return all.first;
  }
}

/// Chosen language, remembered per device. `choice == null` follows the device.
class AppLocale extends ChangeNotifier {
  AppLocale._(this._prefs, this._choice, this._device);

  static const prefKey = 'language';

  final SharedPreferences? _prefs;
  AppLanguage? _choice;
  List<Locale> _device;

  static Future<AppLocale> load(List<Locale> device) async {
    SharedPreferences? prefs;
    try {
      prefs = await SharedPreferences.getInstance();
    } catch (_) {
      // No storage (e.g. blocked): the choice lasts for this session only.
    }
    return AppLocale._(
      prefs,
      AppLanguage.byTag(prefs?.getString(prefKey)),
      device,
    );
  }

  /// In-memory instance for tests.
  @visibleForTesting
  AppLocale.memory({String? tag, List<Locale> device = const [Locale('en')]})
    : this._(null, AppLanguage.byTag(tag), device);

  /// Explicit choice, or null for "device default".
  AppLanguage? get choice => _choice;

  AppLanguage get current => _choice ?? AppLanguage.resolve(_device);

  set device(List<Locale> locales) {
    _device = locales;
    if (_choice == null) notifyListeners();
  }

  Future<void> choose(AppLanguage? language) async {
    _choice = language;
    notifyListeners();
    if (language == null) {
      await _prefs?.remove(prefKey);
    } else {
      await _prefs?.setString(prefKey, language.tag);
    }
  }
}

/// Makes the [AppLocale] reachable from the language picker.
class AppLocaleScope extends InheritedNotifier<AppLocale> {
  const AppLocaleScope({
    super.key,
    required AppLocale super.notifier,
    required super.child,
  });

  static AppLocale? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppLocaleScope>()?.notifier;
}
