part of '../main.dart';

enum SettingsSection { notifications, appearance }

class SettingsPage extends StatefulWidget {
  final SettingsSection section;
  const SettingsPage({super.key, this.section = SettingsSection.appearance});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool darkMode = false;
  bool notifications = false;
  bool savingNotifications = false;
  String? notificationMessage;

  @override
  void initState() {
    super.initState();
    loadSettings();
  }

  Future<void> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final pushEnabled = await PushNotifications.enabled();
    if (!mounted) return;
    setState(() {
      darkMode = prefs.getBool('settings_dark_mode') ?? false;
      notifications = pushEnabled;
    });
  }

  Future<void> saveBool(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: GeoSafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            GeoSustainHeader(
              title: widget.section == SettingsSection.notifications
                  ? 'Notification settings'
                  : 'Appearance',
              back: () => Navigator.pop(context),
            ),
            Card(
              child: Column(
                children: [
                  if (widget.section == SettingsSection.appearance)
                    SwitchListTile(
                      value: darkMode,
                      onChanged: (v) {
                        setState(() => darkMode = v);
                        saveBool('settings_dark_mode', v);
                        appThemeMode.value = v
                            ? ThemeMode.dark
                            : ThemeMode.light;
                      },
                      title: const Text('Dark mode'),
                      subtitle: const Text(
                        'Apply a dark theme throughout the application',
                      ),
                    ),
                  if (widget.section == SettingsSection.notifications)
                    SwitchListTile(
                      value: notifications,
                      onChanged:
                          savingNotifications || !PushNotifications.configured
                          ? null
                          : (v) async {
                              setState(() {
                                savingNotifications = true;
                                notificationMessage = null;
                              });
                              try {
                                await PushNotifications.setEnabled(
                                  ApiService(),
                                  v,
                                );
                                if (mounted) setState(() => notifications = v);
                              } catch (error) {
                                if (mounted) {
                                  setState(
                                    () => notificationMessage =
                                        friendlyErrorMessage(error),
                                  );
                                }
                              } finally {
                                if (mounted) {
                                  setState(() => savingNotifications = false);
                                }
                              }
                            },
                      secondary: const Icon(
                        Icons.notifications_outlined,
                        color: green,
                      ),
                      title: const Text('Analysis and review push alerts'),
                      subtitle: Text(
                        notificationMessage ??
                            (PushNotifications.configured
                                ? 'Receive alerts when an analysis finishes or an analyst reviews your submission. Requires device/browser permission. Weather advisories remain in the app.'
                                : 'Push delivery requires Firebase project setup. It is currently unavailable; no background alerts will be sent.'),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  final String text;
  const SectionTitle(this.text, {super.key});
  @override
  Widget build(BuildContext context) => Text(
    text,
    style: TextStyle(
      color: Theme.of(context).colorScheme.onSurface,
      fontWeight: FontWeight.w900,
      fontSize: 12,
      letterSpacing: 0.2,
    ),
  );
}
