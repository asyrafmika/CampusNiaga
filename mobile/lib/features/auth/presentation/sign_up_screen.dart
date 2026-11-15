import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_routes.dart';
import '../domain/auth_failure.dart';
import '../domain/auth_validators.dart';
import 'auth_form_controllers.dart';
import 'widgets/auth_layout.dart';
import 'widgets/auth_style.dart';
import 'widgets/password_field.dart';

class SignUpScreen extends ConsumerStatefulWidget {
  const SignUpScreen({super.key});

  static const emailKey = Key('sign-up-email');
  static const nameKey = Key('sign-up-name');
  static const passwordKey = Key('sign-up-password');
  static const submitKey = Key('sign-up-submit');

  @override
  ConsumerState<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends ConsumerState<SignUpScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _name = TextEditingController();
  final _password = TextEditingController();

  @override
  void dispose() {
    _email.dispose();
    _name.dispose();
    _password.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_form.currentState!.validate()) return;
    ref
        .read(signUpControllerProvider.notifier)
        .submit(name: _name.text, email: _email.text, password: _password.text);
  }

  void _toSignIn() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(AppRoutes.login);
    }
  }

  @override
  Widget build(BuildContext context) {
    final request = ref.watch(signUpControllerProvider);

    if (request case AsyncData(value: final String sentTo)) {
      return AuthLayout(
        title: 'Check your ',
        titleAccent: 'inbox.',
        subtitle: 'We sent a confirmation link to $sentTo.',
        children: [
          const Icon(
            Icons.mark_email_read_outlined,
            size: 72,
            color: AuthStyle.link,
          ),
          const SizedBox(height: 16),
          const Text(
            'Open the link to confirm your account. On this phone, it signs '
            'you in straight away; otherwise, come back and sign in. Check '
            'your Junk folder if it does not arrive.',
            style: TextStyle(color: AuthStyle.textMuted),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 28),
          SubmitButton(label: 'Back to sign in', onPressed: _toSignIn),
        ],
      );
    }

    return AuthLayout(
      title: 'Join the ',
      titleAccent: 'campus market.',
      subtitle:
          'Free for USM students. Sign up with your @student.usm.my email.',
      showBadge: true,
      showBack: true,
      footer: AuthSwitchLink(
        question: 'Already have an account?',
        action: 'Sign in',
        onPressed: _toSignIn,
      ),
      children: [
        Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const FieldLabel('Email Address'),
              TextFormField(
                key: SignUpScreen.emailKey,
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                textInputAction: TextInputAction.next,
                validator: AuthValidators.email,
                decoration: const InputDecoration(
                  hintText: 'you@student.usm.my',
                  prefixIcon: Icon(Icons.mail_outline),
                ),
              ),
              const SizedBox(height: 20),
              const FieldLabel('Your Name'),
              TextFormField(
                key: SignUpScreen.nameKey,
                controller: _name,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                validator: AuthValidators.name,
                decoration: const InputDecoration(
                  hintText: 'As buyers will see it',
                  prefixIcon: Icon(Icons.person_outline),
                ),
              ),
              const SizedBox(height: 20),
              const FieldLabel('Password'),
              PasswordField(
                key: SignUpScreen.passwordKey,
                controller: _password,
                hint: 'At least 8 characters',
                validator: AuthValidators.newPassword,
                onSubmitted: (_) => _submit(),
                showStrength: true,
              ),
              const SizedBox(height: 28),
              if (request case AsyncError(:final error))
                FormErrorText(
                  error is AuthFailure
                      ? error.message
                      : AuthFailure.unknown.message,
                ),
              SubmitButton(
                key: SignUpScreen.submitKey,
                label: 'Sign up',
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
