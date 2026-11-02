part of '../main.dart';

class GooglePasswordSetupPage extends StatefulWidget {
  final ApiService api;
  final Map<String, dynamic> user;
  final Future<void> Function() onCompleted, onSignOut;
  const GooglePasswordSetupPage({
    super.key,
    required this.api,
    required this.user,
    required this.onCompleted,
    required this.onSignOut,
  });
  @override
  State<GooglePasswordSetupPage> createState() =>
      _GooglePasswordSetupPageState();
}

class _GooglePasswordSetupPageState extends State<GooglePasswordSetupPage> {
  final form = GlobalKey<FormState>();
  final password = TextEditingController(),
      confirmation = TextEditingController();
  bool busy = false, obscure = true;
  String? error;
  @override
  void dispose() {
    password.dispose();
    confirmation.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (busy || !form.currentState!.validate()) {
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.api.completeGooglePasswordSetup(password.text);
      password.clear();
      confirmation.clear();
      if (mounted) {
        await widget.onCompleted();
      }
    } catch (failure) {
      if (mounted) {
        setState(() => error = friendlyErrorMessage(failure));
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  Future<void> signOut() async {
    if (busy) {
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.onSignOut();
    } catch (failure) {
      if (mounted) {
        setState(() => error = friendlyErrorMessage(failure));
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    child: Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('GeoSustain'),
        actions: [
          TextButton(
            onPressed: busy ? null : signOut,
            child: const Text('Sign out'),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 430),
              child: Form(
                key: form,
                child: AutofillGroup(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Icon(
                        Icons.lock_person_outlined,
                        size: 48,
                        color: green,
                      ),
                      const SizedBox(height: 18),
                      const Text(
                        'Create your GeoSustain password',
                        style: TextStyle(
                          fontSize: 25,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'Next time, sign in with Google or your email and this password.',
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '${widget.user['email'] ?? ''}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 22),
                      TextFormField(
                        key: const ValueKey('google-setup-password'),
                        controller: password,
                        enabled: !busy,
                        obscureText: obscure,
                        autofillHints: const [AutofillHints.newPassword],
                        textInputAction: TextInputAction.next,
                        enableSuggestions: false,
                        autocorrect: false,
                        decoration: InputDecoration(
                          labelText: 'New password',
                          errorMaxLines: 3,
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: IconButton(
                            tooltip: obscure
                                ? 'Show password'
                                : 'Hide password',
                            onPressed: busy
                                ? null
                                : () => setState(() => obscure = !obscure),
                            icon: Icon(
                              obscure
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                          ),
                        ),
                        validator: (value) =>
                            utf8.encode(value ?? '').length > 72
                            ? 'Password is too long.'
                            : validNewPassword(value ?? '')
                            ? null
                            : 'Use 8+ characters and a symbol, without spaces.',
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        key: const ValueKey('google-setup-confirmation'),
                        controller: confirmation,
                        enabled: !busy,
                        obscureText: obscure,
                        enableSuggestions: false,
                        autocorrect: false,
                        autofillHints: const [AutofillHints.newPassword],
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) => save(),
                        decoration: const InputDecoration(
                          labelText: 'Confirm password',
                          errorMaxLines: 2,
                          prefixIcon: Icon(Icons.lock_outline),
                        ),
                        validator: (value) =>
                            value == password.text && (value ?? '').isNotEmpty
                            ? null
                            : 'Passwords do not match.',
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'At least 8 characters and a symbol. No spaces.',
                        style: TextStyle(fontSize: 12),
                      ),
                      if (error != null)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          child: Semantics(
                            liveRegion: true,
                            child: Text(
                              error!,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                          ),
                        ),
                      const SizedBox(height: 20),
                      FilledButton.icon(
                        onPressed: busy ? null : save,
                        icon: busy
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.check),
                        label: Text(busy ? 'Saving…' : 'Save and continue'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
