import 'dart:io';

import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/source/line_info.dart';
import 'package:path/path.dart' as p;

import 'models.dart';

class StaticTextScanner {
  StaticTextScanner({
    required this.projectRoot,
    required this.libDir,
  });

  final String projectRoot;
  final Directory libDir;

  ScanReport scan() {
    if (!libDir.existsSync()) {
      return const ScanReport(hits: [], skipped: [], filesScanned: 0);
    }

    final files = libDir
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .where((file) => !file.path.endsWith('.g.dart'))
        .where((file) => !file.path.endsWith('.freezed.dart'))
        .where(
            (file) => !file.path.contains('${p.separator}l10n${p.separator}'))
        .toList();

    final hits = <StaticTextHit>[];
    final skipped = <SkippedText>[];

    for (final file in files) {
      final result = parseFile(
        path: file.path,
        featureSet: FeatureSet.latestLanguageVersion(),
      );
      final visitor = _UiTextVisitor(
        filePath: file.path,
        source: file.readAsStringSync(),
        lineInfo: result.lineInfo,
      );
      result.unit.accept(visitor);
      hits.addAll(visitor.hits);
      skipped.addAll(visitor.skipped);
    }

    hits.sort((a, b) {
      final byFile = a.filePath.compareTo(b.filePath);
      if (byFile != 0) return byFile;
      return a.start.compareTo(b.start);
    });

    return ScanReport(
      hits: _dedupe(hits),
      skipped: skipped,
      filesScanned: files.length,
    );
  }

  List<StaticTextHit> _dedupe(List<StaticTextHit> hits) {
    final seen = <String>{};
    final result = <StaticTextHit>[];
    for (final hit in hits) {
      final key = '${hit.filePath}:${hit.start}:${hit.end}:${hit.text}';
      if (seen.add(key)) result.add(hit);
    }
    return result;
  }
}

class _UiTextVisitor extends GeneralizingAstVisitor<void> {
  _UiTextVisitor({
    required this.filePath,
    required this.source,
    required this.lineInfo,
  });

  final String filePath;
  final String source;
  final LineInfo lineInfo;
  final hits = <StaticTextHit>[];
  final skipped = <SkippedText>[];
  final variables = <String, _StringInfo>{};

  static const _textConstructors = {
    'Text',
    'SelectableText',
  };

  static const _uiProperties = {
    'hintText',
    'labelText',
    'helperText',
    'errorText',
    'counterText',
    'prefixText',
    'suffixText',
    'semanticLabel',
    'semanticsLabel',
    'tooltip',
    'message',
    'barrierLabel',
    'title',
    'subtitle',
    'label',
    'content',
  };

  @override
  void visitVariableDeclaration(VariableDeclaration node) {
    final initializer = node.initializer;
    if (initializer != null) {
      final info = _stringInfo(initializer);
      if (info != null && _isUiText(info.text)) {
        variables[node.name.lexeme] = info;
      }
    }
    super.visitVariableDeclaration(node);
  }

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    final typeName = node.constructorName.type.name.lexeme;

    if (_textConstructors.contains(typeName)) {
      final argument = node.argumentList.arguments
          .where((argument) => argument is! NamedExpression)
          .firstOrNull;
      if (argument is Expression) {
        _recordExpression(
          argument,
          kind: typeName == 'SelectableText'
              ? HitKind.selectableTextWidget
              : HitKind.textWidget,
        );
      }
    }

    if (typeName == 'TextSpan') {
      final textArgument = _namedArgument(node.argumentList, 'text');
      if (textArgument != null) {
        _recordExpression(textArgument, kind: HitKind.textSpan);
      }
    }

    super.visitInstanceCreationExpression(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final name = node.methodName.name;

    if (_textConstructors.contains(name)) {
      final argument = node.argumentList.arguments
          .where((argument) => argument is! NamedExpression)
          .firstOrNull;
      if (argument is Expression) {
        _recordExpression(
          argument,
          kind: name == 'SelectableText'
              ? HitKind.selectableTextWidget
              : HitKind.textWidget,
        );
      }
    }

    if (name == 'TextSpan') {
      final textArgument = _namedArgument(node.argumentList, 'text');
      if (textArgument != null) {
        _recordExpression(textArgument, kind: HitKind.textSpan);
      }
    }

    super.visitMethodInvocation(node);
  }

  @override
  void visitNamedExpression(NamedExpression node) {
    final name = node.name.label.name;
    if (_uiProperties.contains(name)) {
      _recordExpression(
        node.expression,
        kind: HitKind.property,
        propertyName: name,
      );
    }
    super.visitNamedExpression(node);
  }

  @override
  void visitReturnStatement(ReturnStatement node) {
    final expression = node.expression;
    if (expression != null && _insideValidator(node)) {
      _recordExpression(expression, kind: HitKind.validationReturn);
    }
    super.visitReturnStatement(node);
  }

  void _recordExpression(
    Expression expression, {
    required HitKind kind,
    String? propertyName,
  }) {
    final info = _stringInfo(expression);
    if (info != null) {
      if (!_isUiText(info.text)) return;
      hits.add(_hitForExpression(
        expression,
        info,
        kind: kind,
        propertyName: propertyName,
      ));
      return;
    }

    if (expression is SimpleIdentifier) {
      final variableInfo = variables[expression.name];
      if (variableInfo != null) {
        hits.add(_hitForExpression(
          expression,
          variableInfo,
          kind: HitKind.indirectVariable,
          propertyName: propertyName,
        ));
      }
    }
  }

