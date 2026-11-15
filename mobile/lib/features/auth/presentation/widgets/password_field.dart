import 'package:flutter/material.dart';

import '../../domain/password_strength.dart';

/// A password input with a show/hide toggle and, when [showStrength] is on,
/// a strength meter inside the field (as in the sign-up reference).
class PasswordField extends StatefulWidget {
  const PasswordField({
    super.key,
    required this.controller,
    required this.validator,
    this.hint = 'Your password',
    this.textInputAction = TextInputAction.done,
    this.onSubmitted,
    this.showStrength = false,
  });

  final TextEditingController controller;
  final FormFieldValidator<String> validator;
  final String hint;
  final TextInputAction textInputAction;
  final ValueChanged<String>? onSubmitted;
  final bool showStrength;

  @override
  State<PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<PasswordField> {
  bool _hidden = true;

  @override
  Widget build(BuildContext context) {
    final toggle = IconButton(
      onPressed: () => setState(() => _hidden = !_hidden),
      icon: Icon(
        _hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined,
      ),
      tooltip: _hidden ? 'Show password' : 'Hide password',
    );

    return TextFormField(
      controller: widget.controller,
      obscureText: _hidden,
      autocorrect: false,
      enableSuggestions: false,
      textInputAction: widget.textInputAction,
      onFieldSubmitted: widget.onSubmitted,
      validator: widget.validator,
      decoration: InputDecoration(
        hintText: widget.hint,
        prefixIcon: const Icon(Icons.key_outlined),
        suffixIcon: widget.showStrength
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ValueListenableBuilder<TextEditingValue>(
                    valueListenable: widget.controller,
                    builder: (context, value, _) => value.text.isEmpty
                        ? const SizedBox.shrink()
                        : StrengthMeter(passwordStrength(value.text)),
                  ),
                  toggle,
                ],
              )
            : toggle,
      ),
    );
  }
}

/// Three short bars and a label: weak (1 red), fair (2 amber), strong (3 green).
class StrengthMeter extends StatelessWidget {
  const StrengthMeter(this.strength, {super.key});

  final PasswordStrength strength;

  @override
  Widget build(BuildContext context) {
    final colour = switch (strength) {
      PasswordStrength.weak => const Color(0xFFFF6B6B),
      PasswordStrength.fair => const Color(0xFFFFB547),
      PasswordStrength.strong => const Color(0xFF4ADE80),
    };
    final filled = strength.index + 1;
    return Semantics(
      label: 'Password strength: ${strength.label}',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < 3; i++)
            Container(
              width: 12,
              height: 3,
              margin: const EdgeInsets.only(right: 3),
              decoration: BoxDecoration(
                color: i < filled ? colour : const Color(0x33FFFFFF),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          const SizedBox(width: 4),
          Text(
            strength.label,
            style: TextStyle(
              color: colour,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
