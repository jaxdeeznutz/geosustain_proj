part of '../main.dart';

class PasswordRecoveryPage extends StatefulWidget {
  final ApiService? api;
  const PasswordRecoveryPage({super.key, this.api});
  @override
  State<PasswordRecoveryPage> createState() => _PasswordRecoveryPageState();
}

class _PasswordRecoveryPageState extends State<PasswordRecoveryPage> {
  late final api = widget.api ?? ApiService();
  final _email = TextEditingController(),
      _code = TextEditingController(),
      _confirm = TextEditingController();
  final _token = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _message;
  String? _tokenError, _passwordError;
  String? _emailError, _codeError, _confirmError, _ticket;
  bool _admin = false;
  DateTime? _nextRequest;
  @override
  void dispose() {
    _token.dispose();
    _password.dispose();
    _email.dispose();
    _code.dispose();
    _confirm.dispose();
    if (widget.api == null) api.close();
    super.dispose();
  }

  Future<void> _recover() async {
    if (_busy) return;
    setState(() {
      _tokenError = _admin && _token.text.trim().length < 32
          ? 'Enter the complete private recovery handoff from your administrator.'
          : null;
      _codeError = !_admin && !RegExp(r'^[0-9]{6}$').hasMatch(_code.text)
          ? 'Enter the six-digit email code.'
          : null;
      _confirmError = _confirm.text != _password.text
          ? 'Passwords do not match.'
          : null;
      _passwordError = !validNewPassword(_password.text)
          ? 'Use at least 8 characters, a special character and no spaces.'
          : null;
    });
    if (_tokenError != null ||
        _passwordError != null ||
        _codeError != null ||
        _confirmError != null) {
      return;
    }
    if (!_admin && _ticket == null) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      if (_admin) {
        await api.recoverPassword(_token.text.trim(), _password.text);
      } else {
        await api.finishPasswordReset(_ticket!, _code.text, _password.text);
      }
      if (!mounted) return;
      _password.clear();
      _token.clear();
      _confirm.clear();
      _code.clear();
      setState(() {
        _ticket = null;
        _message =
            'Password changed. Return to sign in with your new password.';
      });
    } catch (error) {
      if (mounted) setState(() => _message = friendlyErrorMessage(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _request() async {
    if (_busy) return;
    setState(
      () => _emailError =
          RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(_email.text.trim())
          ? null
          : 'Enter a valid email address.',
    );
    if (_emailError != null) return;
    if (_nextRequest != null && DateTime.now().isBefore(_nextRequest!)) {
      setState(
        () => _message = 'Wait one minute before requesting another code.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final response = await api.startPasswordReset(_email.text);
      if (!mounted) return;
      setState(() {
        _ticket = '${response['verification_ticket']}';
        _code.clear();
        _codeError = null;
        _message = '${response['message']}';
        _nextRequest = DateTime.now().add(const Duration(seconds: 60));
      });
    } catch (error) {
      if (mounted) setState(() => _message = friendlyErrorMessage(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Recover your account')),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              _admin
                  ? 'Use the private recovery handoff your administrator provided after verifying your identity. It is valid for 15 minutes.'
                  : 'Request a recovery code at your account email. After verification, choose a new password. Your previous sessions will be signed out.',
            ),
            const SizedBox(height: 20),
            if (!_admin) ...[
              TextField(
                controller: _email,
                enabled: !_busy && _ticket == null,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  labelText: 'Account email',
                  errorText: _emailError,
                ),
                onChanged: (_) => setState(() => _emailError = null),
              ),
              TextButton(
                onPressed: _busy ? null : _request,
                child: Text(
                  _ticket == null
                      ? 'Send recovery code'
                      : 'Request another code',
                ),
              ),
              if (_ticket != null)
                TextField(
                  controller: _code,
                  enabled: !_busy,
                  maxLength: 6,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Email recovery code',
                    errorText: _codeError,
                  ),
                ),
            ],
            if (_admin)
              TextField(
                controller: _token,
                enabled: !_busy,
                autocorrect: false,
                decoration: InputDecoration(
                  labelText: 'Private recovery handoff',
                  errorText: _tokenError,
                ),
              ),
            if (_admin || _ticket != null) ...[
              const SizedBox(height: 16),
              TextField(
                controller: _password,
                enabled: !_busy,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: 'New password',
                  errorText: _passwordError,
                  helperText:
                      'At least 8 characters with a special character; no spaces.',
                ),
                onSubmitted: (_) => _recover(),
                onChanged: (_) => setState(() => _passwordError = null),
              ),
              PasswordStrengthIndicator(password: _password.text),
              TextField(
                controller: _confirm,
                enabled: !_busy,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: 'Confirm new password',
                  errorText: _confirmError,
                ),
                onChanged: (_) => setState(() => _confirmError = null),
              ),
            ],
            if (_message != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(_message!),
              ),
            const SizedBox(height: 16),
            if (_admin || _ticket != null)
              FilledButton(
                onPressed: _busy ? null : _recover,
                child: Text(
                  _busy ? 'Changing password...' : 'Set new password',
                ),
              ),
            TextButton(
              onPressed: _busy
                  ? null
                  : () => setState(() {
                      _admin = !_admin;
                      _ticket = null;
                      _message = null;
                      _code.clear();
                      _token.clear();
                    }),
              child: Text(
                _admin
                    ? 'Recover by email instead'
                    : 'Use an administrator recovery handoff',
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
