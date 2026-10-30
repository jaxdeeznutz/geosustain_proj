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

  Widget _brand({bool compact = false}) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(Icons.eco_rounded, color: green, size: compact ? 40 : 46),
      const SizedBox(width: 10),
      Flexible(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'GeoSustain',
              style: TextStyle(
                fontSize: compact ? 25 : 29,
                fontWeight: FontWeight.w900,
                color: WebPortalColors.ink,
              ),
            ),
            Text(
              'Agricultural Insights Platform',
              style: TextStyle(fontSize: 12, color: WebPortalColors.muted),
            ),
          ],
        ),
      ),
    ],
  );

  Widget _introduction() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _brand(),
      const SizedBox(height: 60),
      Text(
        'Smart Decisions.',
        style: TextStyle(
          fontSize: 44,
          height: 1.1,
          fontWeight: FontWeight.w900,
          color: WebPortalColors.ink,
        ),
      ),
      const Text(
        'Sustainable Future.',
        style: TextStyle(
          fontSize: 44,
          height: 1.15,
          fontWeight: FontWeight.w900,
          color: green,
        ),
      ),
      const SizedBox(height: 20),
      Text(
        'A web analyst dashboard for agricultural suitability, crop trends, environmental monitoring, and planning-ready reports.',
        style: TextStyle(
          fontSize: 17,
          height: 1.5,
          color: WebPortalColors.muted,
        ),
      ),
      const SizedBox(height: 28),
      LayoutBuilder(
        builder: (context, constraints) => Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final item in const [
              (
                Icons.map_rounded,
                'Geospatial Analysis',
                'Review field evidence and mapped areas.',
              ),
              (
                Icons.query_stats_rounded,
                'Data Insights',
                'Explore crop trends and saved records.',
              ),
              (
                Icons.picture_as_pdf_rounded,
                'Reports & Export',
                'Export analysis and review reports.',
              ),
              (
                Icons.cloud_rounded,
                'Weather Monitoring',
                'Review rainfall and climate context.',
              ),
            ])
              SizedBox(
                width: (constraints.maxWidth - 12) / 2,
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: WebPortalColors.surface.withValues(alpha: .9),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(item.$1, color: green, size: 30),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.$2,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              item.$3,
                              style: TextStyle(
                                color: WebPortalColors.muted,
                                fontSize: 12,
                                height: 1.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
      const SizedBox(height: 60),
      Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: const Color(0xFF075C43).withValues(alpha: .9),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Wrap(
          spacing: 26,
          runSpacing: 14,
          children: [
            for (final item in const [
              (Icons.spa_outlined, 'Better Planning'),
              (Icons.public, 'Greener Communities'),
              (Icons.bar_chart, 'Healthier Future'),
            ])
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(item.$1, color: Colors.white, size: 24),
                  const SizedBox(width: 8),
                  Text(
                    item.$2,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    ],
  );

  Widget _form(BuildContext context, bool wide) => Container(
    width: 490,
    padding: EdgeInsets.all(wide ? 34 : 24),
    decoration: BoxDecoration(
      color: WebPortalColors.surface.withValues(alpha: .97),
      borderRadius: BorderRadius.circular(30),
      border: Border.all(color: Colors.white.withValues(alpha: .7)),
      boxShadow: [
        BoxShadow(
          color: const Color(0xFF174F3D).withValues(alpha: .13),
          blurRadius: 38,
          offset: const Offset(0, 16),
        ),
      ],
    ),
    child: AutofillGroup(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(child: _brand(compact: true)),
          const SizedBox(height: 30),
          Text(
            'Welcome Back!',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w900,
              color: WebPortalColors.ink,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Sign in to your GeoSustain analyst dashboard',
            textAlign: TextAlign.center,
            style: TextStyle(color: WebPortalColors.muted, fontSize: 13),
          ),
          const SizedBox(height: 28),
          TextField(
            controller: emailController,
            autofillHints: const [AutofillHints.username],
            keyboardType: TextInputType.emailAddress,
            decoration: InputDecoration(
              errorText: emailError,
              labelText: 'Email Address',
              prefixIcon: const Icon(Icons.mail_outline),
            ),
          ),
          const SizedBox(height: 14),
          _WebPasswordField(
            controller: passwordController,
            errorText: passwordError,
            onSubmitted: (_) {
              if (!loading) {
                onLogin();
              }
            },
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: loading
                  ? null
                  : () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => PasswordRecoveryPage()),
                    ),
              child: const Text('Forgot password?'),
            ),
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: loading ? null : onLogin,
            icon: const Icon(Icons.arrow_forward_rounded),
            style: FilledButton.styleFrom(
              backgroundColor: green,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(48),
            ),
            label: Text(loading ? 'Signing in...' : 'Sign In to Dashboard'),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 14),
            child: Row(
              children: [
                Expanded(child: Divider()),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 14),
                  child: Text('OR', style: TextStyle(fontSize: 11)),
                ),
                Expanded(child: Divider()),
              ],
            ),
          ),
          OutlinedButton.icon(
            onPressed: loading ? null : onGoogle,
            icon: const Icon(Icons.account_circle_outlined),
            label: const Text('Continue with Google'),
          ),
          if (onGoogle == null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Google sign-in is currently unavailable. Use your email and password.',
                textAlign: TextAlign.center,
                style: TextStyle(color: WebPortalColors.muted, fontSize: 12),
              ),
            ),
          const SizedBox(height: 22),
          Text(
            'Analyst access is assigned by your administrator. Farmers register and sign in through the GeoSustain mobile app.',
            textAlign: TextAlign.center,
            style: TextStyle(color: WebPortalColors.muted, fontSize: 12),
          ),
          const SizedBox(height: 12),
          SelectableText(
            'Build ${WebBuildIdentity.id}',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: WebPortalColors.canvas,
    body: Stack(
      children: [
        Positioned.fill(
          child: Image.asset(
            'assets/images/web/eco_valley_panorama.png',
            fit: BoxFit.cover,
            excludeFromSemantics: true,
          ),
        ),
        Positioned.fill(
          child: ColoredBox(
            color: WebPortalColors.dark
                ? const Color(0xFF08271C).withValues(alpha: .8)
                : const Color(0xFFEBFAFA).withValues(alpha: .16),
          ),
        ),
        LayoutBuilder(
          builder: (context, box) {
            final wide =
                box.maxWidth >= 1050 &&
                MediaQuery.textScalerOf(context).scale(14) < 21;
            return SingleChildScrollView(
              padding: EdgeInsets.symmetric(
                horizontal: wide ? 56 : 20,
                vertical: wide ? 44 : 24,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: math.max(0.0, box.maxHeight - (wide ? 88 : 48)),
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1320),
                    child: wide
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Expanded(flex: 6, child: _introduction()),
                              const SizedBox(width: 64),
                              Expanded(flex: 5, child: _form(context, true)),
                            ],
                          )
                        : _form(context, false),
                  ),
                ),
              ),
            );
          },
        ),
      ],
    ),
  );
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
