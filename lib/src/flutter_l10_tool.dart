import 'dart:io';

import 'package:path/path.dart' as p;

import 'arb_file.dart';
import 'dart_editor.dart';
import 'models.dart';
import 'scanner.dart';

class FlutterL10Tool {
  FlutterL10Tool({
    String? projectRoot,
    this.libDirectory = 'lib',
    this.arbDirectory,
    this.arbFileName = 'app_en.arb',
  }) : projectRoot = p.normalize(projectRoot ?? Directory.current.path);

  final String projectRoot;
  final String libDirectory;
  final String? arbDirectory;
  final String arbFileName;

  Directory get libDir => Directory(p.join(projectRoot, libDirectory));

  File get arbFile {
    final configured = arbDirectory;
    if (configured != null) {
      return File(p.join(projectRoot, configured, arbFileName));
    }

    final configuredFromYaml = _arbDirFromL10nYaml();
    if (configuredFromYaml != null) {
      return File(p.join(projectRoot, configuredFromYaml, arbFileName));
    }

    final generatedDefault =
        File(p.join(projectRoot, 'lib', 'l10n', arbFileName));
    if (generatedDefault.existsSync()) return generatedDefault;

    final appRootDefault = File(p.join(projectRoot, 'l10n', arbFileName));
    if (appRootDefault.existsSync()) return appRootDefault;

    return generatedDefault;
  }

  ScanReport scan() {
    final scanner = StaticTextScanner(projectRoot: projectRoot, libDir: libDir);
    return scanner.scan();
  }

  ApplyReport apply() {
    final report = scan();
    final arb = ArbFile.read(arbFile);
    final keyPlanner =
        LocalizationKeyPlanner(existingKeys: arb.values.keys.toSet());
    final additions = <String, String>{};
    final replacements = <String, List<Replacement>>{};
    var arbChanged = false;

    for (final hit in report.hits) {
      if (!hit.canReplace) continue;
      final existingKey = arb.findKeyForValue(hit.text) ??
          additions.entries
              .where((entry) => entry.value == hit.text)
              .map((entry) => entry.key)
              .firstOrNull;
      final key = existingKey ?? keyPlanner.keyFor(hit.text);
      additions.putIfAbsent(key, () => hit.text);
      arbChanged = arb.setMetadata(key, hit.placeholders) || arbChanged;
      replacements.putIfAbsent(hit.filePath, () => []).add(
            Replacement(
              start: hit.start,
              end: hit.end,
              replacement: hit.replacementForKey(key),
            ),
          );
    }

    final actuallyAdded = <String, String>{};
    for (final entry in additions.entries) {
      if (!arb.values.containsKey(entry.key)) {
        arb.values[entry.key] = entry.value;
        actuallyAdded[entry.key] = entry.value;
        arbChanged = true;
      }
    }

    if (arbChanged) {
      arb.write();
    }

    final updatedFiles =
        DartEditor(projectRoot: projectRoot).applyReplacements(replacements);

    return ApplyReport(
      scanned: report,
      arbPath: arb.file.path,
      addedToArb: actuallyAdded.length,
      updatedFiles: updatedFiles,
    );
  }

  Future<GenReport> gen() async {
    final result = await Process.run(
      'flutter',
      ['gen-l10n'],
      workingDirectory: projectRoot,
      runInShell: true,
    );
    return GenReport(
      exitCode: result.exitCode,
      stdout: result.stdout.toString(),
      stderr: result.stderr.toString(),
    );
  }

  CheckReport check() {
    final report = scan();
    return CheckReport(scanned: report);
  }

  String? _arbDirFromL10nYaml() {
    final file = File(p.join(projectRoot, 'l10n.yaml'));
    if (!file.existsSync()) return null;
    for (final rawLine in file.readAsLinesSync()) {
      final line = rawLine.trim();
      if (line.startsWith('#')) continue;
      final match = RegExp(r'^arb-dir:\s*(.+?)\s*$').firstMatch(line);
      if (match != null) {
        return match.group(1)!.replaceAll('"', '').replaceAll("'", '');
      }
    }
    return null;
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
