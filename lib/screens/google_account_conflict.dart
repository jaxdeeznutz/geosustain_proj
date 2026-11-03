part of '../main.dart';

enum GoogleAccountConflictChoice { password, anotherAccount }

class GoogleAccountConflictDialog extends StatelessWidget {
  final String? email;
  const GoogleAccountConflictDialog({super.key, this.email});
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('This email already has an account'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (email != null) ...[Text(email!), const SizedBox(height: 12)],
          const Text(
            'Sign in with your GeoSustain password to keep your farms and history. You can link Google from your profile.',
          ),
          const SizedBox(height: 12),
          const Text(
            'To create a new account, choose a Google email that has not been registered in GeoSustain.',
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      TextButton(
        onPressed: () =>
            Navigator.pop(context, GoogleAccountConflictChoice.anotherAccount),
        child: const Text('Choose another Google account'),
      ),
      FilledButton(
        onPressed: () =>
            Navigator.pop(context, GoogleAccountConflictChoice.password),
        child: const Text('Use my password'),
      ),
    ],
  );
}
