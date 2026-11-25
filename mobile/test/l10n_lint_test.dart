import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Plan 5.4: every string lives in both ARB files, and no screen hard-codes
/// one. Fails on a `Text('literal')` under lib/features or lib/widgets, on a
/// key missing from either file, and on a word the plain-words rule bans.
void main() {
  Map<String, dynamic> arb(String name) =>
      jsonDecode(File('lib/l10n/$name').readAsStringSync()) as Map<String, dynamic>;

  Set<String> keys(Map<String, dynamic> m) =>
      m.keys.where((k) => !k.startsWith('@')).toSet();

  final en = arb('app_en.arb');
  final bn = arb('app_bn.arb');

  test('both ARB files have the same keys', () {
    final onlyEn = keys(en).difference(keys(bn));
    final onlyBn = keys(bn).difference(keys(en));
    expect(onlyEn, isEmpty, reason: 'missing from app_bn.arb: $onlyEn');
    expect(onlyBn, isEmpty, reason: 'missing from app_en.arb: $onlyBn');
  });

  test('no Bangla string is left empty', () {
    final empty = keys(bn).where((k) => (bn[k] as String).trim().isEmpty);
    expect(empty, isEmpty);
  });

  test('no hard-coded Text literal in lib/features or lib/widgets', () {
    final literal = RegExp(r'''Text\(\s*['"]''');
    final hits = <String>[];
    for (final root in ['lib/features', 'lib/widgets']) {
      for (final f in Directory(root).listSync(recursive: true).whereType<File>()) {
        if (!f.path.endsWith('.dart')) continue;
        final lines = f.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          final l = lines[i];
          if (l.trimLeft().startsWith('//')) continue;
          if (l.contains('// l10n-lint: allow')) continue;
          if (literal.hasMatch(l)) hits.add('${f.path}:${i + 1}  ${l.trim()}');
        }
      }
    }
    expect(hits, isEmpty, reason: '\n${hits.join('\n')}');
  });

  test('English copy uses plain words', () {
    // LaMP.ai's rule: the owner never reads the system's own jargon.
    final banned = RegExp(
      r'\b(model|replay|passport|funding|capture|shortfall|ledger|LLM|AI model)\b',
      caseSensitive: false,
    );
    final hits = [
      for (final k in keys(en))
        if (banned.hasMatch(en[k] as String)) '$k: ${en[k]}',
    ];
    expect(hits, isEmpty, reason: '\n${hits.join('\n')}');
  });
}
