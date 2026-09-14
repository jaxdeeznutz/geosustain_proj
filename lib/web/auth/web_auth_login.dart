part of geosustain_mobile;

class WebAuthLoginShell extends StatelessWidget {
  final TextEditingController emailController;
  final TextEditingController passwordController;
  final bool loading;
  final VoidCallback onLogin;
  final VoidCallback onGoogle;
  final VoidCallback onCreate;
  const WebAuthLoginShell({
    super.key,
    required this.emailController,
    required this.passwordController,
    required this.loading,
    required this.onLogin,
    required this.onGoogle,
    required this.onCreate,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Row(
        children: [
          Expanded(
            flex: 9,
            child: Container(
              height: double.infinity,
              padding: const EdgeInsets.fromLTRB(64, 56, 64, 36),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFFF2FBF6), Color(0xFFE7F6EE)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(children: [
                    Icon(Icons.eco_rounded, color: green, size: 42),
                    SizedBox(width: 12),
                    Text('GeoSustain', style: TextStyle(fontSize: 34, fontWeight: FontWeight.w900, color: green)),
                  ]),
                  const SizedBox(height: 78),
                  const Text('Smart Decisions.\nSustainable Future.', style: TextStyle(fontSize: 42, height: 1.15, fontWeight: FontWeight.w900, color: Color(0xFF102018))),
                  const SizedBox(height: 22),
                  const SizedBox(
                    width: 560,
                    child: Text(
                      'A web analyst dashboard for agricultural suitability, crop trends, environmental monitoring, and planning-ready reports.',
                      style: TextStyle(fontSize: 17, height: 1.55, color: Colors.black54),
                    ),
                  ),
                  const SizedBox(height: 48),
                  Wrap(spacing: 18, runSpacing: 18, children: const [
                    _WebLoginFeature(icon: Icons.map_rounded, title: 'Geospatial Analysis', text: 'Review field suitability and mapped areas.'),
                    _WebLoginFeature(icon: Icons.query_stats_rounded, title: 'Data Insights', text: 'Analyze crop trends and suitability records.'),
                    _WebLoginFeature(icon: Icons.cloud_rounded, title: 'Weather Monitoring', text: 'Track rainfall, alerts, and climate factors.'),
                    _WebLoginFeature(icon: Icons.picture_as_pdf_rounded, title: 'Reports & Export', text: 'Generate planning summaries and reports.'),
                  ]),
                  const Spacer(),
                  const Text('Secure analyst access • Firebase Authentication • PostgreSQL-backed system', style: TextStyle(color: Colors.black45, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          ),
          Expanded(
            flex: 11,
            child: Center(
              child: Container(
                width: 560,
                padding: const EdgeInsets.all(48),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(color: const Color(0xFFE1E8E2)),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(.06), blurRadius: 34, offset: const Offset(0, 18))],
                ),
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Container(width: 70, height: 70, decoration: const BoxDecoration(color: softGreen, shape: BoxShape.circle), child: const Icon(Icons.eco_rounded, color: green, size: 46)),
                  const SizedBox(height: 20),
                  const Text('Welcome Back!', textAlign: TextAlign.center, style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 8),
                  const Text('Sign in to your GeoSustain analyst dashboard', textAlign: TextAlign.center, style: TextStyle(color: Colors.black54)),
                  const SizedBox(height: 34),
                  TextField(controller: emailController, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Email Address', prefixIcon: Icon(Icons.mail_outline))),
                  const SizedBox(height: 14),
                  TextField(controller: passwordController, obscureText: true, decoration: const InputDecoration(labelText: 'Password', prefixIcon: Icon(Icons.lock_outline))),
                  const SizedBox(height: 24),
                  FilledButton.icon(onPressed: loading ? null : onLogin, icon: const Icon(Icons.arrow_forward_rounded), label: Text(loading ? 'Signing in...' : 'Sign In to Dashboard')),
                  const SizedBox(height: 18),
                  Row(children: const [Expanded(child: Divider()), Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text('or continue with', style: TextStyle(color: Colors.black45))), Expanded(child: Divider())]),
                  const SizedBox(height: 18),
                  OutlinedButton.icon(
                    onPressed: loading ? null : onGoogle,
                    icon: const Icon(Icons.g_mobiledata_rounded, size: 28),
                    label: const Text('Sign in with Google'),
                    style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52), foregroundColor: const Color(0xFF1F2937), side: const BorderSide(color: Color(0xFFE1E8E2)), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                  ),
                  const SizedBox(height: 18),
                  TextButton(onPressed: loading ? null : onCreate, child: const Text('Create Analyst Account')),
                ]),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WebLoginFeature extends StatelessWidget {
  final IconData icon;
  final String title;
  final String text;
  const _WebLoginFeature({required this.icon, required this.title, required this.text});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 250,
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(width: 52, height: 52, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)), child: Icon(icon, color: green)),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          Text(text, style: const TextStyle(color: Colors.black54, height: 1.3)),
        ])),
      ]),
    );
  }
}
