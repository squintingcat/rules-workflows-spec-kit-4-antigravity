import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/source/line_info.dart';

import 'models.dart';
import 'path_utils.dart';

class DartProjectAnalyzer {
  DartProjectAnalyzer({required this.repoRoot});

  final String repoRoot;

  List<FileSignals> analyze({
    required List<String> productionFiles,
    required DocumentationSignals documentationSignals,
  }) {
    final results = <FileSignals>[];

    for (final relativePath in productionFiles) {
      final normalized = toPosixPath(relativePath);
      final file = File('$repoRoot/$normalized');
      if (!file.existsSync()) {
        continue;
      }

      final source = file.readAsStringSync();
      final parse = parseString(path: normalized, content: source);
      final collector = _SignalCollector(
        filePath: normalized,
        moduleKey: moduleKeyFromPath(normalized),
        lineInfo: parse.lineInfo,
      );
      parse.unit.visitChildren(collector);
      collector.collectCommentHints(source);

      final moduleHints =
          documentationSignals.moduleHints[collector.moduleKey] ??
          const <String>[];
      final moduleRoutes =
          documentationSignals.moduleRoutes[collector.moduleKey] ??
          const <String>[];
      collector.mergeDocumentationHints(
        moduleHints: moduleHints,
        moduleRoutes: moduleRoutes,
      );

      results.add(collector.build());
    }

    results.sort((a, b) => a.filePath.compareTo(b.filePath));
    return results;
  }
}

class _SignalCollector extends RecursiveAstVisitor<void> {
  _SignalCollector({
    required this.filePath,
    required this.moduleKey,
    required this.lineInfo,
  });

  final String filePath;
  final String moduleKey;
  final LineInfo lineInfo;

  final Set<String> _screens = <String>{};
  final Set<String> _widgets = <String>{};
  final Set<String> _instantiatedWidgets = <String>{};
  final Set<String> _routes = <String>{};
  final Set<String> _navigationTransitions = <String>{};
  final Set<String> _uiActions = <String>{};
  final Set<String> _forms = <String>{};
  final Set<String> _validations = <String>{};
  final Set<String> _guards = <String>{};
  final Set<String> _errors = <String>{};
  final Set<String> _repositoryCalls = <String>{};
  final Set<String> _serviceCalls = <String>{};
  final Set<String> _stateChanges = <String>{};
  final Set<String> _supabaseInteractions = <String>{};
  final Set<String> _crudOps = <String>{};
  final Set<String> _authOps = <String>{};
  final Set<String> _commentHints = <String>{};
  final List<SourceReference> _references = <SourceReference>[];

  String get featureKey => featureKeyFromPath(filePath);

  bool get _isUiByPath => isUiLikelyFilePath(filePath);

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    super.visitClassDeclaration(node);

    final className = node.name.lexeme;
    final extendsName = node.extendsClause?.superclass.name.lexeme ?? '';
    final mixins =
        node.withClause?.mixinTypes.map((item) => item.toSource()).toList() ??
        const <String>[];

    final looksLikeWidget =
        _widgetTypeMarkers.any((marker) => extendsName.contains(marker)) ||
        mixins.any((mixin) => mixin.contains('Widget'));

    final looksLikeScreen = _screenNamePattern.hasMatch(className);
    final looksLikeWidgetClass = _widgetNamePattern.hasMatch(className);

    if (looksLikeScreen || (looksLikeWidget && looksLikeWidgetClass)) {
      _screens.add(className);
      _addReference(node.name.offset, 'screen:$className');
    } else if (looksLikeWidget || looksLikeWidgetClass) {
      _widgets.add(className);
      _addReference(node.name.offset, 'widget:$className');
    }

