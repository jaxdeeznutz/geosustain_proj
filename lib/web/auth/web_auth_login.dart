part of '../../main.dart';

class WebAuthLoginShell extends StatelessWidget {
  final TextEditingController emailController;
  final TextEditingController passwordController;
  final bool loading;
  final String? emailError;
  final String? passwordError;
  final VoidCallback onLogin;
  final VoidCallback? onGoogle;
  const WebAuthLoginShell({
    super.key,
    required this.emailController,
    required this.passwordController,
    required this.loading,
    this.emailError,
    this.passwordError,
    required this.onLogin,
    this.onGoogle,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: WebPortalColors.surface,
      body: Row(
        children: [
          if (MediaQuery.sizeOf(context).width >= 1000)
            Expanded(
              flex: 9,
              child: SingleChildScrollView(
                child: Container(
                  padding: EdgeInsets.fromLTRB(64, 56, 64, 36),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [WebPortalColors.canvas, WebPortalColors.canvas],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.eco_rounded,
                            color: WebPortalColors.accent,
                            size: 42,
                          ),
                          SizedBox(width: 12),
                          Text(
                            'GeoSustain',
                            style: TextStyle(
                              fontSize: 34,
                              fontWeight: FontWeight.w900,
                              color: WebPortalColors.accent,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 78),
                      Text(
                        'Smart Decisions.\nSustainable Future.',
                        style: TextStyle(
                          fontSize: 42,
                          height: 1.15,
                          fontWeight: FontWeight.w900,
                          color: WebPortalColors.ink,
                        ),
                      ),
                      SizedBox(height: 22),
                      SizedBox(
                        width: 560,
                        child: Text(
                          'A web analyst dashboard for agricultural suitability, crop trends, environmental monitoring, and planning-ready reports.',
                          style: TextStyle(
                            fontSize: 17,
                            height: 1.55,
                            color: WebPortalColors.muted,
                          ),
                        ),
                      ),
                      SizedBox(height: 48),
                      Wrap(
                        spacing: 18,
                        runSpacing: 18,
                        children: [
                          _WebLoginFeature(
                            icon: Icons.map_rounded,
                            title: 'Geospatial Analysis',
                            text: 'Review field suitability and mapped areas.',
                          ),
                          _WebLoginFeature(
                            icon: Icons.query_stats_rounded,
                            title: 'Data Insights',
                            text:
                                'Analyze crop trends and suitability records.',
                          ),
                          _WebLoginFeature(
                            icon: Icons.cloud_rounded,
                            title: 'Weather Monitoring',
                            text: 'Track rainfall and climate factors.',
                          ),
                          _WebLoginFeature(
                            icon: Icons.picture_as_pdf_rounded,
                            title: 'Reports & Export',
                            text: 'Generate planning summaries and reports.',
                          ),
                        ],
                      ),
                      SizedBox(height: 32),
                      Text(
                        'Secure access for agricultural planning',
                        style: TextStyle(
                          color: WebPortalColors.muted,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          Expanded(
            flex: 11,
            child: SingleChildScrollView(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Container(
                  width: 560,
                  padding: EdgeInsets.all(48),
                  decoration: BoxDecoration(
                    color: WebPortalColors.surface,
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(color: Color(0xFFE1E8E2)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: .06),
                        blurRadius: 34,
                        offset: Offset(0, 18),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        width: 70,
                        height: 70,
                        decoration: BoxDecoration(
                          color: WebPortalColors.tint,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.eco_rounded,
                          color: WebPortalColors.accent,
                          size: 46,
                        ),
                      ),
                      SizedBox(height: 20),
                      Text(
                        'Welcome Back!',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Sign in to your GeoSustain analyst dashboard',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: WebPortalColors.muted),
                      ),
                      SizedBox(height: 34),
                      TextField(
                        controller: emailController,
                        autofillHints: [AutofillHints.username],
                        keyboardType: TextInputType.emailAddress,
                        decoration: InputDecoration(
                          errorText: emailError,
                          labelText: 'Email Address',
                          prefixIcon: Icon(Icons.mail_outline),
                        ),
                      ),
                      SizedBox(height: 14),
                      _WebPasswordField(
                        controller: passwordController,
                        errorText: passwordError,
                        onSubmitted: (_) {
                          if (!loading) onLogin();
                        },
                      ),
                      TextButton(
                        onPressed: loading
                            ? null
                            : () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => PasswordRecoveryPage(),
                                ),
                              ),
                        child: Text('Forgot password?'),
                      ),
                      SizedBox(height: 24),
                      FilledButton.icon(
                        onPressed: loading ? null : onLogin,
                        icon: Icon(Icons.arrow_forward_rounded),
                        label: Text(
                          loading ? 'Signing in...' : 'Sign In to Dashboard',
                        ),
                      ),
                      SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: loading ? null : onGoogle,
                        icon: Icon(Icons.account_circle_outlined),
                        label: Text('Continue with Google'),
                      ),
                      if (onGoogle == null)
                        Padding(
                          padding: EdgeInsets.only(top: 8),
                          child: Text(
                            'Google sign-in is currently unavailable. Use your email and password.',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      SizedBox(height: 18),
                      Text(
                        'Analyst access is assigned by your administrator. Farmers register and sign in through the GeoSustain mobile app.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: WebPortalColors.muted),
                      ),
                      SizedBox(height: 12),
                      SelectableText(
                        'Build ${WebBuildIdentity.id}',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WebPasswordField extends StatefulWidget {
  final TextEditingController controller;
  final String? errorText;
  final ValueChanged<String> onSubmitted;
  const _WebPasswordField({
    required this.controller,
    this.errorText,
    required this.onSubmitted,
  });
  @override
  State<_WebPasswordField> createState() => _WebPasswordFieldState();
}

class _WebPasswordFieldState extends State<_WebPasswordField> {
  bool hidden = true;
  @override
  Widget build(BuildContext context) => TextField(
    controller: widget.controller,
    obscureText: hidden,
    autofillHints: [AutofillHints.password],
    onSubmitted: widget.onSubmitted,
    decoration: InputDecoration(
      labelText: 'Password',
      errorText: widget.errorText,
      prefixIcon: Icon(Icons.lock_outline),
      suffixIcon: IconButton(
        tooltip: hidden ? 'Show password' : 'Hide password',
        onPressed: () => setState(() => hidden = !hidden),
        icon: Icon(
          hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined,
        ),
      ),
    ),
  );
}

class _WebLoginFeature extends StatelessWidget {
  final IconData icon;
  final String title;
  final String text;
  const _WebLoginFeature({
    required this.icon,
    required this.title,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 250,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: WebPortalColors.surface,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: WebPortalColors.accent),
          ),
          SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(fontWeight: FontWeight.w900)),
                SizedBox(height: 4),
                Text(
                  text,
                  style: TextStyle(color: WebPortalColors.muted, height: 1.3),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
