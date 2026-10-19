part of '../main.dart';

class ProfilePage extends StatelessWidget {
  final AnalysisState state;
  final VoidCallback logout;
  const ProfilePage({super.key, required this.state, required this.logout});
  void _open(BuildContext c, Widget page) =>
      Navigator.push(c, MaterialPageRoute(builder: (_) => page));
  @override
  Widget build(BuildContext context) {
    void edit() =>
        _open(context, EditProfilePage(state: state, logout: logout));
    Widget tile(
      IconData icon,
      String title,
      String subtitle,
      VoidCallback tap,
    ) => ProfileActionTile(
      icon: icon,
      title: title,
      subtitle: subtitle,
      onTap: tap,
    );
    return GeoSafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          GeoSustainHeader(title: 'Profile', state: state),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              color: green,
              image: const DecorationImage(
                image: AssetImage('assets/images/dashboard/field_header.png'),
                fit: BoxFit.cover,
                colorFilter: ColorFilter.mode(
                  Color(0xCC00603E),
                  BlendMode.srcATop,
                ),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      backgroundColor: Colors.white.withValues(alpha: .12),
                      side: const BorderSide(color: Colors.white54),
                    ),
                    onPressed: edit,
                    icon: const Icon(Icons.edit_outlined, size: 17),
                    label: const Text('Edit Profile'),
                  ),
                ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    InkWell(
                      onTap: edit,
                      child: Stack(
                        children: [
                          CircleAvatar(
                            radius: 36,
                            backgroundColor: Colors.white24,
                            backgroundImage: state.profilePhotoBytes == null
                                ? null
                                : MemoryImage(state.profilePhotoBytes!),
                            child: state.profilePhotoBytes == null
                                ? const Icon(
                                    Icons.person,
                                    size: 48,
                                    color: Colors.white,
                                  )
                                : null,
                          ),
                          const Positioned(
                            right: 0,
                            bottom: 0,
                            child: CircleAvatar(
                              radius: 13,
                              backgroundColor: Colors.white,
                              child: Icon(
                                Icons.photo_camera_outlined,
                                size: 18,
                                color: green,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            state.userName(),
                            style: const TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            '${state.currentUser?['email'] ?? ''}',
                            style: const TextStyle(color: Colors.white),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            state.userRole().toLowerCase().contains('account')
                                ? state.userRole()
                                : '${state.userRole()} Account',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          TextButton.icon(
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.white,
                            ),
                            onPressed: edit,
                            icon: const Icon(
                              Icons.location_on_outlined,
                              size: 17,
                            ),
                            label: Text(state.userLocation()),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ReferenceStat(
                  '${state.profileCounts['analysis_count'] ?? state.historyRecords.length}',
                  'Analysis',
                  Icons.map_outlined,
                  () => _open(context, SavedAnalysesPage(state: state)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ReferenceStat(
                  '${state.farms.length}',
                  'Saved Farms',
                  Icons.bookmark_outline,
                  () => _open(context, MyFarmsPage(state: state)),
                  tint: const Color(0xFFFFF3CE),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ReferenceStat(
                  '${state.profileCounts['report_count'] ?? state.generatedReports.length}',
                  'Reports',
                  Icons.description_outlined,
                  () => _open(context, ReportsListPage(state: state)),
                  tint: const Color(0xFFDDF3FC),
                ),
              ),
            ],
          ),
          const SizedBox(height: 17),
          ProfileSection(
            title: 'Account Management',
            children: [
              tile(
                Icons.person_outline,
                'Personal Information',
                'View and update your account details',
                edit,
              ),
              tile(
                Icons.lock_outline,
                'Security',
                'Change your password',
                () => _open(context, ChangePasswordPage(api: state.api)),
              ),
              tile(
                Icons.location_on_outlined,
                'Location',
                'Set your default location',
                edit,
              ),
              tile(
                Icons.notifications_none,
                'Notifications',
                'Manage your notification preferences',
                () => _open(context, const SettingsPage()),
              ),
              tile(
                Icons.dark_mode_outlined,
                'Appearance',
                'Light or dark mode',
                () => _open(context, const SettingsPage()),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ProfileSection(
            title: 'Analysis Library',
            children: [
              tile(
                Icons.bookmark_outline,
                'Saved Analysis',
                'View saved land and crop analysis records',
                () => _open(context, SavedAnalysesPage(state: state)),
              ),
              tile(
                Icons.description_outlined,
                'Reports',
                'Open generated land suitability reports',
                () => _open(context, ReportsListPage(state: state)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ProfileSection(
            title: 'Support & About',
            children: [
              tile(
                Icons.help_outline,
                'Help & Guide',
                'Learn how to use GeoSustain',
                () => showDialog(
                  context: context,
                  builder: (c) => AlertDialog(
                    title: const Text('Help & Guide'),
                    content: const SingleChildScrollView(
                      child: Text(
                        'Create a boundary by walking with GPS or drawing on the map. Saving a farm does not analyze it. Open a saved farm and choose Analyze This Farm. Review every crop?s evidence and limitations in its detail tabs. Submit a completed result for analyst review. Historical results retain the boundary and criteria used at the time.',
                      ),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(c),
                        child: const Text('Close'),
                      ),
                    ],
                  ),
                ),
              ),
              tile(
                Icons.info_outline,
                'About',
                'App version and data use',
                () => showAboutDialog(
                  context: context,
                  applicationName: 'GeoSustain',
                  applicationVersion: '1.0.0+1',
                  children: const [
                    Text(
                      'Your account owns its farm boundaries and analysis history. Environmental screening supports planning and requires field verification. Contact your project administrator for the deployed service?s privacy policy and support.',
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextButton.icon(
            onPressed: logout,
            icon: const Icon(Icons.logout),
            label: const Text('Sign Out'),
          ),
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

  @override
  void initState() {
    super.initState();
    nameController = TextEditingController(
      text: widget.state.currentUser?['username']?.toString() ?? 'User',
    );
    emailController = TextEditingController(
      text: widget.state.currentUser?['email']?.toString() ?? '',
    );
    locationController = TextEditingController(
      text: '${widget.state.currentUser?['location'] ?? ''}',
    );
    role = widget.state.userRole();
  }

  @override
  void dispose() {
    nameController.dispose();
    emailController.dispose();
    locationController.dispose();
    super.dispose();
  }

  Future<void> pickPhoto() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 70,
      maxWidth: 512,
      maxHeight: 512,
    );
    if (file == null) return;
    final bytes = await file.readAsBytes();
    setState(() {
      pickedPhotoBytes = bytes;
      pickedPhotoBase64 = base64Encode(bytes);
    });
  }

  Future<void> saveProfile() async {
    if (saving) return;
    if (nameController.text.trim().length < 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Name must be at least 3 characters.')),
      );
      return;
    }
    setState(() => saving = true);
    try {
      final updated = await widget.state.api.updateProfile(
        username: nameController.text.trim().isEmpty
            ? 'User'
            : nameController.text.trim(),
        location: locationController.text.trim(),
        profilePhotoBase64: pickedPhotoBase64,
      );
      widget.state.updateCurrentProfile(updated, photo: pickedPhotoBytes);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Profile updated.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Profile update failed: ${e.toString().replaceFirst('Exception: ', '')}',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> confirmDanger({required bool delete}) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(delete ? 'Delete account?' : 'Deactivate account?'),
        content: Text(
          delete
              ? 'This permanently removes your account and linked records from the online database.'
              : 'This disables your account until an admin reactivates it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: delete ? Colors.red : Colors.orange,
            ),
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final avatarBytes = pickedPhotoBytes ?? widget.state.profilePhotoBytes;
    return Scaffold(
      backgroundColor: bg,
      body: GeoSafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            GeoSustainHeader(
              title: 'Account Settings',
              state: widget.state,
              back: () => Navigator.pop(context),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  children: [
                    Stack(
                      children: [
                        CircleAvatar(
                          radius: 54,
                          backgroundColor: softGreen,
                          backgroundImage: avatarBytes != null
                              ? MemoryImage(avatarBytes)
                              : null,
                          child: avatarBytes == null
                              ? const Icon(
                                  Icons.person_rounded,
                                  color: green,
                                  size: 58,
                                )
                              : null,
                        ),
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: CircleAvatar(
                            backgroundColor: green,
                            child: IconButton(
                              onPressed: pickPhoto,
                              icon: const Icon(
                                Icons.camera_alt,
                                color: Colors.white,
                                size: 18,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    TextButton.icon(
                      onPressed: pickPhoto,
                      icon: const Icon(Icons.photo_library_outlined),
                      label: const Text('Upload profile photo'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(
                        labelText: 'Full Name',
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: emailController,
                      readOnly: true,
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        prefixIcon: Icon(Icons.mail_outline),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      initialValue: role,
                      readOnly: true,
                      decoration: const InputDecoration(
                        labelText: 'Role',
                        helperText: 'Assigned by your administrator',
                        prefixIcon: Icon(Icons.badge_outlined),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: softGreen,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text(
                        role == 'Agricultural Planning Analyst'
                            ? 'Agricultural Planning Analyst: view reports, saved analyses, and planning insights for independent environmental monitoring.'
                            : 'Farmer: analyze land, get crop recommendations, save reports, and receive weather alerts.',
                        style: const TextStyle(
                          color: darkGreen,
                          fontWeight: FontWeight.w700,
                          height: 1.3,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: locationController,
                      decoration: const InputDecoration(
                        labelText: 'Location',
                        prefixIcon: Icon(Icons.location_on_outlined),
                      ),
                    ),
                    const SizedBox(height: 18),
                    FilledButton.icon(
                      onPressed: saving ? null : saveProfile,
                      icon: saving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.save_outlined),
                      label: Text(saving ? 'Saving...' : 'Save Changes'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(
                      Icons.pause_circle_outline,
                      color: Colors.orange,
                    ),
                    title: const Text('Deactivate Account'),
                    subtitle: const Text('Temporarily disable this account'),
                    onTap: () => confirmDanger(delete: false),
                  ),
                  const Divider(height: 0),
                  ListTile(
                    leading: const Icon(
                      Icons.delete_outline,
                      color: Colors.red,
                    ),
                    title: const Text('Delete Account'),
                    subtitle: const Text(
                      'Permanently remove account from database',
                    ),
                    onTap: () => confirmDanger(delete: true),
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

class SavedAnalysesPage extends StatelessWidget {
  final AnalysisState state;
  const SavedAnalysesPage({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    final rows = state.savedAnalyses;
    return Scaffold(
      backgroundColor: bg,
      body: GeoSafeArea(
        child: Column(
          children: [
            GeoSustainHeader(
              title: 'Saved Analysis',
              state: state,
              back: () => Navigator.pop(context),
            ),
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
                            leading: const CircleAvatar(
                              backgroundColor: softGreen,
                              child: Icon(Icons.bookmark, color: green),
                            ),
                            title: Text(
                              '${r['title'] ?? 'Unknown location'}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            subtitle: Text(
                              '${r['subtitle'] ?? 'Land suitability analysis'}\n${r['date'] ?? '--'}',
                            ),
                            isThreeLine: true,
                            trailing: const Icon(Icons.chevron_right_rounded),
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    SavedAnalysisDetailPage(record: r),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
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
      body: GeoSafeArea(
        child: Column(
          children: [
            GeoSustainHeader(
              title: 'Reports',
              state: state,
              back: () => Navigator.pop(context),
            ),
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
                            leading: const CircleAvatar(
                              backgroundColor: softGreen,
                              child: Icon(Icons.description, color: green),
                            ),
                            title: Text(
                              'Report: ${r['title'] ?? 'Unknown location'}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            subtitle: Text(
                              '${r['subtitle'] ?? 'Land suitability report'}\n${r['date'] ?? '--'}',
                            ),
                            isThreeLine: true,
                            trailing: const Icon(Icons.chevron_right_rounded),
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => SavedAnalysisDetailPage(
                                  record: r,
                                  title: 'Saved Report',
                                  state: state,
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class SavedAnalysisDetailPage extends StatelessWidget {
  final Map<String, dynamic> record;
  final String title;
  final AnalysisState? state;
  const SavedAnalysisDetailPage({
    super.key,
    required this.record,
    this.title = 'Saved Analysis',
    this.state,
  });

  @override
  Widget build(BuildContext context) {
    final lat = record['center_lat'] ?? record['lat'];
    final lon = record['center_lon'] ?? record['lon'];
    return Scaffold(
      backgroundColor: bg,
      body: GeoSafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            GeoSustainHeader(
              title: title,
              state: state,
              back: () => Navigator.pop(context),
              trailing: IconButton(
                onPressed: () => generateAnalysisPdf(record, state: state),
                icon: const Icon(Icons.download_outlined),
              ),
            ),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${record['title'] ?? 'Unknown location'}',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: green,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${record['subtitle'] ?? 'Land suitability analysis'}',
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Date: ${record['date'] ?? '--'}',
                      style: const TextStyle(color: Colors.black54),
                    ),
                    const Divider(height: 28),
                    DetailLine(label: 'Latitude', value: '${lat ?? '--'}'),
                    DetailLine(label: 'Longitude', value: '${lon ?? '--'}'),
                    DetailLine(label: 'Status', value: 'Saved locally'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () => generateAnalysisPdf(record, state: state),
              icon: const Icon(Icons.download),
              label: const Text('Download PDF Report'),
            ),
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
            Text(
              value,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: green,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ],
        ),
      ),
    );
  }
}

class ProfileSection extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const ProfileSection({
    super.key,
    required this.title,
    required this.children,
  });

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      GeoSectionHeader(title),
      Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(
            children: [
              for (final entry in children.indexed) ...[
                if (entry.$1 > 0)
                  const Divider(height: 1, color: Color(0xFFEDF1EC)),
                entry.$2,
              ],
            ],
          ),
        ),
      ),
    ],
  );
}

class ProfileActionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  const ProfileActionTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor: softGreen,
        child: Icon(icon, color: green),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right_rounded),
    );
  }
}

String suitabilityLabel(dynamic pct) {
  final n = pct is num ? pct : num.tryParse('$pct');
  if (n == null) return 'NOT YET ANALYZED';
  // Original suitability scale used across legend and badges.
  if (n >= 75) return 'HIGHLY SUITABLE';
  if (n >= 50) return 'MODERATELY SUITABLE';
  if (n >= 25) return 'MARGINALLY SUITABLE';
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
  if (label.contains('MODERATE') || label.contains('CONDITION')) {
    return const Color(0xFF8BDD75);
  }
  if (label.contains('MARGIN')) return const Color(0xFFE9A829);
  if (label.contains('NOT') ||
      label.contains('WATER') ||
      label.contains('FLOOD')) {
    return const Color(0xFFE45B5B);
  }
  return const Color(0xFF1FA463);
}

Color suitabilityColor(dynamic pct) {
  final label = suitabilityLabel(pct);
  if (label.startsWith('HIGH')) return const Color(0xFFDCF5E4);
  if (label.startsWith('MODERATE')) return const Color(0xFFE5F4D8);
  if (label.startsWith('MARGINAL')) return const Color(0xFFFFE7B8);
  return const Color(0xFFFFD5D5);
}

Color infrastructureColor(Map<String, dynamic>? data) {
  final label = '${data?['infrastructure_suitability'] ?? ''}'.toUpperCase();
  if (label.contains('HIGH')) return const Color(0xFF1FA463);
  if (label.contains('MODERATE') || label.contains('CONDITION')) {
    return const Color(0xFFE9A829);
  }
  if (label.contains('NOT')) return const Color(0xFFE45B5B);
  return green;
}

class ChangePasswordPage extends StatefulWidget {
  final ApiService api;
  const ChangePasswordPage({super.key, required this.api});
  @override
  State<ChangePasswordPage> createState() => _ChangePasswordPageState();
}

class _ChangePasswordPageState extends State<ChangePasswordPage> {
  final current = TextEditingController(),
      password = TextEditingController(),
      confirm = TextEditingController();
  bool saving = false, obscure = true;
  String? error;
  @override
  void dispose() {
    current.dispose();
    password.dispose();
    confirm.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (saving) return;
    if (current.text.isEmpty ||
        password.text.runes.length < 15 ||
        utf8.encode(password.text).length > 72 ||
        password.text != confirm.text) {
      setState(
        () => error =
            'Enter your current password and matching new passwords (15 characters minimum, 72 UTF-8 bytes maximum).',
      );
      return;
    }
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await widget.api.changePassword(current.text, password.text);
      if (!mounted) return;
      showAuthFeedback(
        context,
        'Password changed. Other sessions must sign in again.',
        success: true,
      );
      Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => error = friendlyErrorMessage(e));
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: const GeoSustainHeader(
      title: 'Change Password',
      embedded: false,
      nested: true,
    ),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'Your current password is required. Your other sessions will be signed out.',
          ),
          const SizedBox(height: 18),
          for (final field in [
            (current, 'Current password'),
            (password, 'New password'),
            (confirm, 'Confirm new password'),
          ]) ...[
            TextField(
              controller: field.$1,
              obscureText: obscure,
              enabled: !saving,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                labelText: field.$2,
                suffixIcon: IconButton(
                  onPressed: () => setState(() => obscure = !obscure),
                  icon: Icon(
                    obscure
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text(error!, style: const TextStyle(color: Colors.red)),
            ),
          FilledButton(
            onPressed: saving ? null : save,
            child: Text(saving ? 'Saving...' : 'Change Password'),
          ),
        ],
      ),
    ),
  );
}

class LocationGuidancePage extends StatefulWidget {
  const LocationGuidancePage({super.key});
  @override
  State<LocationGuidancePage> createState() => _LocationGuidancePageState();
}

class _LocationGuidancePageState extends State<LocationGuidancePage> {
  String status = 'Checking location access...';
  @override
  void initState() {
    super.initState();
    check();
  }

  Future<void> check({bool request = false}) async {
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      var permission = await Geolocator.checkPermission();
      if (request && permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      final message = !enabled
          ? 'Device location is off. Enable GPS in your device settings.'
          : permission == LocationPermission.deniedForever
          ? 'Location is blocked. Allow location for GeoSustain in app or browser settings.'
          : permission == LocationPermission.denied
          ? 'Location permission has not been granted.'
          : 'Location access is available for GPS recording.';
      if (mounted) setState(() => status = message);
    } catch (e) {
      if (mounted) setState(() => status = friendlyErrorMessage(e));
    }
  }

  Future<void> openSettings(bool location) async {
    try {
      final opened = location
          ? await Geolocator.openLocationSettings()
          : await Geolocator.openAppSettings();
      if (!opened && mounted) {
        setState(
          () => status =
              'Open your device or browser settings and allow location for GeoSustain.',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => status =
              'Open your browser site permissions and allow location for GeoSustain.',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: const GeoSustainHeader(
      title: 'Location Permission',
      embedded: false,
      nested: true,
    ),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(status),
          const SizedBox(height: 16),
          const Text(
            'GPS walking needs location access and a clear outdoor signal. Recording pauses when the app is backgrounded. Drawing a polygon works without location permission.',
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: () => check(request: true),
            child: const Text('Check / request permission'),
          ),
          if (!kIsWeb) ...[
            TextButton(
              onPressed: () => openSettings(false),
              child: const Text('Open app settings'),
            ),
            TextButton(
              onPressed: () => openSettings(true),
              child: const Text('Open location settings'),
            ),
          ],
          if (kIsWeb)
            const Padding(
              padding: EdgeInsets.only(top: 16),
              child: Text(
                'In your browser, open site permissions beside the address bar and allow Location. GPS requires HTTPS or a trusted local development origin.',
              ),
            ),
        ],
      ),
    ),
  );
}
