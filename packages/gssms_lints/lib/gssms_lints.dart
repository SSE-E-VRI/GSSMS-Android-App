import 'package:analyzer/error/error.dart' show ErrorSeverity;
import 'package:analyzer/error/listener.dart';
import 'package:custom_lint_builder/custom_lint_builder.dart';

PluginBase createPlugin() => _GssmsLints();

class _GssmsLints extends PluginBase {
  @override
  List<LintRule> getLintRules(CustomLintConfigs configs) => [
        const AvoidHardcodedColor(),
        const AvoidBareFontSize(),
      ];
}

bool _inFeatures(String path) {
  final normalized = path.replaceAll('\\', '/');
  return normalized.contains('/lib/features/');
}

class AvoidHardcodedColor extends DartLintRule {
  const AvoidHardcodedColor() : super(code: _code);

  static const _code = LintCode(
    name: 'avoid_hardcoded_color',
    problemMessage:
        'Use AppTheme / module / status tokens instead of Color(0xFF…) in lib/features/.',
    errorSeverity: ErrorSeverity.WARNING,
  );

  @override
  void run(
    CustomLintResolver resolver,
    ErrorReporter reporter,
    CustomLintContext context,
  ) {
    if (!_inFeatures(resolver.path)) return;

    context.registry.addInstanceCreationExpression((node) {
      final typeName = node.constructorName.type.toSource();
      if (typeName != 'Color') return;
      if (node.argumentList.arguments.isEmpty) return;
      final source = node.argumentList.arguments.first.toSource().toUpperCase();
      if (source.contains('0XFF')) {
        reporter.atNode(node, code);
      }
    });
  }
}

class AvoidBareFontSize extends DartLintRule {
  const AvoidBareFontSize() : super(code: _code);

  static const _code = LintCode(
    name: 'avoid_bare_font_size',
    problemMessage:
        'Use Theme.of(context).textTheme instead of a bare fontSize: in lib/features/.',
    errorSeverity: ErrorSeverity.WARNING,
  );

  @override
  void run(
    CustomLintResolver resolver,
    ErrorReporter reporter,
    CustomLintContext context,
  ) {
    if (!_inFeatures(resolver.path)) return;
    // package:pdf layout styles (e.g. *_pdf_service.dart) are print layout,
    // not Flutter text — Theme.of(context).textTheme does not apply there.
    if (resolver.path.replaceAll('\\', '/').endsWith('_pdf_service.dart')) {
      return;
    }

    context.registry.addNamedExpression((node) {
      if (node.name.label.name == 'fontSize') {
        reporter.atNode(node, code);
      }
    });
  }
}
