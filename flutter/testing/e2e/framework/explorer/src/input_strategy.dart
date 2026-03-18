import 'package:flutter/material.dart';

class InputStrategy {
  const InputStrategy();

  String generateText({required TextInputType? keyboardType, String? label}) {
    final normalizedLabel = (label ?? '').toLowerCase();

    if (keyboardType == TextInputType.emailAddress ||
        normalizedLabel.contains('email')) {
      return 'e2e_${DateTime.now().millisecondsSinceEpoch}@test.com';
    }
    if (keyboardType == TextInputType.number) {
      return '42';
    }
    if (keyboardType == TextInputType.phone) {
      return '+4915112345678';
    }
    if (keyboardType == TextInputType.url) {
      return 'https://example.com';
    }
    if (normalizedLabel.contains('password')) {
      return 'TestPa4w0rd!';
    }
    if (normalizedLabel.contains('code')) {
      return 'ABC123';
    }
    if (normalizedLabel.contains('address')) {
      return 'Teststrasse 1';
    }
    if (normalizedLabel.contains('name')) {
      return 'E2E Test ${DateTime.now().millisecondsSinceEpoch}';
    }

    return 'E2E Test ${DateTime.now().millisecondsSinceEpoch}';
  }

  /// Returns a reasonable index to select from a dropdown with [itemCount] items.
  int generateDropdownIndex({required int itemCount}) => itemCount > 1 ? 1 : 0;

  /// Returns suggested toggle state for a checkbox or switch.
  bool generateToggleValue({required bool currentValue}) => !currentValue;

  /// Returns a plausible DateTime for date pickers.
  DateTime generateDate() => DateTime.now().add(const Duration(days: 3));
}
