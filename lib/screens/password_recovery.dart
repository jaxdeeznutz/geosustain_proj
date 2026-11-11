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
  bool _showPassword = false;
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
  Widget build(BuildContext context) {
    final settingPassword = _admin || _ticket != null;
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Recover your account')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              children: [
                Image.asset(
                  settingPassword
                      ? 'assets/images/dashboard/recovery_envelope.png'
                      : 'assets/images/dashboard/recovery_shield.png',
                  height: settingPassword ? 142 : 172,
                  fit: BoxFit.contain,
                ),
                const SizedBox(height: 14),
                Text(
                  settingPassword
                      ? 'Set a new password'
                      : 'Recover your account',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: darkGreen,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  _admin
                      ? 'Enter the private recovery handoff provided by your administrator, then choose a new password.'
                      : settingPassword
                      ? 'Enter the recovery code sent to your email, then choose a new password.'
                      : 'Request a recovery code at your account email. After verification, choose a new password. Your previous sessions will be signed out.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 28),
                if (!_admin) ...[
                  if (settingPassword)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: softGreen,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.mail_outline, color: green),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'A recovery code was requested for ${_email.text.trim()}.',
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (settingPassword) const SizedBox(height: 14),
                  TextField(
                    controller: _email,
                    enabled: !_busy && !settingPassword,
                    keyboardType: TextInputType.emailAddress,
                    decoration: InputDecoration(
                      labelText: 'Account email',
                      hintText: 'Enter your account email',
                      prefixIcon: const Icon(Icons.mail_outline),
                      errorText: _emailError,
                    ),
                    onChanged: (_) => setState(() => _emailError = null),
                  ),
                  const SizedBox(height: 16),
                  if (!settingPassword)
                    FilledButton.icon(
                      onPressed: _busy ? null : _request,
                      icon: const Icon(Icons.send_outlined),
                      label: Text(
                        _busy ? 'Sending code...' : 'Send recovery code',
                      ),
                    )
                  else ...[
                    Center(
                      child: TextButton.icon(
                        onPressed: _busy ? null : _request,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Request another code'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                    key: const ValueKey('recovery-code'),
                      controller: _code,
                      enabled: !_busy,
                      maxLength: 6,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: 'Email recovery code',
                        hintText: 'Enter 6-digit code',
                        prefixIcon: const Icon(Icons.verified_user_outlined),
                        errorText: _codeError,
                      ),
                    ),
                  ],
                ],
                if (_admin)
                  TextField(
                    controller: _token,
                    enabled: !_busy,
                    autocorrect: false,
                    decoration: InputDecoration(
                      labelText: 'Private recovery handoff',
                      prefixIcon: const Icon(Icons.key_outlined),
                      errorText: _tokenError,
                    ),
                  ),
                if (settingPassword) ...[
                  const SizedBox(height: 14),
                  TextField(
                    key: const ValueKey('recovery-password'),
                    controller: _password,
                    enabled: !_busy,
                    obscureText: !_showPassword,
                    decoration: InputDecoration(
                      labelText: 'New password',
                      hintText: 'Enter new password',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        onPressed: () =>
                            setState(() => _showPassword = !_showPassword),
                        icon: Icon(
                          _showPassword
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                      ),
                      errorText: _passwordError,
                      helperText:
                          'At least 8 characters, a special character, and no spaces.',
                    ),
                    onChanged: (_) => setState(() => _passwordError = null),
                  ),
                  PasswordStrengthIndicator(password: _password.text),
                  const SizedBox(height: 14),
                  TextField(
                    key: const ValueKey('recovery-confirm-password'),
                    controller: _confirm,
                    enabled: !_busy,
                    obscureText: !_showPassword,
                    decoration: InputDecoration(
                      labelText: 'Confirm new password',
                      hintText: 'Confirm new password',
                      prefixIcon: const Icon(Icons.lock_outline),
                      errorText: _confirmError,
                    ),
                    onSubmitted: (_) => _recover(),
                    onChanged: (_) => setState(() => _confirmError = null),
                  ),
                  const SizedBox(height: 18),
                  FilledButton.icon(
                    onPressed: _busy ? null : _recover,
                    icon: const Icon(Icons.check_circle_outline),
                    label: Text(
                      _busy ? 'Changing password...' : 'Set new password',
                    ),
                  ),
                ],
                if (_message != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Text(
                      _message!,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: colors.primary),
                    ),
                  ),
                const SizedBox(height: 12),
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
      ),
    );
  }
}
