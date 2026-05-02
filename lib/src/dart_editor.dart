import 'dart:io';

import 'package:path/path.dart' as p;

import 'models.dart';

class DartEditor {
  DartEditor({required this.projectRoot});

  final String projectRoot;

  int applyReplacements(Map<String, List<Replacement>> replacementsByFile) {
    var updated = 0;

    for (final entry in replacementsByFile.entries) {
      final file = File(entry.key);
      if (!file.existsSync()) continue;

      final original = file.readAsStringSync();
      final replacements = List<Replacement>.from(entry.value)
        ..sort((a, b) => b.start.compareTo(a.start));

      var content = original;
      for (final replacement in replacements) {
        content = content.replaceRange(
          replacement.start,
          replacement.end,
          replacement.replacement,
        );
      }

      content = _removeConstAroundLocalizations(content);
      content = _ensureLocalizationImport(content);

      if (content != original) {
        file.writeAsStringSync(content);
        updated++;
      }
    }

    return updated;
  }

  String _ensureLocalizationImport(String content) {
    const importLine =
        "import 'package:flutter_gen/gen_l10n/app_localizations.dart';";
    if (content.contains(importLine)) return content;

    final importMatches = RegExp(r"""^import\s+['"].+?['"];""", multiLine: true)
        .allMatches(content)
        .toList();
    if (importMatches.isEmpty) {
      return '$importLine\n\n$content';
    }

    final last = importMatches.last;
    return content.replaceRange(last.end, last.end, '\n$importLine\n');
  }

  String _removeConstAroundLocalizations(String content) {
    const marker = 'AppLocalizations.of(context)!';
    var result = content;
    var searchFrom = 0;

    while (true) {
      final markerIndex = result.indexOf(marker, searchFrom);
      if (markerIndex == -1) break;

      final windowStart = _statementWindowStart(result, markerIndex);
      final beforeMarker = result.substring(windowStart, markerIndex);
      final constMatches =
          RegExp(r'\bconst\s+').allMatches(beforeMarker).toList();

      if (constMatches.isNotEmpty) {
        final match = constMatches.last;
        final removeStart = windowStart + match.start;
        final removeEnd = windowStart + match.end;
        result = result.replaceRange(removeStart, removeEnd, '');
        searchFrom = markerIndex - (removeEnd - removeStart) + marker.length;
      } else {
        searchFrom = markerIndex + marker.length;
      }
    }

    return result;
  }

  int _statementWindowStart(String content, int offset) {
    for (var i = offset - 1; i >= 0; i--) {
      final char = content[i];
      if (char == ';' || char == '{') return i + 1;
    }
    return 0;
  }

  String relativePath(String filePath) =>
      p.relative(filePath, from: projectRoot);
}
