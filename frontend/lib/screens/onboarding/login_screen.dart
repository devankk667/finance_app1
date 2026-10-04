import 'package:flutter/material.dart';
import 'package:frontend/data/finance_store.dart';
import 'package:frontend/screens/app_shell.dart';
import 'package:provider/provider.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _phoneController = TextEditingController();
  final _codeController = TextEditingController();
  bool _codeSent = false;

  Future<void> _sendCode() async {
    final phone = _phoneController.text.trim();
    if (!RegExp(r'^\+[1-9]\d{7,14}$').hasMatch(phone)) return;
    try {
      await context.read<FinanceStore>().requestPhoneCode(phone);
      if (mounted) setState(() => _codeSent = true);
    } catch (_) {
      // The store exposes a safe, user-facing request error.
    }
  }

  Future<void> _verifyCode() async {
    final code = _codeController.text.trim();
    if (!RegExp(r'^\d{4,10}$').hasMatch(code)) return;
    try {
      final store = context.read<FinanceStore>();
      await store.verifyPhoneCode(_phoneController.text.trim(), code);
      if (!mounted || !store.isSignedIn) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(builder: (_) => const MainShell()),
      );
    } catch (_) {
      // Keep the user on the verification screen so they can retry.
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<FinanceStore>();
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(
                    Icons.account_balance,
                    size: 64,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Nokai Finance',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Sign in with a one-time verification code',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 32),
                  TextField(
                    key: const ValueKey('phone-field'),
                    controller: _phoneController,
                    readOnly: _codeSent || store.isLoading,
                    decoration: const InputDecoration(
                      labelText: 'Phone number',
                      hintText: '+14155550123',
                      prefixIcon: Icon(Icons.phone_outlined),
                      helperText: 'Include country code in E.164 format',
                    ),
                    keyboardType: TextInputType.phone,
                    textInputAction: _codeSent
                        ? TextInputAction.next
                        : TextInputAction.done,
                    onSubmitted: (_) => _codeSent ? null : _sendCode(),
                  ),
                  if (_codeSent) ...[
                    const SizedBox(height: 16),
                    TextField(
                      key: const ValueKey('otp-field'),
                      controller: _codeController,
                      decoration: const InputDecoration(
                        labelText: 'Verification code',
                        prefixIcon: Icon(Icons.password_outlined),
                      ),
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _verifyCode(),
                    ),
                  ],
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: store.isLoading
                        ? null
                        : _codeSent
                            ? _verifyCode
                            : _sendCode,
                    child: store.isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(_codeSent ? 'Verify and sign in' : 'Send code'),
                  ),
                  if (_codeSent)
                    TextButton(
                      onPressed: store.isLoading
                          ? null
                          : () {
                              setState(() {
                                _codeSent = false;
                                _codeController.clear();
                              });
                            },
                      child: const Text('Change phone number'),
                    ),
                  if (store.errorMessage case final message?) ...[
                    const SizedBox(height: 12),
                    Card(
                      color: Theme.of(context).colorScheme.errorContainer,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(message),
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        'Depending on backend mode, the code is printed in the development server '
                        'console or sent by SMS through your verification provider.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _codeController.dispose();
    super.dispose();
  }
}