  StaticTextHit _hitForExpression(
    Expression expression,
    _StringInfo info, {
    required HitKind kind,
    String? propertyName,
  }) {
    return StaticTextHit(
      filePath: filePath,
      start: expression.offset,
      end: expression.end,
      text: info.text,
      kind: kind,
      line: lineInfo.getLocation(expression.offset).lineNumber,
      propertyName: propertyName,
      placeholders: info.placeholders,
      placeholderArguments: info.placeholderArguments,
      canReplace: info.canReplace,
    );
  }

  _StringInfo? _stringInfo(Expression expression) {
    expression = expression.unParenthesized;

    if (expression is SimpleStringLiteral) {
      return _StringInfo(
        text: expression.value,
        placeholders: const [],
        placeholderArguments: const [],
        canReplace: true,
      );
    }

    if (expression is AdjacentStrings) {
      final parts = <_StringInfo>[];
      for (final string in expression.strings) {
        final info = _stringInfo(string);
        if (info == null) return null;
        parts.add(info);
      }
      return _combine(parts, canReplace: true);
    }

    if (expression is StringInterpolation) {
      return _interpolationInfo(expression);
    }

    if (expression is BinaryExpression &&
        expression.operator.type == TokenType.PLUS) {
      return _concatInfo(expression);
    }

    if (expression is SimpleIdentifier) {
      return variables[expression.name];
    }

    return null;
  }

  _StringInfo _interpolationInfo(StringInterpolation expression) {
    final buffer = StringBuffer();
    final placeholders = <String>[];
    final placeholderArguments = <String>[];
    var placeholderIndex = 1;
    var canReplace = true;

    for (final element in expression.elements) {
      if (element is InterpolationString) {
        buffer.write(element.value);
      } else if (element is InterpolationExpression) {
        final placeholder =
            _placeholderFor(element.expression, placeholderIndex);
        placeholderIndex++;
        placeholders.add(placeholder);
        placeholderArguments.add(_sourceFor(element.expression));
        buffer.write('{$placeholder}');
        if (!_canUseAsArgument(element.expression)) {
          canReplace = false;
        }
      }
    }

    return _StringInfo(
      text: buffer.toString(),
      placeholders: placeholders,
      placeholderArguments: placeholderArguments,
      canReplace: canReplace,
    );
  }

  _StringInfo? _concatInfo(BinaryExpression expression) {
    final parts = <_StringInfo>[];
    var containsString = false;

    void collect(Expression expression) {
      expression = expression.unParenthesized;
      if (expression is BinaryExpression &&
          expression.operator.type == TokenType.PLUS) {
        collect(expression.leftOperand);
        collect(expression.rightOperand);
        return;
      }

      if (expression is SimpleIdentifier ||
          expression is PrefixedIdentifier ||
          expression is PropertyAccess) {
        final placeholder = _placeholderFor(expression, parts.length + 1);
        parts.add(_StringInfo(
          text: '{$placeholder}',
          placeholders: [placeholder],
          placeholderArguments: [_sourceFor(expression)],
          canReplace: true,
        ));
        return;
      }

      final info = _stringInfo(expression);
      if (info != null) {
        containsString = true;
        parts.add(info);
        return;
      }

      final placeholder = _placeholderFor(expression, parts.length + 1);
      parts.add(_StringInfo(
        text: '{$placeholder}',
        placeholders: [placeholder],
        placeholderArguments: [_sourceFor(expression)],
        canReplace: _canUseAsArgument(expression),
      ));
    }

    collect(expression);
    if (!containsString) return null;
    return _combine(parts, canReplace: true);
  }

  _StringInfo _combine(List<_StringInfo> parts, {required bool canReplace}) {
    return _StringInfo(
      text: parts.map((part) => part.text).join(),
      placeholders: [
        for (final part in parts) ...part.placeholders,
      ],
      placeholderArguments: [
        for (final part in parts) ...part.placeholderArguments,
      ],
      canReplace: canReplace && parts.every((part) => part.canReplace),
    );
  }

  String _placeholderFor(Expression expression, int index) {
    expression = expression.unParenthesized;
    if (expression is SimpleIdentifier) return expression.name;
    if (expression is PrefixedIdentifier) return expression.identifier.name;
    if (expression is PropertyAccess) return expression.propertyName.name;
    return 'value$index';
  }

  bool _canUseAsArgument(Expression expression) {
    expression = expression.unParenthesized;
    return expression is SimpleIdentifier ||
        expression is PrefixedIdentifier ||
        expression is PropertyAccess;
  }

  String _sourceFor(Expression expression) {
    return source.substring(expression.offset, expression.end);
  }

  Expression? _namedArgument(ArgumentList arguments, String name) {
    for (final argument in arguments.arguments) {
      if (argument is NamedExpression && argument.name.label.name == name) {
        return argument.expression;
      }
    }
    return null;
  }

  bool _insideValidator(AstNode node) {
    AstNode? current = node.parent;
    while (current != null) {
      if (current is NamedExpression &&
          current.name.label.name == 'validator') {
        return true;
      }
      if (current is FunctionDeclaration &&
          current.name.lexeme.toLowerCase().contains('validator')) {
        return true;
      }
      if (current is MethodDeclaration &&
          current.name.lexeme.toLowerCase().contains('validator')) {
        return true;
      }
      current = current.parent;
    }
    return false;
  }

  bool _isUiText(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return false;
    if (trimmed.length == 1 && RegExp(r'^[^\w]$').hasMatch(trimmed)) {
      return false;
    }
    if (RegExp(r'^(https?:|assets/|images/|icons/|package:)')
        .hasMatch(trimmed)) {
      return false;
    }
    return true;
  }
}

class _StringInfo {
  const _StringInfo({
    required this.text,
    required this.placeholders,
    required this.placeholderArguments,
    required this.canReplace,
  });

  final String text;
  final List<String> placeholders;
  final List<String> placeholderArguments;
  final bool canReplace;
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
