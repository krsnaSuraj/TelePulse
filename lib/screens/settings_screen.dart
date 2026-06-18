import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/proxy_list_provider.dart';
import '../services/update_service.dart';
import '../theme/app_theme.dart';
import '../utils/haptic_utils.dart';

final updateServiceProvider = Provider<UpdateService>((ref) => UpdateService());

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen>
    with SingleTickerProviderStateMixin {
  final _customUrlController = TextEditingController();
  bool _isAdding = false;
  bool _isCheckingUpdate = false;
  String? _updateCheckError;
  String? _appVersion;

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    final service = ref.read(updateServiceProvider);
    final ver = await service.currentVersion;
    if (mounted) {
      setState(() => _appVersion = ver ?? '--');
    }
  }

  @override
  void dispose() {
    _customUrlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final notifier = ref.read(proxyListProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          _buildCustomSourceSection(notifier),
          const SizedBox(height: 28),
          _SectionHeader(icon: Icons.dns_rounded, title: 'PROXY SOURCES'),
          const SizedBox(height: 10),
          _buildSourcesSection(),
          const SizedBox(height: 28),
          _SectionHeader(icon: Icons.analytics_rounded, title: 'STATISTICS'),
          const SizedBox(height: 10),
          _buildStatsSection(notifier),
          const SizedBox(height: 28),
          _SectionHeader(icon: Icons.system_update_rounded, title: 'UPDATES'),
          const SizedBox(height: 10),
          _buildUpdateSection(),
          const SizedBox(height: 28),
          _SectionHeader(icon: Icons.info_outline_rounded, title: 'ABOUT'),
          const SizedBox(height: 10),
          _buildAboutSection(),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildCustomSourceSection(ProxyListNotifier notifier) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Add Custom Source',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 2),
          const Text(
            'Enter a URL containing proxy links (tg://, t.me, or plain format)',
            style: TextStyle(fontSize: 11, color: AppColors.textMuted),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _customUrlController,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _addCustomSource(notifier),
                  decoration: const InputDecoration(
                    hintText: 'https://',
                    prefixIcon: Icon(Icons.link_rounded, size: 18),
                    isDense: true,
                  ),
                  style: const TextStyle(
                    fontSize: 13,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                height: 46,
                child: FilledButton(
                  onPressed:
                      _isAdding ? null : () => _addCustomSource(notifier),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: _isAdding
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Add'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSourcesSection() {
    return Container(
      decoration: _cardDecoration(),
      child: Column(
        children: [
          _SourceTile(
            icon: Icons.verified_rounded,
            iconColor: AppColors.primary,
            name: 'SoliSpirit',
            subtitle: 'Verified primary MTProto proxy list',
            trailing: Icons.open_in_new_rounded,
            onTap: () => _openUrl('https://github.com/SoliSpirit/mtproto'),
          ),
          _sourceDivider(),
          _SourceTile(
            icon: Icons.dns_rounded,
            iconColor: AppColors.primary,
            name: 'kort0881',
            subtitle: 'Multi-region collections: all, EU, RU',
          ),
          _sourceDivider(),
          _SourceTile(
            icon: Icons.copy_rounded,
            iconColor: AppColors.primary,
            name: 'Grim1313',
            subtitle: 'Community fork mirror',
          ),
          _sourceDivider(),
          _SourceTile(
            icon: Icons.storage_rounded,
            iconColor: AppColors.textMuted,
            name: 'iwh3n / ALIILAPRO',
            subtitle: 'Proxy scrapers & finders',
          ),
          _sourceDivider(),
          _SourceTile(
            icon: Icons.cloud_outlined,
            iconColor: AppColors.textMuted,
            name: 'SoliSpirit-mirror & Grim1313-HTML',
            subtitle: 'CDN mirror & HTML parser fallbacks',
          ),
        ],
      ),
    );
  }

  Widget _buildStatsSection(ProxyListNotifier notifier) {
    final alive = notifier.aliveCount;
    final total = notifier.totalProxies;
    final tested = notifier.testedCount;
    final isTesting = notifier.isTesting;
    final percent = notifier.alivePercent;
    final avgLat = notifier.avgLatency;

    return Container(
      decoration: _cardDecoration(),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Column(
              children: [
                Row(
                  children: [
                    _statItem('Total', '$total', AppColors.textPrimary),
                    const SizedBox(width: 24),
                    _statItem('Alive', '$alive', AppColors.alive),
                    const SizedBox(width: 24),
                    _statItem('Dead', '${total - alive}', AppColors.dead),
                  ],
                ),
                const SizedBox(height: 12),
                if (total > 0) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: Container(
                      height: 4,
                      width: double.infinity,
                      color: AppColors.surfaceBorder,
                      child: FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: percent.clamp(0.0, 1.0),
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(2),
                            gradient: LinearGradient(
                              colors: [
                                AppColors.alive.withValues(alpha: 0.6),
                                AppColors.alive,
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                Row(
                  children: [
                    _statItem('Avg Latency',
                        avgLat > 0 ? '${avgLat.toStringAsFixed(0)}ms' : '--',
                        AppColors.textSecondary),
                    const SizedBox(width: 24),
                    _statItem('Testing',
                        isTesting ? '$tested/$total' : 'Done',
                        isTesting ? AppColors.terminalGreen : AppColors.textMuted),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _statItem(String label, String value, Color color) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: color,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              color: AppColors.textMuted,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUpdateSection() {
    return Container(
      decoration: _cardDecoration(),
      child: Column(
        children: [
          ListTile(
            leading: _isCheckingUpdate
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.system_update_rounded,
                    color: AppColors.textMuted, size: 18),
            title: const Text(
              'Check for Updates',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            ),
            subtitle: _updateCheckError != null
                ? Text(
                    _updateCheckError!,
                    style: const TextStyle(fontSize: 11, color: AppColors.warning),
                  )
                : null,
            trailing: const Icon(Icons.chevron_right_rounded,
                color: AppColors.textMuted, size: 18),
            dense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            onTap: _isCheckingUpdate ? null : _checkForUpdate,
          ),
        ],
      ),
    );
  }

  Widget _buildAboutSection() {
    return Container(
      decoration: _cardDecoration(),
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.shield_rounded,
                color: AppColors.primary, size: 20),
            title: const Text(
              'TelePulse',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            subtitle: const Text(
              'MTProto Proxy Manager',
              style: TextStyle(fontSize: 11, color: AppColors.textMuted),
            ),
            dense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
          ),
          _aboutDivider(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                _aboutInfo(label: 'Version', value: _appVersion ?? '--'),
                const SizedBox(width: 32),
                _aboutInfo(label: 'Protocol', value: 'MTProto v2'),
              ],
            ),
          ),
          _aboutDivider(),
          ListTile(
            leading: const Icon(Icons.code_rounded,
                color: AppColors.primary, size: 18),
            title: const Text(
              'Open Source',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            ),
            subtitle: const Text(
              'github.com/krsnaSuraj/TelePulse',
              style: TextStyle(
                fontSize: 11,
                color: AppColors.primary,
                decoration: TextDecoration.underline,
              ),
            ),
            trailing: const Icon(Icons.open_in_new_rounded,
                color: AppColors.textMuted, size: 16),
            dense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            onTap: () => _openUrl('https://github.com/krsnaSuraj/TelePulse'),
          ),
        ],
      ),
    );
  }

  Widget _aboutInfo({required String label, required String value}) {
    return Expanded(
      child: Row(
        children: [
          Text(
            '$label: ',
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textMuted,
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }

  BoxDecoration _cardDecoration() {
    return BoxDecoration(
      color: AppColors.surfaceCard,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: AppColors.surfaceBorder, width: 0.5),
    );
  }

  Widget _sourceDivider() =>
      const Divider(height: 1, indent: 16, endIndent: 16);

  Widget _aboutDivider() =>
      const Divider(height: 1, indent: 16, endIndent: 16);

  Future<void> _openUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    AppHaptics.light();
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  Future<void> _checkForUpdate() async {
    setState(() {
      _isCheckingUpdate = true;
      _updateCheckError = null;
    });
    AppHaptics.light();

    try {
      final updateService = ref.read(updateServiceProvider);
      final update = await updateService.checkForUpdate(force: true);

      if (!mounted) return;
      setState(() => _isCheckingUpdate = false);

      if (update == null) {
        final version = await updateService.currentVersion;
        _showUpToDate(version ?? '--');
        return;
      }

      final skipped = await updateService.skippedVersion;
      if (skipped == update.latestVersion) return;

      _showUpdateDialog(update, updateService);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isCheckingUpdate = false;
        _updateCheckError = 'Could not check for updates';
      });
    }
  }

  void _showUpToDate(String version) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('TelePulse v$version is up to date'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _showUpdateDialog(UpdateInfo update, UpdateService updateService) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceCard,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.surfaceBorder, width: 0.5),
        ),
        title: const Row(
          children: [
            Icon(Icons.system_update_rounded,
                color: AppColors.primary, size: 22),
            SizedBox(width: 10),
            Text(
              'Update Available',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'v${update.latestVersion} is now available',
              style: const TextStyle(
                fontSize: 14,
                color: AppColors.primary,
                fontWeight: FontWeight.w500,
              ),
            ),
            if (update.releaseNotes != null && update.releaseNotes!.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text(
                'Release Notes:',
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.textMuted,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Container(
                width: double.maxFinite,
                constraints: const BoxConstraints(maxHeight: 160),
                decoration: BoxDecoration(
                  color: AppColors.surfaceElevated,
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: const EdgeInsets.all(10),
                child: SingleChildScrollView(
                  child: Text(
                    update.releaseNotes!,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                      height: 1.5,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Not Now',
                style: TextStyle(color: AppColors.textMuted)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              updateService.skipVersion(update.latestVersion);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Skipped v${update.latestVersion}'),
                  duration: const Duration(seconds: 2),
                ),
              );
            },
            child: const Text('Skip',
                style: TextStyle(color: AppColors.textMuted)),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              _openUrl(update.downloadUrl);
            },
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text('Download'),
          ),
        ],
      ),
    );
  }

  Future<void> _addCustomSource(ProxyListNotifier notifier) async {
    final url = _customUrlController.text.trim();
    if (url.isEmpty || _isAdding) return;

    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter a valid URL starting with http:// or https://'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    setState(() => _isAdding = true);
    AppHaptics.light();

    try {
      final success = await notifier.addCustomSource(url);
      _customUrlController.clear();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            success
                ? 'Proxy source added successfully'
                : 'No proxies found at this URL',
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to add source: $e'),
          duration: const Duration(seconds: 3),
        ),
      );
    } finally {
      if (mounted) setState(() => _isAdding = false);
    }
  }
}

class _SourceTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String name;
  final String subtitle;
  final IconData? trailing;
  final VoidCallback? onTap;

  const _SourceTile({
    required this.icon,
    required this.iconColor,
    required this.name,
    required this.subtitle,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: iconColor, size: 18),
      title: Text(
        name,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
      ),
      trailing: trailing != null
          ? Icon(trailing, color: AppColors.textMuted, size: 14)
          : null,
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      onTap: onTap,
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  const _SectionHeader({required this.icon, required this.title});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 14, color: AppColors.textMuted),
        const SizedBox(width: 6),
        Text(
          title,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: AppColors.textMuted,
            letterSpacing: 1.0,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Container(
            height: 1,
            color: AppColors.surfaceBorder.withValues(alpha: 0.5),
          ),
        ),
      ],
    );
  }
}
