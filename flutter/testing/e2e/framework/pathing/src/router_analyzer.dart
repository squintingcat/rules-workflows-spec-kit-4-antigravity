import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

class RouteBindingAnalyzer {
  RouteBindingAnalyzer({required this.repoRoot});

  final String repoRoot;

  Map<String, List<String>> analyze() {
    final routerFile = File('$repoRoot/lib/config/router.dart');
    if (!routerFile.existsSync()) {
      return const <String, List<String>>{};
    }

    final parse = parseString(
      path: 'lib/config/router.dart',
      content: routerFile.readAsStringSync(),
    );
    final collector = _RouteBindingCollector();
    return collector.collect(parse.unit);
  }
}

class _RouteBindingCollector {
  final Map<String, Set<String>> _routesByWidget = <String, Set<String>>{};

  Map<String, List<String>> collect(CompilationUnit unit) {
    final finder = _GoRouterFinder();
    unit.visitChildren(finder);
    final goRouterNode = finder.firstGoRouter;
    if (goRouterNode == null) {
      return const <String, List<String>>{};
    }

    final routesExpression = _namedExpression(goRouterNode, 'routes');
    if (routesExpression != null) {
      _collectRouteNodes(routesExpression, parentPath: '');
    }

    final normalized = <String, List<String>>{};
    final keys = _routesByWidget.keys.toList()..sort();
    for (final key in keys) {
      final routes = _routesByWidget[key]!.toList()..sort();
      normalized[key] = routes;
    }
    return normalized;
  }

  void _collectRouteNodes(Expression expression, {required String parentPath}) {
    if (expression is! ListLiteral) {
      return;
    }

    for (final element in expression.elements) {
      if (element is! Expression) {
        continue;
      }

      final typeName = _callIdentifier(element);
      if (typeName == null) {
        continue;
      }
      if (typeName == 'GoRoute') {
        _collectGoRoute(element, parentPath: parentPath);
        continue;
      }

      if (typeName.startsWith('StatefulShellRoute')) {
        final branches = _namedExpression(element, 'branches');
        if (branches != null) {
          _collectRouteNodes(branches, parentPath: parentPath);
        }
        continue;
      }

      if (typeName == 'StatefulShellBranch') {
        final routes = _namedExpression(element, 'routes');
        if (routes != null) {
          _collectRouteNodes(routes, parentPath: parentPath);
        }
      }
    }
  }

  void _collectGoRoute(Expression node, {required String parentPath}) {
    final rawPath = _namedStringLiteral(node, 'path') ?? '';
    final fullPath = _joinRoute(parentPath, rawPath);

    for (final widgetClass in _builderWidgets(node)) {
      _routesByWidget.putIfAbsent(widgetClass, () => <String>{}).add(fullPath);
    }

    final nestedRoutes = _namedExpression(node, 'routes');
    if (nestedRoutes != null) {
      _collectRouteNodes(nestedRoutes, parentPath: fullPath);
    }
  }

  Iterable<String> _builderWidgets(Expression node) sync* {
    for (final parameterName in const <String>['builder', 'pageBuilder']) {
      final builder = _namedExpression(node, parameterName);
      if (builder is! FunctionExpression) {
        continue;
      }

      final widgetClasses = _extractReturnedWidgetClasses(builder.body);
      for (final widgetClass in widgetClasses) {
        yield widgetClass;
      }
    }
  }

  Set<String> _extractReturnedWidgetClasses(FunctionBody body) {
    if (body is ExpressionFunctionBody) {
      return _widgetClassesFromExpression(body.expression);
    }

    if (body is BlockFunctionBody) {
      final collector = _ReturnExpressionCollector(
        widgetClassesFromExpression: _widgetClassesFromExpression,
      );
      body.block.visitChildren(collector);
      return collector.widgets;
    }

    return const <String>{};
  }

  Set<String> _widgetClassesFromExpression(Expression expression) {
    if (expression is InstanceCreationExpression) {
      final typeName = expression.constructorName.type.toSource();
      if (typeName == 'CustomTransitionPage') {
        final child = _namedExpression(expression, 'child');
        if (child != null) {
          return _widgetClassesFromExpression(child);
        }
      }
      return <String>{typeName};
    }

    if (expression is MethodInvocation) {
      final typeName = _callIdentifier(expression);
      if (typeName == 'CustomTransitionPage') {
        final child = _namedExpression(expression, 'child');
        if (child != null) {
          return _widgetClassesFromExpression(child);
        }
      }
      if (typeName != null && expression.target == null) {
        return <String>{typeName};
      }
    }

    if (expression is ConditionalExpression) {
      return <String>{
        ..._widgetClassesFromExpression(expression.thenExpression),
        ..._widgetClassesFromExpression(expression.elseExpression),
      };
    }

    if (expression is ParenthesizedExpression) {
      return _widgetClassesFromExpression(expression.expression);
    }

    return const <String>{};
  }

  Expression? _namedExpression(Expression node, String name) {
    for (final argument in _argumentsOf(node)) {
      if (argument is NamedExpression && argument.name.label.name == name) {
        return argument.expression;
      }
    }
    return null;
  }

  String? _namedStringLiteral(Expression node, String name) {
    final expression = _namedExpression(node, name);
    if (expression is SimpleStringLiteral) {
      return expression.value;
    }
    return null;
  }

  Iterable<Expression> _argumentsOf(Expression node) {
    if (node is InstanceCreationExpression) {
      return node.argumentList.arguments;
    }
    if (node is MethodInvocation) {
      return node.argumentList.arguments;
    }
    return const <Expression>[];
  }

  String? _callIdentifier(Expression node) {
    if (node is InstanceCreationExpression) {
      return node.constructorName.type.toSource();
    }
    if (node is MethodInvocation) {
      final target = node.target?.toSource();
      final methodName = node.methodName.name;
      if (target == null || target.isEmpty) {
        return methodName;
      }
      return '$target.$methodName';
    }
    return null;
  }

  String _joinRoute(String parentPath, String childPath) {
    if (childPath.isEmpty) {
      return parentPath;
    }
    if (childPath.startsWith('/')) {
      return childPath;
    }

    final normalizedParent = parentPath.endsWith('/')
        ? parentPath.substring(0, parentPath.length - 1)
        : parentPath;
    if (normalizedParent.isEmpty) {
      return '/$childPath';
    }
    return '$normalizedParent/$childPath';
  }
}

class _GoRouterFinder extends RecursiveAstVisitor<void> {
  Expression? firstGoRouter;

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    if (firstGoRouter == null &&
        node.constructorName.type.toSource() == 'GoRouter') {
      firstGoRouter = node;
    }
    super.visitInstanceCreationExpression(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (firstGoRouter == null &&
        node.target == null &&
        node.methodName.name == 'GoRouter') {
      firstGoRouter = node;
    }
    super.visitMethodInvocation(node);
  }
}

class _ReturnExpressionCollector extends RecursiveAstVisitor<void> {
  _ReturnExpressionCollector({required this.widgetClassesFromExpression});

  final Set<String> Function(Expression expression) widgetClassesFromExpression;
  final Set<String> widgets = <String>{};

  @override
  void visitReturnStatement(ReturnStatement node) {
    final expression = node.expression;
    if (expression != null) {
      widgets.addAll(widgetClassesFromExpression(expression));
    }
    super.visitReturnStatement(node);
  }
}
