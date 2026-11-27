import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/constants/typography.dart';
import '../../core/l10n/digits.dart';

/// Banglalink's codes have 6 digits.
const codeLength = 6;

/// A 6-digit code from Banglalink, typed with English or Bangla digits.
class LampCodeField extends StatelessWidget {
  const LampCodeField({super.key, required this.controller, required this.label, this.onSubmitted});

  final TextEditingController controller;
  final String label;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    keyboardType: TextInputType.number,
    maxLength: codeLength,
    autofillHints: const [AutofillHints.oneTimeCode],
    inputFormatters: [FilteringTextInputFormatter.allow(RegExp('[0-9০-৯]'))],
    style: LaMPType.monoBody,
    decoration: InputDecoration(labelText: label, counterText: ''),
    onSubmitted: onSubmitted,
  );
}

/// The code in English digits, or null if it isn't 6 digits.
String? readCode(String typed) {
  final s = enDigits(typed.trim());
  return RegExp(r'^\d{6}$').hasMatch(s) ? s : null;
}
