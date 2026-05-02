import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

class ArbFile {
  ArbFile._(this.file, this.values);

  final File file;
  final Map<String, Object?> values;

  static ArbFile read(File file) {
    if (!file.existsSync()) {
      file.parent.createSync(recursive: true);
      return ArbFile._(file, <String, Object?>{'@@locale': 'en'});
    }

    final decoded = jsonDecode(file.readAsStringSync());
    if (decoded is! Map<String, Object?>) {
      throw FormatException(
          'ARB file must contain a JSON object: ${file.path}');
    }
    return ArbFile._(file, Map<String, Object?>.from(decoded));
  }

  String? findKeyForValue(String text) {
    for (final entry in values.entries) {
      if (entry.key.startsWith('@')) continue;
      if (entry.value == text) return entry.key;
    }
    return null;
  }

  bool setMetadata(String key, List<String> placeholders) {
    if (placeholders.isEmpty) return false;
    final next = {
      'placeholders': {
        for (final placeholder in placeholders)
          placeholder: <String, Object?>{
            'type': 'Object',
          },
      },
    };
    final metadataKey = '@$key';
    if (_deepEquals(values[metadataKey], next)) return false;
    values[metadataKey] = next;
    return true;
  }

  bool _deepEquals(Object? left, Object? right) {
    return jsonEncode(left) == jsonEncode(right);
  }

  void write() {
    final ordered = <String, Object?>{};
    if (values.containsKey('@@locale')) {
      ordered['@@locale'] = values['@@locale'];
    }

    final keys = values.keys.where((key) => key != '@@locale').toList()
      ..sort((a, b) {
        if (a.startsWith('@') && !b.startsWith('@')) return 1;
        if (!a.startsWith('@') && b.startsWith('@')) return -1;
        return a.compareTo(b);
      });

    for (final key in keys) {
      ordered[key] = values[key];
    }

    file.parent.createSync(recursive: true);
    const encoder = JsonEncoder.withIndent('  ');
    file.writeAsStringSync('${encoder.convert(ordered)}\n');
  }

  String get displayPath => p.normalize(file.path);
}

class LocalizationKeyPlanner {
  LocalizationKeyPlanner({required Set<String> existingKeys})
      : _used = Set<String>.from(existingKeys);

  final Set<String> _used;
  final Map<String, String> _byText = {};

  String keyFor(String text) {
    final cached = _byText[text];
    if (cached != null) return cached;

    final base = _toCamelCase(text);
    var candidate = base.isEmpty ? 'localizedText' : base;
    if (RegExp(r'^\d').hasMatch(candidate)) {
      candidate = 'text$candidate';
    }

    final original = candidate;
    var suffix = 2;
    while (_used.contains(candidate)) {
      candidate = '$original$suffix';
      suffix++;
    }
    _used.add(candidate);
    _byText[text] = candidate;
    return candidate;
  }

  String _toCamelCase(String text) {
    final allWords = text
        .replaceAll(RegExp(r"['’]"), '')
        .split(RegExp(r'[^A-Za-z0-9]+'))
        .where((part) => part.isNotEmpty)
        .toList();
    if (allWords.isEmpty) return '';

    const maxWordsForKey = 7;
    const maxKeyLength = 48;
    final isLongText = text.length > 80 || allWords.length > maxWordsForKey;
    final words = allWords.take(maxWordsForKey).toList();

    final buffer = StringBuffer(words.first.toLowerCase());
    for (final word in words.skip(1)) {
      final lower = word.toLowerCase();
      buffer.write(lower[0].toUpperCase());
      if (lower.length > 1) buffer.write(lower.substring(1));
    }

    var result = buffer.toString();
    if (result.length > maxKeyLength) {
      result = result.substring(0, maxKeyLength);
    }
    if (isLongText) {
      result = '$result${_shortHash(text)}';
    }

    const reserved = {
      'abstract',
      'as',
      'assert',
      'async',
      'await',
      'break',
      'case',
      'catch',
      'class',
      'const',
      'continue',
      'default',
      'deferred',
      'do',
      'dynamic',
      'else',
      'enum',
      'export',
      'extends',
      'extension',
      'external',
      'factory',
      'false',
      'final',
      'finally',
      'for',
      'function',
      'get',
      'hide',
      'if',
      'implements',
      'import',
      'in',
      'interface',
      'is',
      'late',
      'library',
      'mixin',
      'new',
      'null',
      'on',
      'operator',
      'part',
      'required',
      'rethrow',
      'return',
      'set',
      'show',
      'static',
      'super',
      'switch',
      'sync',
      'this',
      'throw',
      'true',
      'try',
      'typedef',
      'var',
      'void',
      'while',
      'with',
      'yield',
    };

    return reserved.contains(result) ? '${result}Text' : result;
  }

  String _shortHash(String text) {
    var hash = 0x811c9dc5;
    for (final codeUnit in text.codeUnits) {
      hash ^= codeUnit;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash.toRadixString(16).padLeft(8, '0').substring(0, 6);
  }
}