    if (_stateTypePattern.hasMatch(className)) {
      _stateChanges.add('state_holder:$className');
      _addReference(node.name.offset, 'state_holder:$className');
    }
  }

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    super.visitInstanceCreationExpression(node);

    final typeName = node.constructorName.type.toSource();
    final normalizedType = typeName.split('<').first.trim();
    final lowerType = typeName.toLowerCase();

    if (_formTypePattern.hasMatch(typeName)) {
      _forms.add(typeName);
      _addReference(node.offset, 'form:$typeName');
    }

    if (typeName == 'GoRoute') {
      final path = _extractNamedStringArgument(node, 'path');
      if (path != null) {
        _routes.add(path);
        _addReference(node.offset, 'route:$path');
      }
      final name = _extractNamedStringArgument(node, 'name');
      if (name != null) {
        _routes.add('name:$name');
        _addReference(node.offset, 'route_name:$name');
      }
    }

    if (lowerType.contains('supabase') && !_isFrameworkUiSymbol(typeName)) {
      _supabaseInteractions.add('construct:$typeName');
      _addReference(node.offset, 'supabase_construct:$typeName');
    }

    if (_uiActionWidgetTypes.contains(typeName)) {
      _uiActions.add('widget:$typeName');
      _addReference(node.offset, 'ui_action_widget:$typeName');
    }

    if (_looksLikeCustomJourneyWidget(normalizedType)) {
      _instantiatedWidgets.add(normalizedType);
      _addReference(node.offset, 'instantiated_widget:$normalizedType');
    }
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    super.visitMethodInvocation(node);

    final methodName = node.methodName.name;
    final lowerMethod = methodName.toLowerCase();
    final target = node.target?.toSource() ?? '';
    final lowerTarget = target.toLowerCase();
    final callLabel = target.isEmpty ? methodName : '$target.$methodName';

    if (_navigationMethods.contains(methodName)) {
      String routeTarget = methodName;
      final firstArgument = node.argumentList.arguments.isNotEmpty
          ? node.argumentList.arguments.first
          : null;
      if (firstArgument is StringLiteral) {
        routeTarget = firstArgument.stringValue ?? firstArgument.toSource();
      }
      _navigationTransitions.add(routeTarget);
      _addReference(node.methodName.offset, 'navigation:$routeTarget');
    }

    if (methodName == 'validate') {
      _validations.add('form_validate_call');
      _addReference(node.methodName.offset, 'validation:validate()');
    }

    if (_stateChangeMethods.contains(methodName)) {
      _stateChanges.add(methodName);
      _addReference(node.methodName.offset, 'state_change:$methodName');
    }

    if (_authMethodPattern.hasMatch(methodName) ||
        _authMethodPattern.hasMatch(target)) {
      _authOps.add(methodName);
      _crudOps.add('auth');
      _addReference(node.methodName.offset, 'auth:$methodName');
    }

    if (_crudCreatePattern.hasMatch(methodName)) {
      _crudOps.add('create');
      _addReference(node.methodName.offset, 'crud:create:$methodName');
    }
    if (_crudReadPattern.hasMatch(methodName)) {
      _crudOps.add('read');
      _addReference(node.methodName.offset, 'crud:read:$methodName');
    }
    if (_crudUpdatePattern.hasMatch(methodName)) {
      _crudOps.add('update');
      _addReference(node.methodName.offset, 'crud:update:$methodName');
    }
    if (_crudDeletePattern.hasMatch(methodName)) {
      _crudOps.add('delete');
      _addReference(node.methodName.offset, 'crud:delete:$methodName');
    }

    if (_looksLikeRepositoryTarget(lowerTarget, lowerMethod)) {
      _repositoryCalls.add(callLabel);
      _addReference(node.methodName.offset, 'repository_call:$callLabel');
    }

    if (_looksLikeServiceOrControllerTarget(lowerTarget, lowerMethod)) {
      _serviceCalls.add(callLabel);
      _addReference(node.methodName.offset, 'service_call:$callLabel');
    }

    final looksSupabaseCall =
        !_isFrameworkUiSymbol(target) &&
        !_isFrameworkUiSymbol(methodName) &&
        (lowerTarget.contains('supabase') ||
            _supabaseMethodNames.contains(methodName) ||
            (lowerTarget.contains('.auth') &&
                _supabaseAuthMethodNames.contains(methodName)));
    if (looksSupabaseCall) {
      _supabaseInteractions.add(callLabel);
      _addReference(node.methodName.offset, 'supabase_call:$callLabel');
    }

    if (_retryPattern.hasMatch(lowerMethod)) {
      _errors.add('retry:$methodName');
      _addReference(node.methodName.offset, 'retry:$methodName');
    }

    if (_errorPattern.hasMatch(lowerMethod) ||
        _errorPattern.hasMatch(lowerTarget)) {
      _errors.add('error_handler:$target.$methodName');
      _addReference(
        node.methodName.offset,
        'error_handler:$target.$methodName',
      );
    }
  }

  bool _looksLikeRepositoryTarget(String lowerTarget, String lowerMethod) {
    return lowerTarget.contains('repository') ||
        lowerMethod.contains('repository') ||
        lowerTarget.endsWith('repo') ||
        lowerTarget.contains('repoprovider');
  }

  bool _looksLikeServiceOrControllerTarget(
    String lowerTarget,
    String lowerMethod,
  ) {
    return lowerTarget.contains('service') ||
        lowerMethod.contains('service') ||
        lowerTarget.contains('controller') ||
        lowerTarget.contains('notifier') ||
        lowerTarget.contains('provider.notifier') ||
        lowerTarget.contains('provider)');
  }

  bool _isFrameworkUiSymbol(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty) {
      return false;
    }

    if (_uiFrameworkTypeNames.contains(normalized)) {
      return true;
    }

    return _uiFrameworkPrefixes.any(normalized.startsWith);
  }

  bool _looksLikeCustomJourneyWidget(String typeName) {
    if (typeName.isEmpty || _isFrameworkUiSymbol(typeName)) {
      return false;
    }
    if (typeName.startsWith('_')) {
      return false;
    }

    return _screenNamePattern.hasMatch(typeName) ||
        _widgetNamePattern.hasMatch(typeName) ||
        typeName.endsWith('Tab') ||
        typeName.endsWith('View') ||
        typeName.endsWith('Dialog') ||
        typeName.endsWith('Wizard');
  }

  @override
  void visitNamedExpression(NamedExpression node) {
    super.visitNamedExpression(node);

    final name = node.name.label.name;
    final valueSource = node.expression.toSource();

    if (_uiCallbackNames.contains(name) && valueSource != 'null') {
      _uiActions.add('$name:$valueSource');
      _addReference(node.name.offset, 'ui_action:$name');
    }

    if (name == 'validator') {
      _validations.add('validator:$valueSource');
      _addReference(node.name.offset, 'validation:validator');
    }

    if (name == 'redirect') {
      _guards.add('router_redirect');
      _addReference(node.name.offset, 'guard:router_redirect');
    }
  }

  @override
  void visitIfStatement(IfStatement node) {
    super.visitIfStatement(node);

    final expression = node.expression.toSource();
    final lowerExpression = expression.toLowerCase();

    if (_guardPattern.hasMatch(lowerExpression)) {
      _guards.add(expression);
      _addReference(node.offset, 'guard:$expression');
    }

    if (_validationPattern.hasMatch(lowerExpression)) {
      _validations.add(expression);
      _addReference(node.offset, 'validation:$expression');
    }

    if (_statusPattern.hasMatch(lowerExpression)) {
      _stateChanges.add('status_branch:$expression');
      _addReference(node.offset, 'status_branch:$expression');
    }
  }

  @override
  void visitCatchClause(CatchClause node) {
    super.visitCatchClause(node);

    final exceptionType = node.exceptionType?.toSource() ?? 'dynamic';
    _errors.add('catch:$exceptionType');
    _addReference(node.offset, 'error_catch:$exceptionType');
  }

  @override
  void visitThrowExpression(ThrowExpression node) {
    super.visitThrowExpression(node);

    _errors.add('throw:${node.expression.toSource()}');
    _addReference(node.offset, 'error_throw:${node.expression.toSource()}');
  }

  void collectCommentHints(String source) {
    final lines = source.split('\n');
    for (var index = 0; index < lines.length; index += 1) {
      final line = lines[index].trim();
      if (!(line.startsWith('//') || line.startsWith('///'))) {
        continue;
      }
      final lower = line.toLowerCase();
      if (_commentHintKeywords.any((keyword) => lower.contains(keyword))) {
        _commentHints.add(line);
        _references.add(
          SourceReference(
            file: filePath,
            line: index + 1,
            column: 1,
            label: 'comment_hint:$line',
          ),
        );
      }
    }
  }

  void mergeDocumentationHints({
    required List<String> moduleHints,
    required List<String> moduleRoutes,
  }) {
    for (final hint in moduleHints) {
      _commentHints.add('doc:$hint');
    }
    for (final route in moduleRoutes) {
      _routes.add(route);
    }
  }

  FileSignals build() {
    return FileSignals(
      filePath: filePath,
      moduleKey: moduleKey,
      featureKey: featureKey,
      isUiFile: _isUiByPath,
      screens: _screens,
      widgets: _widgets,
      instantiatedWidgets: _instantiatedWidgets,
      routes: _routes,
      navigationTransitions: _navigationTransitions,
      uiActions: _uiActions,
      forms: _forms,
      validations: _validations,
      guards: _guards,
      errorPaths: _errors,
      repositoryCalls: _repositoryCalls,
      serviceCalls: _serviceCalls,
      stateChanges: _stateChanges,
      supabaseInteractions: _supabaseInteractions,
      crudOperations: _crudOps,
      authOperations: _authOps,
      commentHints: _commentHints,
      references: _references,
    );
  }

  void _addReference(int offset, String label) {
    final location = lineInfo.getLocation(offset);
    _references.add(
      SourceReference(
        file: filePath,
        line: location.lineNumber,
        column: location.columnNumber,
        label: label,
      ),
    );
  }

  String? _extractNamedStringArgument(
    InstanceCreationExpression node,
    String argumentName,
  ) {
    for (final argument in node.argumentList.arguments) {
      if (argument is! NamedExpression) {
        continue;
      }
      if (argument.name.label.name != argumentName) {
        continue;
      }
      final expression = argument.expression;
      if (expression is StringLiteral) {
        return expression.stringValue;
      }
    }
    return null;
  }
}

