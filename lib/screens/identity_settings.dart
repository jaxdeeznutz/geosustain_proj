part of '../main.dart';

class IdentityProfileSection extends StatefulWidget {
  final AnalysisState state;
  const IdentityProfileSection({super.key, required this.state});
  @override
  State<IdentityProfileSection> createState() => _IdentityProfileSectionState();
}

class _IdentityProfileSectionState extends State<IdentityProfileSection> {
  late final phone = TextEditingController(
    text: '${widget.state.currentUser?['phone_number'] ?? ''}',
  );
  final code = TextEditingController(), password = TextEditingController();
  PhoneProofChallenge? challenge;
  String? ticket, message, phoneError, codeError;
  bool busy = false;
  DateTime? resendAt;
  String get owner => '${widget.state.currentUser?['id']}';

  @override
  void dispose() {
    phone.dispose();
    code.dispose();
    password.dispose();
    unawaited(challenge?.close().catchError((_) {}) ?? Future<void>.value());
    super.dispose();
  }

  Future<void> action(Future<void> Function(String) work) async {
    if (busy) return;
    final expectedOwner = owner;
    setState(() {
      busy = true;
      message = null;
    });
    try {
      await work(expectedOwner);
    } catch (error) {
      if (mounted) {
        setState(
          () => message = error is ApiException
              ? error.message
              : FirebaseIdentity.errorMessage(error),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void update(Map<String, dynamic> user, String expectedOwner) {
    if (owner != expectedOwner || '${user['id']}' != expectedOwner) {
      throw const ApiException(
        409,
        'Account changed. Open your profile again.',
      );
    }
    widget.state.updateCurrentProfile(user);
  }

  bool validPhone({bool allowEmpty = false}) {
    final value = phone.text.trim();
    setState(
      () => phoneError =
          (allowEmpty && value.isEmpty) ||
              RegExp(r'^\+[1-9][0-9]{7,14}$').hasMatch(value)
          ? null
          : 'Use international format, for example +639171234567.',
    );
    return phoneError == null;
  }

  Future<void> savePhone() async {
    if (!validPhone(allowEmpty: true)) return;
    await action((expectedOwner) async {
      final user = await widget.state.api.updateProfile(
        username: '${widget.state.currentUser?['username'] ?? 'User'}',
        phoneNumber: phone.text.trim(),
      );
      update(user, expectedOwner);
      if (mounted) {
        setState(() {
          ticket = null;
          message = 'Phone number saved. A changed number needs verification.';
        });
      }
    });
  }

  Future<void> sendCode() async {
    if (!validPhone()) return;
    if (resendAt != null && DateTime.now().isBefore(resendAt!)) {
      setState(
        () => message = 'Wait one minute before requesting another SMS code.',
      );
      return;
    }
    await action((expectedOwner) async {
      final response = await widget.state.api.startPhoneVerification(
        phone.text.trim(),
      );
      update(await widget.state.api.getMe(), expectedOwner);
      final proof = await FirebaseIdentity.startPhone(phone.text.trim());
      if (!mounted || owner != expectedOwner) {
        await proof.close();
        return;
      }
      setState(() {
        challenge = proof;
        ticket = '${response['ticket']}';
        code.clear();
        codeError = null;
        resendAt = DateTime.now().add(const Duration(seconds: 60));
        message = proof.automaticToken != null
            ? 'Code received automatically. Tap Verify phone number.'
            : 'Enter the code from your SMS message.';
      });
    });
  }

  Future<void> verifyPhone() async {
    if (challenge == null || ticket == null) return;
    if (challenge!.automaticToken == null &&
        !RegExp(r'^[0-9]{6}$').hasMatch(code.text)) {
      setState(() => codeError = 'Enter the six-digit SMS code.');
      return;
    }
    await action((expectedOwner) async {
      final token = await challenge!.confirm(code.text);
      if (owner != expectedOwner) {
        throw const ApiException(
          409,
          'Account changed. Start verification again.',
        );
      }
      update(
        await widget.state.api.finishPhoneVerification(ticket!, token),
        expectedOwner,
      );
      await challenge!.close();
      if (mounted) {
        setState(() {
          challenge = null;
          ticket = null;
          code.clear();
          message = 'Phone number verified.';
        });
      }
    });
  }

  Future<void> linkGoogle() async {
    if (password.text.isEmpty) {
      setState(
        () => message =
            'Enter your current account password before linking Google.',
      );
      return;
    }
    await action((expectedOwner) async {
      final proof = await FirebaseIdentity.googleProof();
      if (owner != expectedOwner) {
        throw const ApiException(
          409,
          'Account changed. Open your profile again.',
        );
      }
      update(
        await widget.state.api.linkGoogle(proof, password.text),
        expectedOwner,
      );
      password.clear();
      if (mounted) {
        setState(
          () => message = 'Google sign-in linked to your existing account.',
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.state.currentUser ?? {};
    final verified =
        user['phone_verified'] == true &&
        phone.text.trim() == user['phone_number'];
    final linked = user['auth_provider'] == 'google';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(height: 28),
        Text(
          'Account verification',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Text(
          user['email_verified'] == true
              ? 'Email verified'
              : 'Email not yet verified',
        ),
        const SizedBox(height: 12),
        TextField(
          controller: phone,
          enabled: !busy,
          keyboardType: TextInputType.phone,
          onChanged: (_) => setState(() {
            ticket = null;
            phoneError = null;
            codeError = null;
          }),
          decoration: InputDecoration(
            labelText: 'Phone number',
            hintText: '+639171234567',
            errorText: phoneError,
            helperText: verified ? 'Verified number' : 'Not verified',
            prefixIcon: Icon(
              verified ? Icons.verified_outlined : Icons.phone_outlined,
            ),
          ),
        ),
        Wrap(
          spacing: 8,
          children: [
            TextButton(
              onPressed: busy ? null : savePhone,
              child: const Text('Save phone number'),
            ),
            OutlinedButton(
              onPressed: busy || !FirebaseIdentity.configured ? null : sendCode,
              child: const Text('Send SMS code'),
            ),
          ],
        ),
        if (!FirebaseIdentity.configured)
          const Text(
            'SMS verification is temporarily unavailable. You can still save your number.',
          ),
        if (ticket != null) ...[
          TextField(
            controller: code,
            enabled: !busy,
            keyboardType: TextInputType.number,
            maxLength: 6,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              labelText: 'SMS verification code',
              errorText: codeError,
            ),
            onChanged: (_) => setState(() => codeError = null),
          ),
          FilledButton(
            onPressed: busy ? null : verifyPhone,
            child: const Text('Verify phone number'),
          ),
        ],
        const SizedBox(height: 12),
        if (linked)
          const Text('Google sign-in is linked')
        else ...[
          TextField(
            controller: password,
            enabled: !busy,
            obscureText: true,
            enableSuggestions: false,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'Current password to link Google',
            ),
          ),
          TextButton.icon(
            onPressed: busy || !FirebaseIdentity.googleConfigured
                ? null
                : linkGoogle,
            icon: const Icon(Icons.link),
            label: const Text('Link Google to this account'),
          ),
        ],
        if (message != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(message!, semanticsLabel: message),
          ),
        if (busy) const LinearProgressIndicator(),
      ],
    );
  }
}
