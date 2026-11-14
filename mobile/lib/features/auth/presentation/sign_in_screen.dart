import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_routes.dart';
import '../domain/auth_failure.dart';
import '../domain/auth_validators.dart';
import 'auth_form_controllers.dart';
import 'widgets/auth_layout.dart';
import 'widgets/password_field.dart';

/// Signing in sends the user on by itself: the router follows their access.
class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});

  static const emailKey = Key('sign-in-email');
  static const passwordKey = Key('sign-in-password');
  static const submitKey = Key('sign-in-submit');

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_form.currentState!.validate()) return;
    ref
        .read(signInControllerProvider.notifier)
        .submit(email: _email.text, password: _password.text);
  }

  @override
  Widget build(BuildContext context) {
    final request = ref.watch(signInControllerProvider);

    return AuthLayout(
      title: 'Welcome back',
      subtitle: 'Sign in with your USM student email to continue.',
      children: [
        Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const FieldLabel('Email'),
              TextFormField(
                key: SignInScreen.emailKey,
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
                key: SignInScreen.passwordKey,
                controller: _password,
                validator: AuthValidators.password,
                onSubmitted: (_) => _submit(),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => context.push(AppRoutes.forgotPassword),
                  child: const Text('Forgot password?'),
                ),
              ),
              const SizedBox(height: 8),
              if (request case AsyncError(:final error))
                FormErrorText(
                  error is AuthFailure
                      ? error.message
                      : AuthFailure.unknown.message,
                ),
              SubmitButton(
                key: SignInScreen.submitKey,
                label: 'Sign in',
                busy: request.isLoading,
                onPressed: _submit,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        AuthSwitchLink(
          question: 'New to CampusNiaga?',
          action: 'Create an account',
          onPressed: () => context.push(AppRoutes.signUp),
        ),
      ],
    );
  }
}
