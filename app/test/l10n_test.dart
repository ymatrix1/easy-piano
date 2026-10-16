import 'dart:convert';
import 'dart:io';

import 'package:easy_piano/content/content_repo.dart';
import 'package:easy_piano/l10n/app_locale.dart';
import 'package:easy_piano/l10n/app_localizations.dart';
import 'package:easy_piano/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _arb(String name) =>
    jsonDecode(File('lib/l10n/$name').readAsStringSync())
        as Map<String, dynamic>;

Set<String> _keys(Map<String, dynamic> arb) =>
    arb.keys.where((k) => !k.startsWith('@')).toSet();

ContentRepo _repo() {
  final root = Directory('../content').absolute;
  final files = {
    for (final f in root.listSync(recursive: true).whereType<File>())
      if (f.path.endsWith('.json') && !f.path.contains('schema'))
        f.uri.pathSegments.skip(root.uri.pathSegments.length - 1).join('/'): f
            .readAsStringSync(),
  };
  return ContentRepo.fromFiles(files);
}

void main() {
  test('every UI locale has every key of the English template', () {
    final en = _keys(_arb('app_en.arb'));
    // pt_BR inherits everything from pt (gen-l10n needs the base language).
    for (final name in [
      'app_pt.arb',
      'app_es.arb',
      'app_fr.arb',
      'app_de.arb',
    ]) {
      final keys = _keys(_arb(name));
      expect(en.difference(keys), isEmpty, reason: '$name is missing keys');
      expect(keys.difference(en), isEmpty, reason: '$name has stale keys');
    }
  });

  test('each app language has UI and content strings', () {
    final repo = _repo();
    final supported = AppLocalizations.supportedLocales;
    for (final lang in AppLanguage.all) {
      expect(supported, contains(lang.locale), reason: lang.tag);
      expect(repo.locales, contains(lang.tag), reason: lang.tag);
    }
  });

  test('device locale resolves to the closest app language', () {
    String pick(List<Locale> l) => AppLanguage.resolve(l).tag;
    expect(pick(const [Locale('pt', 'PT')]), 'pt-BR');
    expect(pick(const [Locale('es', 'MX')]), 'es');
    expect(pick(const [Locale('ja'), Locale('fr', 'CA')]), 'fr');
    expect(pick(const [Locale('ja')]), 'en');
  });

  test('content falls back to base language, then English', () {
    final repo = _repo()..locale = 'es';
    expect(repo.t('str:node.ode'), 'Oda a la alegría');
    repo.locale = 'de-AT'; // no file: base language `de`
    expect(repo.t('str:node.ode'), 'Ode an die Freude');
    repo.locale = 'xx';
    expect(repo.t('str:node.ode'), 'Ode to Joy');
  });

  testWidgets('picking a language switches UI and content live', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final appLocale = AppLocale.memory();
    await tester.pumpWidget(EasyPianoApp(repo: _repo(), appLocale: appLocale));
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('PIANO BASICS'), findsOneWidget);

    await tester.tap(find.text('PROFILE'));
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('Português (Brasil)'));
    await tester.pump(const Duration(seconds: 1));
    expect(appLocale.current.tag, 'pt-BR');
    expect(find.text('CONFIGURAÇÕES'), findsOneWidget); // still on Profile

    await tester.tap(find.text('APRENDER'));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('PIANO BÁSICO'), findsOneWidget);

    await tester.tap(find.text('PERFIL').last);
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('Deutsch'));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('EINSTELLUNGEN'), findsOneWidget);
  });
}
