part of geosustain_mobile;

class ProfilePage extends StatelessWidget {
  final AnalysisState state;
  final VoidCallback logout;
  const ProfilePage({super.key, required this.state, required this.logout});

  @override
  Widget build(BuildContext context) {
    final analysisCount = state.profileCounts['analysis_count'] ?? state.historyRecords.length;
    final savedCount = state.profileCounts['saved_count'] ?? state.savedAnalyses.length;
    final reportCount = state.profileCounts['report_count'] ?? state.generatedReports.length;
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          const MobileHeader(title: 'Profile'),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF08733F), Color(0xFF055C34)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(28),
              boxShadow: [BoxShadow(color: green.withOpacity(0.18), blurRadius: 22, offset: const Offset(0, 12))],
            ),
            child: Column(
              children: [
                Container(
                  width: 86,
                  height: 86,
                  decoration: BoxDecoration(color: Colors.white.withOpacity(0.18), shape: BoxShape.circle, border: Border.all(color: Colors.white.withOpacity(0.45), width: 2)),
                  child: state.profilePhotoBytes != null
                      ? ClipOval(child: Image.memory(state.profilePhotoBytes!, width: 86, height: 86, fit: BoxFit.cover))
                      : const Icon(Icons.person_rounded, size: 52, color: Colors.white),
                ),
                const SizedBox(height: 12),
                Text(state.userName(), style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w900)),
                const SizedBox(height: 4),
                Text(state.userRole(), style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w700)),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(color: Colors.white.withOpacity(0.16), borderRadius: BorderRadius.circular(999)),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [const Icon(Icons.location_on_outlined, color: Colors.white, size: 16), const SizedBox(width: 5), Flexible(child: Text(state.userLocation(), style: const TextStyle(color: Colors.white, fontSize: 12), overflow: TextOverflow.ellipsis))],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(child: ProfileStatCard(value: '$analysisCount', label: 'Analysis')),
              const SizedBox(width: 10),
              Expanded(child: ProfileStatCard(value: '$savedCount', label: 'Saved')),
              const SizedBox(width: 10),
              Expanded(child: ProfileStatCard(value: '$reportCount', label: 'Reports')),
            ],
          ),
          const SizedBox(height: 14),
          ProfileSection(
            title: state.isAnalystRole ? 'Planning Library' : 'Analysis Library',
            children: [
              ProfileActionTile(
                icon: Icons.bookmark_border_rounded,
                title: 'Saved Analysis',
                subtitle: 'View saved land and crop analysis records',
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SavedAnalysesPage(state: state))),
              ),
              ProfileActionTile(
                icon: Icons.description_outlined,
                title: 'Reports',
                subtitle: 'Open generated land suitability reports',
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ReportsListPage(state: state))),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ProfileSection(
            title: 'Account',
            children: [
              ProfileActionTile(
                icon: Icons.settings_outlined,
                title: 'Account Settings',
                subtitle: 'Edit profile, photo, notifications, and account actions',
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => EditProfilePage(state: state, logout: logout))),
              ),
              ProfileActionTile(icon: Icons.notifications_none_rounded, title: 'Notifications', subtitle: 'Weather, analysis, and alert updates', onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => NotificationsPage(state: state)))),
              ProfileActionTile(icon: Icons.my_location_outlined, title: 'Location Permission', subtitle: 'GPS and field location access'),
            ],
          ),
          const SizedBox(height: 16),
          FilledButton.icon(onPressed: logout, icon: const Icon(Icons.logout), label: const Text('Sign Out')),
        ],
      ),
    );
  }
}

class EditProfilePage extends StatefulWidget {
  final AnalysisState state;
  final VoidCallback? logout;
  const EditProfilePage({super.key, required this.state, this.logout});
  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  late final TextEditingController nameController;
  late final TextEditingController emailController;
  late final TextEditingController locationController;
  late String role;
  Uint8List? pickedPhotoBytes;
  String? pickedPhotoBase64;
  bool saving = false;
  bool notificationsEnabled = true;
  bool weatherAlerts = true;

  @override
  void initState() {
    super.initState();
    nameController = TextEditingController(text: widget.state.currentUser?['username']?.toString() ?? 'User');
    emailController = TextEditingController(text: widget.state.currentUser?['email']?.toString() ?? '');
    locationController = TextEditingController(text: widget.state.userLocation());
    final currentRole = widget.state.currentUser?['role']?.toString() ?? 'farmer';
    role = currentRole == 'analyst' ? 'Analyst / Planner' : 'Farmer';
  }

