part of '../main.dart';

class EmailVerificationPage extends StatefulWidget {
  final String email, ticket;
  final ApiService? api;
  const EmailVerificationPage({
    super.key,
    required this.email,
    required this.ticket,
    this.api,
  });
  @override
  State<EmailVerificationPage> createState() => _EmailVerificationPageState();
}

class _EmailVerificationPageState extends State<EmailVerificationPage> {
  late final api = widget.api ?? ApiService();
  final code = TextEditingController();
  bool busy = false;
  String? error;
  DateTime resendAt = DateTime.now().add(const Duration(seconds: 60));

  Future<void> submit({bool resend = false}) async {
    if (busy) return;
    if (resend && DateTime.now().isBefore(resendAt)) {
      setState(() => error = 'Wait one minute before requesting another code.');
      return;
    }
    if (!resend && !RegExp(r'^[0-9]{6}$').hasMatch(code.text)) {
      setState(() => error = 'Enter the six-digit code from your email.');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await api.emailVerification(
        widget.ticket,
        code: resend ? null : code.text,
      );
      if (!mounted) return;
      if (resend) {
        resendAt = DateTime.now().add(const Duration(seconds: 60));
        showAuthFeedback(
          context,
          'A new code was sent. Check your email.',
          success: true,
        );
      } else {
        showAuthFeedback(
          context,
          kIsWeb
              ? 'Farmer account verified. Sign in through the GeoSustain mobile app.'
              : 'Email verified. Sign in with your password.',
          success: true,
        );
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const LoginPage()),
        );
      }
    } catch (e) {
      if (mounted) setState(() => error = friendlyErrorMessage(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    code.dispose();
    if (widget.api == null) api.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FarmerAuthScaffold(
    onBack: () => Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const RegisterPage()),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Verify your email',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 12),
        Text(
          'Enter the code sent to ${widget.email}. It expires in ten minutes. Your account will be created after verification.',
        ),
        const SizedBox(height: 20),
        TextField(
          controller: code,
          enabled: !busy,
          keyboardType: TextInputType.number,
          autofillHints: const [AutofillHints.oneTimeCode],
          maxLength: 6,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(
            labelText: 'Email verification code',
            errorText: error,
            errorMaxLines: 4,
          ),
          onSubmitted: (_) => submit(),
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: busy ? null : submit,
          child: Text(busy ? 'Please wait…' : 'Verify email'),
        ),
        TextButton(
          onPressed: busy ? null : () => submit(resend: true),
          child: const Text('Resend code'),
        ),
        const Text(
          'Wait one minute before requesting another code. Check your spam folder too.',
        ),
      ],
    ),
  );
}
