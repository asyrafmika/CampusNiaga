// Temporary screen proving the Supabase connection. Replaced by the real
// sign-in screens in the next Phase 1 commit; not part of the app's design.
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/config/supabase_config.dart';

class ConnectionCheckScreen extends StatefulWidget {
  const ConnectionCheckScreen({super.key});

  @override
  State<ConnectionCheckScreen> createState() => _ConnectionCheckScreenState();
}

class _ConnectionCheckScreenState extends State<ConnectionCheckScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final List<String> _log = [];
  bool _busy = false;

  SupabaseClient get _client => Supabase.instance.client;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _add(String line) => setState(() => _log.insert(0, line));

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } on AuthException catch (e) {
      _add('Auth error: ${e.message}');
    } on PostgrestException catch (e) {
      _add('Database error (${e.details ?? e.code}): ${e.message}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signUp() => _run(() async {
    final response = await _client.auth.signUp(
      email: _email.text.trim(),
      password: _password.text,
    );
    _add(
      response.session == null
          ? 'Auth: account created. Open the confirmation email, then sign in.'
          : 'Auth: account created and signed in.',
    );
  });

  Future<void> _signInAndCheck() => _run(() async {
    final response = await _client.auth.signInWithPassword(
      email: _email.text.trim(),
      password: _password.text,
    );
    _add('Auth: signed in as ${response.user?.email}');

    final access = await _client.rpc<dynamic>('get_my_access');
    _add('Database: get_my_access -> $access');

    final profile = await _client
        .from('profiles')
        .select('name, account_status')
        .eq('id', response.user!.id)
        .maybeSingle();
    _add('Database: own profile -> $profile');
  });

  Future<void> _signOut() => _run(() async {
    await _client.auth.signOut();
    _add('Auth: signed out');
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Supabase connection check')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Project: ${SupabaseConfig.url}'),
          const SizedBox(height: 16),
          TextField(
            controller: _email,
            decoration: const InputDecoration(
              labelText: 'Email',
              hintText: 'you@student.usm.my',
            ),
            keyboardType: TextInputType.emailAddress,
          ),
          TextField(
            controller: _password,
            decoration: const InputDecoration(labelText: 'Password'),
            obscureText: true,
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _busy ? null : _signInAndCheck,
            child: const Text('Sign in and check'),
          ),
          OutlinedButton(
            onPressed: _busy ? null : _signUp,
            child: const Text('Create account'),
          ),
          TextButton(
            onPressed: _busy ? null : _signOut,
            child: const Text('Sign out'),
          ),
          const Divider(),
          for (final line in _log)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(line),
            ),
        ],
      ),
    );
  }
}
