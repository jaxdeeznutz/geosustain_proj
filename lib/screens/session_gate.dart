part of '../main.dart';

/// Validate saved sessions without discarding them during a network outage.
class SessionGate extends StatefulWidget {
  final ApiService? api;
  const SessionGate({super.key, this.api});
  @override
  State<SessionGate> createState() => _SessionGateState();
}

class _SessionGateState extends State<SessionGate> {
  late final ApiService api;
  bool checking = true;
  String? error;
  bool authenticated = false;
  @override
  void initState() {
    super.initState();
    api = widget.api ?? ApiService();
    restore();
  }

  @override
  void dispose() {
    if (widget.api == null) api.close();
    super.dispose();
  }

  Future<void> restore() async {
    setState(() {
      checking = true;
      error = null;
    });
    try {
      final token = await api.getToken();
      if (token != null && token.isNotEmpty) {
        await api.getMe();
        authenticated = true;
      }
    } on ApiException catch (e) {
      if (e.statusCode == 401 || e.statusCode == 403) {
        await api.logout();
        authenticated = false;
      } else {
        error = friendlyErrorMessage(e);
      }
    } catch (e) {
      error = friendlyErrorMessage(e);
    }
    if (mounted) setState(() => checking = false);
  }

  @override
  Widget build(BuildContext context) {
    if (checking) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (error != null) {
      return Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.cloud_off_outlined, size: 48, color: green),
                  const SizedBox(height: 16),
                  const Text(
                    'Unable to restore your session',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  Text(error!, textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: restore,
                    child: const Text('Try again'),
                  ),
                  TextButton(
                    onPressed: () async {
                      await api.logout();
                      if (mounted) {
                        setState(() {
                          error = null;
                          authenticated = false;
                        });
                      }
                    },
                    child: const Text('Back to login'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    return authenticated ? const ShellPage() : const LoginPage();
  }
}