final RegExp _screenNamePattern = RegExp(r'(Screen|View|Page|Dialog|Wizard)$');
final RegExp _widgetNamePattern = RegExp(r'(Widget|Tile|Card|Form|Button)$');
final RegExp _stateTypePattern = RegExp(
  r'(Controller|Notifier|Bloc|Cubit|State)$',
);
final RegExp _formTypePattern = RegExp(
  r'(Form|TextFormField|DropdownButtonFormField)',
);
final RegExp _authMethodPattern = RegExp(
  r'(signIn|signOut|login|logout|register|otp|verify)',
);
final RegExp _crudCreatePattern = RegExp(r'(create|add|insert|save)');
final RegExp _crudReadPattern = RegExp(
  r'(get|fetch|watch|load|list|find|read|query|stream)',
);
final RegExp _crudUpdatePattern = RegExp(r'(update|edit|patch|upsert)');
final RegExp _crudDeletePattern = RegExp(r'(delete|remove|archive)');
final RegExp _retryPattern = RegExp(r'(retry|tryagain|reconnect)');
final RegExp _errorPattern = RegExp(
  r'(error|fail|exception|denied|forbidden|invalid)',
);
final RegExp _guardPattern = RegExp(
  r'(auth|permission|role|allow|deny|forbid|guard|isauthenticated|logged|flavor|currentuser|null)',
);
final RegExp _validationPattern = RegExp(
  r'(validate|invalid|required|empty|length|format|contains\(@\)|regex|null)',
);
final RegExp _statusPattern = RegExp(
  r'(status|state|loading|success|error|pending)',
);
const Set<String> _widgetTypeMarkers = <String>{
  'Widget',
  'ConsumerWidget',
  'ConsumerStatefulWidget',
  'StatefulWidget',
  'StatelessWidget',
};

