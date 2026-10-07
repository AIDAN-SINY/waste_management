import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../services/functions_client.dart';

/// "Forgot password?" — reset with a 6-digit code received by SMS.
///
/// Step 1: phone number → `passwordResetStart` (the answer never reveals
/// whether the number has an account). Step 2: code + new password →
/// `passwordResetConfirm`. Sessions opened with the old password are then
/// signed out by the server.
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key, this.initialPhone = '', this.functions});

  final String initialPhone;

  /// Injected in tests (mocked functions).
  final FunctionsClient? functions;

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  static const Color _bg = Color(0xFF073A1B);
  static const Color _gold = Color(0xFFF5B800);
  static const Color _cream = Color(0xFFF5F1E8);
  static const Color _muted = Color(0xFFAEC0B7);

  final _phone = TextEditingController();
  final _code = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _codeSent = false;
  bool _busy = false;
  bool _obscure = true;
  String? _error;
  String? _info;

  FunctionsClient get _functions => widget.functions ?? FunctionsClient();

  @override
  void initState() {
    super.initState();
    _phone.text = widget.initialPhone;
  }

  @override
  void dispose() {
    _phone.dispose();
    _code.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    if (_phone.text.trim().isEmpty) {
      setState(() => _error = 'Enter your phone number.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final data = await _functions.postPublic('passwordResetStart', {
        'phone': _phone.text.trim(),
      });
      setState(() {
        _codeSent = true;
        _info = data['message'] as String? ??
            'If this number has an account, a code was sent by SMS.';
      });
    } on FunctionsException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reset() async {
    final code = _code.text.trim();
    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      setState(() => _error = 'Please enter the full 6-digit code.');
      return;
    }
    if (_password.text.length < 6) {
      setState(() => _error = 'Password must be at least 6 characters.');
      return;
    }
    if (_password.text != _confirm.text) {
      setState(() => _error = 'Passwords do not match.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _functions.postPublic('passwordResetConfirm', {
        'phone': _phone.text.trim(),
        'code': code,
        'newPassword': _password.text,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Password changed. Log in with your new password.'),
        ),
      );
      Navigator.of(context).pop();
    } on FunctionsException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        foregroundColor: _cream,
        elevation: 0,
        title: Text(
          'Reset password',
          style: GoogleFonts.sora(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    _codeSent
                        ? 'Enter the 6-digit code received by SMS and choose '
                            'a new password.'
                        : 'Enter the phone number of your account. We will '
                            'send you a code by SMS.',
                    style: const TextStyle(color: _muted, height: 1.5),
                  ),
                  const SizedBox(height: 20),
                  _field(
                    _phone,
                    'Phone number',
                    key: const Key('reset_phone'),
                    enabled: !_codeSent,
                    keyboard: TextInputType.phone,
                  ),
                  if (_codeSent) ...[
                    const SizedBox(height: 12),
                    _field(
                      _code,
                      'SMS code',
                      key: const Key('reset_code'),
                      keyboard: TextInputType.number,
                      digitsOnly: true,
                    ),
                    const SizedBox(height: 12),
                    _field(
                      _password,
                      'New password (min. 6 characters)',
                      key: const Key('reset_password'),
                      obscure: true,
                    ),
                    const SizedBox(height: 12),
                    _field(
                      _confirm,
                      'Confirm new password',
                      key: const Key('reset_confirm'),
                      obscure: true,
                    ),
                  ],
                  if (_info != null && _codeSent) ...[
                    const SizedBox(height: 12),
                    Text(_info!, style: const TextStyle(color: _muted)),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      style: const TextStyle(color: Color(0xFFFF8A80)),
                    ),
                  ],
                  const SizedBox(height: 22),
                  ElevatedButton(
                    onPressed: _busy ? null : (_codeSent ? _reset : _sendCode),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _gold,
                      foregroundColor: _bg,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(
                            _codeSent ? 'Change password' : 'Send code',
                            style: GoogleFonts.sora(fontWeight: FontWeight.w600),
                          ),
                  ),
                  if (_codeSent)
                    TextButton(
                      onPressed: _busy ? null : _sendCode,
                      child: const Text(
                        'Send a new code',
                        style: TextStyle(color: _gold),
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

  Widget _field(
    TextEditingController controller,
    String label, {
    Key? key,
    bool enabled = true,
    bool obscure = false,
    bool digitsOnly = false,
    TextInputType? keyboard,
  }) {
    return TextField(
      key: key,
      controller: controller,
      enabled: enabled,
      obscureText: obscure && _obscure,
      keyboardType: keyboard,
      maxLength: digitsOnly ? 6 : null,
      inputFormatters:
          digitsOnly ? [FilteringTextInputFormatter.digitsOnly] : null,
      style: const TextStyle(color: _cream),
      decoration: InputDecoration(
        labelText: label,
        counterText: '',
        labelStyle: const TextStyle(color: _muted),
        filled: true,
        fillColor: _cream.withValues(alpha: 0.07),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        suffixIcon: obscure
            ? IconButton(
                icon: Icon(
                  _obscure ? Icons.visibility_off : Icons.visibility,
                  color: _muted,
                ),
                onPressed: () => setState(() => _obscure = !_obscure),
              )
            : null,
      ),
    );
  }
}
