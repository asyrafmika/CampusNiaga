import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../domain/auth_failure.dart';
import '../domain/auth_validators.dart';
import 'auth_form_controllers.dart';
import 'widgets/auth_layout.dart';
import 'widgets/password_field.dart';

class SignUpScreen extends ConsumerStatefulWidget {
  const SignUpScreen({super.key});

  static const nameKey = Key('sign-up-name');
  static const emailKey = Key('sign-up-email');
  static const passwordKey = Key('sign-up-password');
  static const confirmKey = Key('sign-up-confirm');
  static const submitKey = Key('sign-up-submit');

  @override
  ConsumerState<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends ConsumerState<SignUpScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
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
        title: 'Check your inbox',
        subtitle: 'We sent a confirmation link to $sentTo.',
        children: [
          const Icon(
            Icons.mark_email_read_outlined,
            size: 72,
            color: AppColors.primary,
          ),
          const SizedBox(height: 16),
          Text(
            'Open the link to confirm your account. On this phone, it signs '
            'you in straight away; otherwise, come back and sign in. Check '
            'your Junk folder if it does not arrive.',
            style: Theme.of(context).textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 28),
          FilledButton(
            onPressed: _toSignIn,
            child: const Text('Back to sign in'),
          ),
        ],
      );
    }

    return AuthLayout(
      title: 'Create your account',
      subtitle:
          'Use your @student.usm.my email. We will send a link to confirm it.',
      showBack: true,
      children: [
        Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const FieldLabel('Full name'),
              TextFormField(
                key: SignUpScreen.nameKey,
                controller: _name,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                validator: AuthValidators.name,
                decoration: const InputDecoration(
                  hintText: 'As you want buyers to see it',
                  prefixIcon: Icon(Icons.person_outline),
                ),
              ),
              const SizedBox(height: 20),
              const FieldLabel('USM email'),
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
              const FieldLabel('Password'),
              PasswordField(
                key: SignUpScreen.passwordKey,
                controller: _password,
                hint: 'At least 8 characters',
                textInputAction: TextInputAction.next,
                validator: AuthValidators.newPassword,
              ),
              const SizedBox(height: 20),
              const FieldLabel('Confirm password'),
              PasswordField(
                key: SignUpScreen.confirmKey,
                controller: _confirm,
                hint: 'Type it again',
                validator: (value) =>
                    AuthValidators.confirmPassword(value, _password.text),
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 24),
              if (request case AsyncError(:final error))
                FormErrorText(
                  error is AuthFailure
                      ? error.message
                      : AuthFailure.unknown.message,
                ),
              SubmitButton(
                key: SignUpScreen.submitKey,
                label: 'Create account',
                busy: request.isLoading,
                onPressed: _submit,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        AuthSwitchLink(
          question: 'Already have an account?',
          action: 'Sign in',
          onPressed: _toSignIn,
        ),
      ],
    );
  }
}