  @override
  void dispose() {
    nameController.dispose();
    emailController.dispose();
    locationController.dispose();
    super.dispose();
  }

  String get apiRole => role == 'Analyst / Planner' ? 'analyst' : 'farmer';

  Future<void> pickPhoto() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(source: ImageSource.gallery, imageQuality: 70, maxWidth: 512, maxHeight: 512);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    setState(() {
      pickedPhotoBytes = bytes;
      pickedPhotoBase64 = base64Encode(bytes);
    });
  }

  Future<void> saveProfile() async {
    setState(() => saving = true);
    try {
      final updated = await widget.state.api.updateProfile(
        username: nameController.text.trim().isEmpty ? 'User' : nameController.text.trim(),
        role: apiRole,
        location: locationController.text.trim(),
        profilePhotoBase64: pickedPhotoBase64,
      );
      widget.state.currentUser = updated;
      if (pickedPhotoBytes != null) widget.state.profilePhotoBytes = pickedPhotoBytes;
      widget.state.notifyListeners();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profile updated.')));
    } catch (e) {
      widget.state.currentUser = {
        ...?widget.state.currentUser,
        'username': nameController.text.trim().isEmpty ? 'User' : nameController.text.trim(),
        'role': apiRole,
        'location': locationController.text.trim(),
        if (pickedPhotoBase64 != null) 'profile_photo': pickedPhotoBase64,
      };
      if (pickedPhotoBytes != null) widget.state.profilePhotoBytes = pickedPhotoBytes;
      widget.state.notifyListeners();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Profile update failed: ${e.toString().replaceFirst('Exception: ', '')}')));
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> confirmDanger({required bool delete}) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(delete ? 'Delete account?' : 'Deactivate account?'),
        content: Text(delete
            ? 'This permanently removes your account and linked records from the online database.'
            : 'This disables your account until an admin reactivates it.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: delete ? Colors.red : Colors.orange),
            onPressed: () => Navigator.pop(context, true),
            child: Text(delete ? 'Delete' : 'Deactivate'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      if (delete) {
        await widget.state.api.deleteAccount();
      } else {
        await widget.state.api.deactivateAccount();
      }
      widget.logout?.call();
      if (mounted) Navigator.popUntil(context, (route) => route.isFirst);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final avatarBytes = pickedPhotoBytes ?? widget.state.profilePhotoBytes;
    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            MobileHeader(title: 'Account Settings', back: () => Navigator.pop(context)),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(children: [
                  Stack(children: [
                    CircleAvatar(
                      radius: 54,
                      backgroundColor: softGreen,
                      backgroundImage: avatarBytes != null ? MemoryImage(avatarBytes) : null,
                      child: avatarBytes == null ? const Icon(Icons.person_rounded, color: green, size: 58) : null,
                    ),
                    Positioned(right: 0, bottom: 0, child: CircleAvatar(backgroundColor: green, child: IconButton(onPressed: pickPhoto, icon: const Icon(Icons.camera_alt, color: Colors.white, size: 18))))
                  ]),
                  const SizedBox(height: 10),
                  TextButton.icon(onPressed: pickPhoto, icon: const Icon(Icons.photo_library_outlined), label: const Text('Upload profile photo')),
                  const SizedBox(height: 12),
                  TextField(controller: nameController, decoration: const InputDecoration(labelText: 'Full Name', prefixIcon: Icon(Icons.person_outline))),
                  const SizedBox(height: 12),
                  TextField(controller: emailController, readOnly: true, decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.mail_outline))),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: role,
                    decoration: const InputDecoration(labelText: 'Role', prefixIcon: Icon(Icons.badge_outlined)),
                    items: const [
                      DropdownMenuItem(value: 'Farmer', child: Text('Farmer')),
                      DropdownMenuItem(value: 'Analyst / Planner', child: Text('Analyst / Planner')),
                    ],
                    onChanged: (v) => setState(() => role = v ?? 'Farmer'),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: softGreen, borderRadius: BorderRadius.circular(14)),
                    child: Text(
                      role == 'Analyst / Planner'
                          ? 'Analyst / Planner: view reports, saved analyses, and planning insights for independent environmental monitoring.'
                          : 'Farmer: analyze land, get crop recommendations, save reports, and receive weather alerts.',
                      style: const TextStyle(color: darkGreen, fontWeight: FontWeight.w700, height: 1.3),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(controller: locationController, decoration: const InputDecoration(labelText: 'Location', prefixIcon: Icon(Icons.location_on_outlined))),
                  const SizedBox(height: 18),
                  FilledButton.icon(
                    onPressed: saving ? null : saveProfile,
                    icon: saving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.save_outlined),
                    label: Text(saving ? 'Saving...' : 'Save Changes'),
                  ),
                ]),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Column(children: [
                SwitchListTile(
                  value: notificationsEnabled,
                  onChanged: (v) => setState(() => notificationsEnabled = v),
                  secondary: const Icon(Icons.notifications_outlined, color: green),
                  title: const Text('Notifications'),
                  subtitle: const Text('Show analysis and system alerts'),
                ),
                SwitchListTile(
                  value: weatherAlerts,
                  onChanged: (v) => setState(() => weatherAlerts = v),
                  secondary: const Icon(Icons.water_drop_outlined, color: green),
                  title: const Text('Weather alerts'),
                  subtitle: const Text('Rainfall, humidity, wind, and field warnings'),
                ),
              ]),
            ),
            const SizedBox(height: 12),
            Card(
              child: Column(children: [
                ListTile(
                  leading: const Icon(Icons.pause_circle_outline, color: Colors.orange),
                  title: const Text('Deactivate Account'),
                  subtitle: const Text('Temporarily disable this account'),
                  onTap: () => confirmDanger(delete: false),
                ),
                const Divider(height: 0),
                ListTile(
                  leading: const Icon(Icons.delete_outline, color: Colors.red),
                  title: const Text('Delete Account'),
                  subtitle: const Text('Permanently remove account from database'),
                  onTap: () => confirmDanger(delete: true),
                ),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}

class SavedAnalysesPage extends StatelessWidget {
  final AnalysisState state;
  const SavedAnalysesPage({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    final rows = state.savedAnalyses;
    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: Column(children: [
          MobileHeader(title: 'Saved Analysis', back: () => Navigator.pop(context)),
          Expanded(
            child: rows.isEmpty
                ? const Center(child: Text('No saved analysis yet.'))
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
                    itemCount: rows.length,
                    itemBuilder: (context, i) {
                      final r = state.normalizeRecord(rows[i]);
                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: ListTile(
                          leading: const CircleAvatar(backgroundColor: softGreen, child: Icon(Icons.bookmark, color: green)),
                          title: Text('${r['title'] ?? 'Unknown location'}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900)),
                          subtitle: Text('${r['subtitle'] ?? 'Land suitability analysis'}\n${r['date'] ?? '--'}'),
                          isThreeLine: true,
                          trailing: const Icon(Icons.chevron_right_rounded),
                          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SavedAnalysisDetailPage(record: r))),
                        ),
                      );
                    },
                  ),
          ),
        ]),
      ),
    );
  }
}

