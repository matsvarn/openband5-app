import 'package:flutter/material.dart';

import 'theme.dart';

/// The shared ui2 text input. Used by wellness, nutrition, coach, food log
/// and the component gallery.
class OsTextField extends StatelessWidget {
  const OsTextField({
    super.key,
    required this.controller,
    required this.label,
    this.hint = '',
    this.lines = 1,
    this.keyboard,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final int lines;
  final TextInputType? keyboard;

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label.toUpperCase(), style: F.over.copyWith(color: p.ink3)),
        const SizedBox(height: S.x2),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: S.x3, vertical: S.x2),
          decoration: BoxDecoration(
            color: p.card,
            borderRadius: R.rMd,
            border: Border.all(color: p.line),
          ),
          child: Semantics(
            label: label,
            textField: true,
            child: TextField(
              controller: controller,
              maxLines: lines,
              minLines: 1,
              keyboardType: keyboard,
              style: F.body.copyWith(color: p.ink),
              cursorColor: p.on(C.domMind),
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: hint,
                hintStyle: F.body.copyWith(color: p.ink3),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