const Set<String> _navigationMethods = <String>{
  'go',
  'goNamed',
  'push',
  'pushNamed',
  'pushReplacement',
  'pushReplacementNamed',
  'replace',
  'pop',
};

const Set<String> _uiCallbackNames = <String>{
  'onPressed',
  'onTap',
  'onLongPress',
  'onSubmitted',
  'onFieldSubmitted',
  'onChanged',
};

const Set<String> _uiActionWidgetTypes = <String>{
  'FilledButton',
  'TextButton',
  'ElevatedButton',
  'IconButton',
  'GestureDetector',
  'InkWell',
  'ListTile',
};

const Set<String> _supabaseMethodNames = <String>{
  'from',
  'rpc',
  'select',
  'insert',
  'update',
  'delete',
  'upsert',
  'eq',
  'neq',
  'or',
  'order',
  'limit',
  'single',
  'maybeSingle',
};

const Set<String> _supabaseAuthMethodNames = <String>{
  'signInWithOtp',
  'signInWithPassword',
  'signUp',
  'signOut',
  'getSession',
  'refreshSession',
  'resetPasswordForEmail',
  'verifyOtp',
};

const Set<String> _uiFrameworkTypeNames = <String>{
  'AlertDialog',
  'AppBar',
  'AppDrawerLayout',
  'AppMainHeader',
  'AppPrimaryButton',
  'AppSidebarItem',
  'AppSidebarSectionHeader',
  'AppTextFormField',
  'ButtonSegment',
  'Center',
  'CircularProgressIndicator',
  'Column',
  'Container',
  'ContextHelpButton',
  'DropdownButtonFormField',
  'FilledButton',
  'Form',
  'GestureDetector',
  'Icon',
  'IconButton',
  'Image',
  'InkWell',
  'InputDecoration',
  'LinearProgressIndicator',
  'ListTile',
  'OutlinedButton',
  'Padding',
  'PopupMenuButton',
  'RefreshIndicator',
  'Row',
  'Scaffold',
  'SegmentedButton',
  'SingleChildScrollView',
  'SizedBox',
  'SnackBar',
  'Stepper',
  'Text',
  'TextButton',
  'TextFormField',
};

const Set<String> _uiFrameworkPrefixes = <String>{
  'Icons.',
  'MaterialLocalizations.',
  'Theme.of',
};

const Set<String> _stateChangeMethods = <String>{
  'setState',
  'copyWith',
  'emit',
  'update',
  'notifyListeners',
};

const Set<String> _commentHintKeywords = <String>{
  'todo',
  'guard',
  'validation',
  'error',
  'retry',
  'supabase',
  'auth',
  'navigate',
  'flow',
};
