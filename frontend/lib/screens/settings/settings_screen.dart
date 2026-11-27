import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../providers/auth_provider.dart';
import '../../providers/serfix_provider.dart';
import '../../providers/settings_provider.dart';
import '../../services/session_service.dart';
import '../../widgets/serfix_components.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  Future<void> _editApiUrl(BuildContext context) async {
    final settings = context.read<SettingsProvider>();
    final controller = TextEditingController(text: settings.apiBaseUrl);
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Alamat server SerFix API'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.url,
          autocorrect: false,
          decoration: const InputDecoration(
            labelText: 'Base URL API',
            hintText: 'http://10.0.2.2/serfix/api',
            prefixIcon: Icon(Icons.link_rounded),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (result == null || !context.mounted) return;
    final saved = await settings.setApiBaseUrl(result);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(saved
            ? 'Alamat server berhasil disimpan.'
            : settings.errorMessage ?? 'Gagal menyimpan alamat server.'),
      ),
    );
  }

  Future<void> _logout(BuildContext context) async {
    final auth = context.read<AuthProvider>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Keluar dari akun?'),
        content:
            const Text('Anda perlu masuk kembali untuk mengakses data SerFix.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Keluar'),
          ),
        ],
      ),
    );
    if (confirmed == true) await auth.logout();
  }

  Future<void> _resetApiBaseUrl(BuildContext context) async {
    final settings = context.read<SettingsProvider>();
    final saved = await settings.resetApiBaseUrl();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(saved
            ? 'URL bawaan berhasil dipulihkan.'
            : settings.errorMessage ?? 'Gagal memulihkan URL bawaan.'),
      ),
    );
  }

  Future<void> _registerPushDevice(BuildContext context) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Daftarkan perangkat push'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Push/FCM token',
            hintText: 'Tempel token perangkat',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('Daftar'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (result == null || result.trim().isEmpty || !context.mounted) return;
    try {
      await context
          .read<SerfixProvider>()
          .registerPushDevice(result.trim(), Theme.of(context).platform.name);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Perangkat push berhasil didaftarkan.')),
        );
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.toString())),
        );
      }
    }
  }

  Future<void> _syncOffline(BuildContext context) async {
    final mutations = await SessionService.getSerfixMutations();
    if (!context.mounted) return;
    if (mutations.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Tidak ada perubahan offline untuk sinkronisasi.')),
      );
      return;
    }
    try {
      await context.read<SerfixProvider>().syncOfflineMutations(mutations);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Perubahan offline berhasil disinkronkan.')),
        );
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.toString())),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final user = context.watch<AuthProvider>().currentUser;
    return Scaffold(
      appBar: const SerfixAppBar(
        title: 'Pengaturan',
        subtitle: 'Preferensi dan keamanan akun',
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.x4),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.x4),
              child: Row(
                children: [
                  Container(
                    width: AppSpacing.appLogoSize,
                    height: AppSpacing.appLogoSize,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                    ),
                    child: const Icon(
                      Icons.person_outline,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.x3),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user?.name ?? 'Pengguna SerFix',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: AppSpacing.x1),
                        Text(
                          '${user?.email ?? ''} · ${user?.role ?? ''}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.verified_user_outlined,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.x6),
          Text('Tampilan', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.x2),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.x3),
              child: SegmentedButton<ThemeMode>(
                segments: const [
                  ButtonSegment(
                    value: ThemeMode.system,
                    icon: Icon(Icons.settings_suggest_outlined),
                    label: Text('Sistem'),
                  ),
                  ButtonSegment(
                    value: ThemeMode.light,
                    icon: Icon(Icons.light_mode_outlined),
                    label: Text('Terang'),
                  ),
                  ButtonSegment(
                    value: ThemeMode.dark,
                    icon: Icon(Icons.dark_mode_outlined),
                    label: Text('Gelap'),
                  ),
                ],
                selected: {settings.themeMode},
                onSelectionChanged: (value) =>
                    settings.setThemeMode(value.single),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.x6),
          Text('Sinkronisasi dan push',
              style: Theme.of(context).textTheme.titleMedium),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.notifications_active_outlined),
                  title: const Text('Daftarkan perangkat push'),
                  subtitle: const Text(
                      'Tambahkan token FCM/APNs dari provider push.'),
                  onTap: () => _registerPushDevice(context),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.sync),
                  title: const Text('Sinkronkan data offline'),
                  subtitle: const Text('Unggah perubahan yang masih antre.'),
                  onTap: () => _syncOffline(context),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.x6),
          Text('Server', style: Theme.of(context).textTheme.titleMedium),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.link),
                  title: const Text('Base URL API'),
                  subtitle: Text(settings.apiBaseUrl),
                  onTap: () => _editApiUrl(context),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.restart_alt),
                  title: const Text('Kembalikan URL bawaan'),
                  onTap: () => _resetApiBaseUrl(context),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          OutlinedButton.icon(
            onPressed: () => _logout(context),
            icon: const Icon(Icons.logout),
            label: const Text('Keluar dari akun'),
          ),
        ],
      ),
    );
  }
}
