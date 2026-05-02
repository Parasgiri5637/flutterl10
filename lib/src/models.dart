enum HitKind {
  textWidget,
  selectableTextWidget,
  textSpan,
  property,
  validationReturn,
  materialPageRouteTitle,
  indirectVariable,
  dynamicExpression,
}

class StaticTextHit {
  const StaticTextHit({
    required this.filePath,
    required this.start,
    required this.end,
    required this.text,
    required this.kind,
    required this.line,
    this.propertyName,
    this.placeholders = const [],
    this.placeholderArguments = const [],
    this.canReplace = true,
  });

  final String filePath;
  final int start;
  final int end;
  final String text;
  final HitKind kind;
  final int line;
  final String? propertyName;
  final List<String> placeholders;
  final List<String> placeholderArguments;
  final bool canReplace;

  String replacementForKey(String key) {
    final localization = 'AppLocalizations.of(context)!';
    final arguments =
        placeholderArguments.isEmpty ? placeholders : placeholderArguments;
    final access = placeholders.isEmpty
        ? '$localization.$key'
        : '$localization.$key(${arguments.join(', ')})';
    return switch (kind) {
      HitKind.textWidget => access,
      HitKind.selectableTextWidget => access,
      HitKind.textSpan => access,
      HitKind.property => access,
      HitKind.validationReturn => access,
      HitKind.materialPageRouteTitle => access,
      HitKind.indirectVariable => access,
      HitKind.dynamicExpression => access,
    };
  }
}

class SkippedText {
  const SkippedText({
    required this.filePath,
    required this.line,
    required this.reason,
    required this.snippet,
  });

  final String filePath;
  final int line;
  final String reason;
  final String snippet;
}

class ScanReport {
  const ScanReport({
    required this.hits,
    required this.skipped,
    required this.filesScanned,
  });

  final List<StaticTextHit> hits;
  final List<SkippedText> skipped;
  final int filesScanned;
}

class Replacement {
  const Replacement({
    required this.start,
    required this.end,
    required this.replacement,
  });

  final int start;
  final int end;
  final String replacement;
}

class ApplyReport {
  const ApplyReport({
    required this.scanned,
    required this.arbPath,
    required this.addedToArb,
    required this.updatedFiles,
  });

  final ScanReport scanned;
  final String arbPath;
  final int addedToArb;
  final int updatedFiles;
}

class CheckReport {
  const CheckReport({required this.scanned});

  final ScanReport scanned;
}

class GenReport {
  const GenReport({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });

  final int exitCode;
  final String stdout;
  final String stderr;
}
