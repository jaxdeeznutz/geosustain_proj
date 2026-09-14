part of geosustain_mobile;

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool lowBandwidth = true;
  bool darkMode = false;
  bool notifications = true;

  @override
  void initState() {
    super.initState();
    loadSettings();
  }

  Future<void> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      lowBandwidth = prefs.getBool('settings_low_bandwidth') ?? true;
      darkMode = prefs.getBool('settings_dark_mode') ?? false;
      notifications = prefs.getBool('settings_notifications') ?? true;
    });
  }

  Future<void> saveBool(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
          child: ListView(padding: const EdgeInsets.all(16), children: [
        MobileHeader(title: 'Settings', back: () => Navigator.pop(context)),
        Card(
            child: Column(children: [
          SwitchListTile(
              value: lowBandwidth,
              onChanged: (v) {
                setState(() => lowBandwidth = v);
                saveBool('settings_low_bandwidth', v);
              },
              title: const Text('Low-bandwidth mode'),
              subtitle: const Text('Optimized mobile access for field use')),
          SwitchListTile(
              value: darkMode,
              onChanged: (v) {
                setState(() => darkMode = v);
                saveBool('settings_dark_mode', v);
              },
              title: const Text('Dark mode'),
              subtitle: const Text('Saved setting for future theme support')),
          SwitchListTile(
              value: notifications,
              onChanged: (v) {
                setState(() => notifications = v);
                saveBool('settings_notifications', v);
              },
              secondary: const Icon(Icons.notifications_outlined, color: green),
              title: const Text('Notifications'),
              subtitle: const Text('Analysis completed and weather alerts')),
        ])),
      ])),
    );
  }
}

class SectionTitle extends StatelessWidget {
  final String text;
  const SectionTitle(this.text, {super.key});
  @override
  Widget build(BuildContext context) => Text(text,
      style: const TextStyle(
          color: darkGreen,
          fontWeight: FontWeight.w900,
          fontSize: 12,
          letterSpacing: 0.2));
}
