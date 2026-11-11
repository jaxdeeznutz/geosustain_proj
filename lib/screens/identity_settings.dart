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
  final password = TextEditingController();
  String? message, phoneError;
  bool busy = false;
  String get owner => '${widget.state.currentUser?['id']}';

  @override
  void dispose() {
    phone.dispose();
    password.dispose();
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
          message = 'Phone number saved.';
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
    final linked = user['auth_provider'] == 'google';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(height: 28),
        Text('Account details', style: Theme.of(context).textTheme.titleMedium),
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
          onChanged: (_) => setState(() => phoneError = null),
          decoration: InputDecoration(
            labelText: 'Phone number',
            hintText: '+639171234567',
            errorText: phoneError,
            prefixIcon: const Icon(Icons.phone_outlined),
          ),
        ),
        Wrap(
          spacing: 8,
          children: [
            TextButton(
              onPressed: busy ? null : savePhone,
              child: const Text('Save phone number'),
            ),
          ],
        ),
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
