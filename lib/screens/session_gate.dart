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
  AnalysisState? offlineState;
  bool offlineChosen = false;

  Future<void> enterOffline() async {
    try {
      final token = await api.getToken();
      final local = await OfflineFarmStore.read();
      final user = analysisMapValue(local['identity']);
      if (token == null || user['id'] == null || user['role'] != 'farmer') {
        throw StateError(
          'Sign in online as a farmer once on this device to enable saved farms offline.',
        );
      }
      if (!mounted) return;
      final state = AnalysisState();
      state.currentUser = user;
      state.userLoaded = true;
      state.offlineWorkspace = true;
      state.farms.addAll([
        ...OfflineFarmStore.rows(local['pending']),
        ...OfflineFarmStore.rows(local['farms']),
      ]);
      setState(() {
        offlineChosen = true;
        offlineState = state;
        authenticated = true;
        checking = false;
        error = null;
      });
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Offline farms are unavailable. Sign in online once on this device, or retry the connection.',
            ),
          ),
        );
      }
    }
  }

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
    String? token;
    try {
      token = await api.getToken();
      if (token != null && token.isNotEmpty) {
        await api.getMe();
        authenticated = true;
      }
    } on ApiException catch (e) {
      if (e.statusCode == 401 || e.statusCode == 403) {
        if (!mounted || await api.getToken() != token) return;
        await api.logout();
        authenticated = false;
        if (mounted && offlineChosen) {
          setState(() {
            offlineChosen = false;
            offlineState = null;
            checking = false;
          });
        }
      } else {
        error = friendlyErrorMessage(e);
      }
    } catch (e) {
      error = friendlyErrorMessage(e);
    }
    if (mounted && !offlineChosen) setState(() => checking = false);
  }

  @override
  Widget build(BuildContext context) {
    if (checking) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              const Text(
                'Connecting to GeoSustain. The server may need about a minute to wake up.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: enterOffline,
                child: const Text('Open saved farms offline'),
              ),
            ],
          ),
        ),
      );
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
                    onPressed: enterOffline,
                    child: const Text('Open saved farms offline'),
                  ),
                  TextButton(
                    onPressed: () async {
                      try {
                        await api.logout();
                      } catch (failure) {
                        if (mounted) {
                          setState(() => error = friendlyErrorMessage(failure));
                        }
                        return;
                      }
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
    return authenticated
        ? ShellPage(analysisState: offlineState)
        : const LoginPage();
  }
}