class ReportsListPage extends StatelessWidget {
  final AnalysisState state;
  const ReportsListPage({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    final rows = state.generatedReports;
    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: Column(children: [
          MobileHeader(title: 'Reports', back: () => Navigator.pop(context)),
          Expanded(
            child: rows.isEmpty
                ? const Center(child: Text('No generated reports yet.'))
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
                    itemCount: rows.length,
                    itemBuilder: (context, i) {
                      final r = state.normalizeRecord(rows[i]);
                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: ListTile(
                          leading: const CircleAvatar(backgroundColor: softGreen, child: Icon(Icons.description, color: green)),
                          title: Text('Report: ${r['title'] ?? 'Unknown location'}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900)),
                          subtitle: Text('${r['subtitle'] ?? 'Land suitability report'}\n${r['date'] ?? '--'}'),
                          isThreeLine: true,
                          trailing: const Icon(Icons.chevron_right_rounded),
                          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SavedAnalysisDetailPage(record: r, title: 'Saved Report', state: state))),
                        ),
                      );
                    },
                  ),
          ),
        ]),
      ),
    );
  }
}

class SavedAnalysisDetailPage extends StatelessWidget {
  final Map<String, dynamic> record;
  final String title;
  final AnalysisState? state;
  const SavedAnalysisDetailPage({super.key, required this.record, this.title = 'Saved Analysis', this.state});

