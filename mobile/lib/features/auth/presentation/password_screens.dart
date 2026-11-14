import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../domain/auth_failure.dart';
import '../domain/auth_validators.dart';
import 'auth_controller.dart';
import 'auth_form_controllers.dart';
import 'widgets/auth_layout.dart';
import 'widgets/password_field.dart';

String _failureMessage(Object error) =>
    error is AuthFailure ? error.message : AuthFailure.unknown.message;

/// Sends a password-reset link. The link opens the app on the
/// [ResetPasswordScreen].
class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_form.currentState!.validate()) return;
    ref.read(forgotPasswordControllerProvider.notifier).submit(_email.text);
  }

  @override
  Widget build(BuildContext context) {
    final request = ref.watch(forgotPasswordControllerProvider);

    if (request case AsyncData(value: final String sentTo)) {
      return AuthLayout(
        title: 'Check your inbox',
        subtitle: 'If $sentTo has an account, a reset link is on its way.',
        showBack: true,
        children: [
          const Icon(
            Icons.mark_email_read_outlined,
            size: 72,
            color: AppColors.primary,
          ),
          const SizedBox(height: 16),
          Text(
            'Open the link on this phone to choose a new password.',
            style: Theme.of(context).textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
        ],
      );
    }

    return AuthLayout(
      title: 'Reset your password',
      subtitle: 'Enter your email and we will send you a reset link.',
      showBack: true,
      children: [
        Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const FieldLabel('Email'),
              TextFormField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                validator: AuthValidators.email,
                onFieldSubmitted: (_) => _submit(),
                decoration: const InputDecoration(
                  hintText: 'you@student.usm.my',
                  prefixIcon: Icon(Icons.mail_outline),
                ),
              ),
              const SizedBox(height: 24),
              if (request case AsyncError(:final error))
                FormErrorText(_failureMessage(error)),
              SubmitButton(
                label: 'Send reset link',
                busy: request.isLoading,
                onPressed: _submit,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Shown after the user opens a password-reset link.
class ResetPasswordScreen extends ConsumerStatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  ConsumerState<ResetPasswordScreen> createState() =>
      _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends ConsumerState<ResetPasswordScreen> {
  final _form = GlobalKey<FormState>();
  final _password = TextEditingController();
  final _confirm = TextEditingController();

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_form.currentState!.validate()) return;
    ref.read(resetPasswordControllerProvider.notifier).submit(_password.text);
  }

  @override
  Widget build(BuildContext context) {
    final request = ref.watch(resetPasswordControllerProvider);

    return AuthLayout(
      title: 'Choose a new password',
      subtitle: 'You will stay signed in after saving it.',
      children: [
        Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const FieldLabel('New password'),
              PasswordField(
                controller: _password,
                hint: 'At least 8 characters',
                textInputAction: TextInputAction.next,
                validator: AuthValidators.newPassword,
              ),
              const SizedBox(height: 20),
              const FieldLabel('Confirm password'),
              PasswordField(
                controller: _confirm,
                hint: 'Type it again',
                validator: (value) =>
                    AuthValidators.confirmPassword(value, _password.text),
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 24),
              if (request case AsyncError(:final error))
                FormErrorText(_failureMessage(error)),
              SubmitButton(
                label: 'Save password',
                busy: request.isLoading,
                onPressed: _submit,
              ),
              TextButton(
                onPressed: ref.read(authControllerProvider.notifier).signOut,
                child: const Text('Cancel and sign out'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
