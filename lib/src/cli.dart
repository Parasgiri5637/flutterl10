import 'dart:io';

import 'package:args/args.dart';
import 'package:path/path.dart' as p;

import 'flutter_l10_tool.dart';
import 'models.dart';

class FlutterL10Cli {
  Future<void> run(List<String> arguments) async {
    final parser = _buildParser();

    late ArgResults results;
    try {
      results = parser.parse(arguments);
    } on FormatException catch (error) {
      stderr.writeln(error.message);
      stderr.writeln('');
      _printUsage(parser);
      exitCode = 64;
      return;
    }

    if (results['help'] == true || results.command == null) {
      _printUsage(parser);
      return;
    }

    final command = results.command!;
    final tool = FlutterL10Tool(
      projectRoot: results['project-root'] as String?,
      libDirectory: results['lib-dir'] as String,
      arbDirectory: results['arb-dir'] as String?,
      arbFileName: results['arb-file'] as String,
    );

    try {
      switch (command.name) {
        case 'scan':
          _printScan(tool.scan(), tool.projectRoot);
          break;
        case 'apply':
          final report = tool.apply();
          _printApply(report, tool.projectRoot);
          final genAfterApply = command['gen'] as bool;
          if (genAfterApply) {
            final genReport = await tool.gen();
            _printGen(genReport);
            if (genReport.exitCode != 0) exitCode = genReport.exitCode;
          }
          break;
        case 'check':
          final report = tool.check();
          _printCheck(report, tool.projectRoot);
          if (report.scanned.hits.isNotEmpty) exitCode = 1;
          break;
        case 'gen':
          final report = await tool.gen();
          _printGen(report);
          if (report.exitCode != 0) exitCode = report.exitCode;
          break;
        default:
          stderr.writeln('Unknown command: ${command.name}');
          exitCode = 64;
      }
    } on Object catch (error) {
      stderr.writeln('flutterl10 failed: $error');
      exitCode = 1;
    }
  }

  ArgParser _buildParser() {
    final parser = ArgParser()
      ..addFlag('help', abbr: 'h', negatable: false, help: 'Show usage.')
      ..addOption(
        'project-root',
        help: 'Flutter project root. Defaults to the current directory.',
      )
      ..addOption(
        'lib-dir',
        defaultsTo: 'lib',
        help: 'Directory to scan inside the project root.',
      )
      ..addOption(
        'arb-dir',
        help:
            'ARB directory. Defaults to l10n.yaml arb-dir, lib/l10n, then l10n.',
      )
      ..addOption(
        'arb-file',
        defaultsTo: 'app_en.arb',
        help: 'English ARB file name.',
      );

    parser.addCommand('scan');
    parser.addCommand('check');
    parser.addCommand('gen');
    parser.addCommand(
      'apply',
      ArgParser()
        ..addFlag(
          'gen',
          defaultsTo: true,
          help: 'Run flutter gen-l10n after replacing text.',
        ),
    );
    return parser;
  }

  void _printUsage(ArgParser parser) {
    stdout.writeln('Flutter static UI text localization tool');
    stdout.writeln('');
    stdout.writeln('Usage: flutterl10 <command> [options]');
    stdout.writeln('');
    stdout.writeln('Commands:');
    stdout.writeln('  scan    Find static UI texts in lib');
    stdout.writeln(
        '  apply   Add texts to app_en.arb, replace Dart literals, then run gen-l10n');
    stdout.writeln(
        '  check   Count remaining static UI texts and exit 1 if any remain');
    stdout.writeln('  gen     Run flutter gen-l10n');
    stdout.writeln('');
    stdout.writeln(parser.usage);
  }

  void _printScan(ScanReport report, String root) {
    stdout.writeln('Scan complete');
    stdout.writeln('Files scanned: ${report.filesScanned}');
    stdout.writeln('Total static texts found: ${report.hits.length}');
    stdout.writeln('Skipped or unsupported cases: ${report.skipped.length}');
    _printHits(report, root);
  }

  void _printApply(ApplyReport report, String root) {
    stdout.writeln('Apply complete');
    stdout.writeln('Total static texts found: ${report.scanned.hits.length}');
    stdout.writeln('Total texts added to app_en.arb: ${report.addedToArb}');
    stdout.writeln('Total UI files updated: ${report.updatedFiles}');
    stdout.writeln('ARB file: ${p.relative(report.arbPath, from: root)}');
    stdout.writeln(
        'Skipped or unsupported cases: ${report.scanned.skipped.length}');
  }

  void _printCheck(CheckReport report, String root) {
    stdout.writeln('Check complete');
    stdout
        .writeln('Total remaining static texts: ${report.scanned.hits.length}');
    stdout.writeln(
        'Skipped or unsupported cases: ${report.scanned.skipped.length}');
    _printHits(report.scanned, root);
  }

  void _printGen(GenReport report) {
    stdout.writeln('flutter gen-l10n exit code: ${report.exitCode}');
    if (report.stdout.trim().isNotEmpty) {
      stdout.writeln(report.stdout.trim());
    }
    if (report.stderr.trim().isNotEmpty) {
      stderr.writeln(report.stderr.trim());
    }
  }

  void _printHits(ScanReport report, String root) {
    if (report.hits.isNotEmpty) {
      stdout.writeln('');
      stdout.writeln('Found:');
      for (final hit in report.hits.take(50)) {
        stdout.writeln(
          '  ${p.relative(hit.filePath, from: root)}:${hit.line}  "${hit.text}"',
        );
      }
      if (report.hits.length > 50) {
        stdout.writeln('  ... ${report.hits.length - 50} more');
      }
    }

    if (report.skipped.isNotEmpty) {
      stdout.writeln('');
      stdout.writeln('Skipped:');
      for (final skipped in report.skipped.take(25)) {
        stdout.writeln(
          '  ${p.relative(skipped.filePath, from: root)}:${skipped.line}  '
          '${skipped.reason}: ${skipped.snippet}',
        );
      }
      if (report.skipped.length > 25) {
        stdout.writeln('  ... ${report.skipped.length - 25} more');
      }
    }
  }
}