  @override
  Widget build(BuildContext context) {
    final lat = record['center_lat'] ?? record['lat'];
    final lon = record['center_lon'] ?? record['lon'];
    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            MobileHeader(title: title, back: () => Navigator.pop(context), trailing: IconButton(onPressed: () => generateAnalysisPdf(record, state: state), icon: const Icon(Icons.download_outlined))),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${record['title'] ?? 'Unknown location'}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: green)),
                  const SizedBox(height: 8),
                  Text('${record['subtitle'] ?? 'Land suitability analysis'}'),
                  const SizedBox(height: 6),
                  Text('Date: ${record['date'] ?? '--'}', style: const TextStyle(color: Colors.black54)),
                  const Divider(height: 28),
                  DetailLine(label: 'Latitude', value: '${lat ?? '--'}'),
                  DetailLine(label: 'Longitude', value: '${lon ?? '--'}'),
                  DetailLine(label: 'Status', value: 'Saved locally'),
                ]),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(onPressed: () => generateAnalysisPdf(record, state: state), icon: const Icon(Icons.download), label: const Text('Download PDF Report')),
          ],
        ),
      ),
    );
  }
}

class ProfileStatCard extends StatelessWidget {
  final String value;
  final String label;
  const ProfileStatCard({super.key, required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
        child: Column(
          children: [
            Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: green)),
            const SizedBox(height: 4),
            Text(label, style: const TextStyle(fontSize: 12, color: Colors.black54)),
          ],
        ),
      ),
    );
  }
}

class ProfileSection extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const ProfileSection({super.key, required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionTitle(title.toUpperCase()),
            const SizedBox(height: 8),
            ...children,
          ],
        ),
      ),
    );
  }
}

class ProfileActionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  const ProfileActionTile({super.key, required this.icon, required this.title, required this.subtitle, this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(backgroundColor: softGreen, child: Icon(icon, color: green)),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right_rounded),
    );
  }
}

String suitabilityLabel(dynamic pct) {
  final n = pct is num ? pct : num.tryParse('$pct');
  if (n == null) return 'NOT YET ANALYZED';
  // Calibrated crop suitability scale:
  // 85-100% = Highly Suitable, 70-84% = Suitable,
  // 50-69% = Moderately Suitable, below 50% = Low Suitability.
  if (n >= 85) return 'HIGHLY SUITABLE';
  if (n >= 70) return 'SUITABLE';
  if (n >= 50) return 'MODERATELY SUITABLE';
  return 'LOW SUITABILITY';
}

String displaySuitability(Map<String, dynamic>? data) {
  if (data == null) return 'NOT YET ANALYZED';
  // Always compute the crop suitability from the actual compatibility percentage
  // so History, Details, Report, and Analyze screens show the same result.
  final pct = data['crop_compatibility_pct'] ?? data['compatibility_pct'];
  if (pct != null) return suitabilityLabel(pct);
  final explicit = data['suitability_level'];
  if (explicit != null && '$explicit'.trim().isNotEmpty) return '$explicit';
  final land = data['land_status'];
  if (land != null) return '$land';
  return 'ANALYZED';
}

Color suitabilityBadgeColor(Map<String, dynamic>? data) {
  final label = displaySuitability(data).toUpperCase();
  if (label.contains('HIGH')) return const Color(0xFF1FA463);
  if (label.contains('MODERATE') || label.contains('CONDITION'))
    return const Color(0xFFE9A829);
  if (label.contains('NOT') ||
      label.contains('WATER') ||
      label.contains('FLOOD')) return const Color(0xFFE45B5B);
  return const Color(0xFF1FA463);
}

Color suitabilityColor(dynamic pct) {
  final label = suitabilityLabel(pct);
  if (label.startsWith('HIGH')) return const Color(0xFFDCF5E4);
  if (label == 'SUITABLE') return const Color(0xFFE5F4D8);
  if (label.startsWith('MODERATE')) return const Color(0xFFFFE7B8);
  return const Color(0xFFFFD5D5);
}

Color infrastructureColor(Map<String, dynamic>? data) {
  final label = '${data?['infrastructure_suitability'] ?? ''}'.toUpperCase();
  if (label.contains('HIGH')) return const Color(0xFF1FA463);
  if (label.contains('MODERATE') || label.contains('CONDITION'))
    return const Color(0xFFE9A829);
  if (label.contains('NOT')) return const Color(0xFFE45B5B);
  return green;
}

