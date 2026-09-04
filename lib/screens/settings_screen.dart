import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/app_errors.dart';
import '../core/app_meta.dart';
import '../core/formatters.dart';
import '../core/haptics.dart';
import '../core/theme/app_theme.dart';
import '../data/proxy_sources.dart';
import '../providers/proxy_list_provider.dart';
import '../services/update_service.dart';
import '../widgets/brand_mark.dart';

final updateServiceProvider =
    Provider<UpdateService>((ref) => UpdateService());

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
  bool _clearing = false;
  late final AnimationController _entrance;

  @override
  void initState() {
    super.initState();
    // Single shared bounded entrance (home/proxies pattern). Muted while
    // this tab is hidden — resumes when shown. No logic changes.
    _entrance = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..forward();
  }

  @override
  void dispose() {
    _entrance.dispose();
    _customUrlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(proxyListProvider);
    final notifier = ref.read(proxyListProvider.notifier);

    // Staggered entrance: single shared bounded controller, first ~10 blocks.
    // Same content, same taps — pure motion. Skips when reduced motion is on.
    var order = 0;
    var animated = 0;
    Widget step(Widget child) {
      if (animated >= 10) return child;
      animated++;
      return _SettingsEntrance(
          index: order++, animation: _entrance, child: child);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          step(_section('CONNECTION', Icons.sync_rounded)),
          step(_card(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                SwitchListTile(
                  value: state.autoScanOnReconnect,
                  onChanged: (v) {
                    AppHaptics.selection();
                    notifier.setAutoScanOnReconnect(v);
                  },
                  secondary: const Icon(Icons.autorenew_rounded,
                      size: 20, color: AppColors.signal),
                  title: const Text('Auto-scan on reconnect',
                      style: TextStyle(fontSize: 14)),
                  subtitle: const Text(
                      'Start a fresh scan when the connection returns',
                      style: TextStyle(
                          fontSize: 11.5, color: AppColors.textMuted)),
                  dense: true,
                ),
                _divider(),
                SwitchListTile(
                  value: state.wifiOnlyAutoScan,
                  onChanged: (v) {
                    AppHaptics.selection();
                    notifier.setWifiOnlyAutoScan(v);
                  },
                  secondary: const Icon(Icons.wifi_rounded,
                      size: 20, color: AppColors.signal),
                  title: const Text('Wi-Fi only for auto scans',
                      style: TextStyle(fontSize: 14)),
                  subtitle: const Text(
                      'Pause background scans on mobile data — manual refresh always works',
                      style: TextStyle(
                          fontSize: 11.5, color: AppColors.textMuted)),
                  dense: true,
                ),
              ],
            ),
          )),
          step(_section('SOURCES', Icons.dns_rounded)),
          step(_card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Add custom source',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  'HTTPS URL containing tg://, t.me or plain proxy lines',
                  style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _customUrlController,
                        keyboardType: TextInputType.url,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _addSource(notifier),
                        decoration: const InputDecoration(
                          hintText: 'https://…',
                          prefixIcon:
                              Icon(Icons.link_rounded, size: 18),
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
                            _isAdding ? null : () => _addSource(notifier),
                        style: FilledButton.styleFrom(
                          padding:
                              const EdgeInsets.symmetric(horizontal: 20),
                        ),
                        // Micro-interaction: Add ↔ spinner cross-fades.
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 150),
                          transitionBuilder: (child, animation) =>
                              FadeTransition(
                            opacity: animation,
                            child: ScaleTransition(
                                scale: animation, child: child),
                          ),
                          child: _isAdding
                              ? const SizedBox(
                                  key: ValueKey<String>('adding'),
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2),
                                )
                              : const Text('Add',
                                  key: ValueKey<String>('add')),
                        ),
                      ),
                    ),
                  ],
                ),
                // Smooth expand/collapse when sources are added or removed.
                ClipRect(
                  child: AnimatedSize(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOut,
                    child: state.customSources.isNotEmpty
                        ? Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const SizedBox(height: 8),
                              for (final url in state.customSources)
                                _customSourceRow(url, notifier),
                            ],
                          )
                        : const SizedBox.shrink(),
                  ),
                ),
              ],
            ),
          )),
          const SizedBox(height: 10),
          step(_card(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (var i = 0; i < ProxySources.all.length; i++) ...[
                  if (i > 0) _divider(),
                  _builtinSourceRow(ProxySources.all[i]),
                ],
              ],
            ),
          )),
          step(_section('DATA', Icons.storage_rounded)),
          step(_card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _stat('Cached', '${state.proxies.length}',
                        AppColors.textPrimary),
                    const SizedBox(width: 16),
                    _stat('Working', '${state.aliveCount}',
                        AppColors.alive),
                    const SizedBox(width: 16),
                    _stat('Saved', timeAgoShort(state.lastUpdated),
                        AppColors.textMuted),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _clearing ? null : () => _confirmClear(notifier),
                    icon: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 150),
                      transitionBuilder: (child, animation) => FadeTransition(
                        opacity: animation,
                        child: ScaleTransition(
                            scale: animation, child: child),
                      ),
                      child: _clearing
                          ? const SizedBox(
                              key: ValueKey<String>('clearing'),
                              width: 16,
                              height: 16,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.delete_sweep_rounded,
                              key: ValueKey<String>('clear-idle'), size: 18),
                    ),
                    label: const Text('Clear cached proxies'),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed:
                        _clearing ? null : () => _confirmDeleteAll(notifier),
                    icon: const Icon(Icons.delete_forever_rounded, size: 18),
                    label: const Text('Delete all local data'),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Clear removes saved scan results only — favorites, sources and preferences stay. Delete-all wipes everything on this device. No analytics, no accounts, nothing leaves your phone except proxy-list fetches.',
                  style: TextStyle(
                      fontSize: 11.5,
                      color: AppColors.textMuted,
                      height: 1.5),
                ),
              ],
            ),
          )),
          step(_section('UPDATES', Icons.system_update_rounded)),
          step(_card(
            padding: EdgeInsets.zero,
            child: ListTile(
              leading: AnimatedSwitcher(
                duration: const Duration(milliseconds: 150),
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: ScaleTransition(scale: animation, child: child),
                ),
                child: _isCheckingUpdate
                    ? const SizedBox(
                        key: ValueKey<String>('checking'),
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.system_update_rounded,
                        key: ValueKey<String>('check-idle'),
                        color: AppColors.textMuted,
                        size: 20),
              ),
              title: const Text('Check for updates',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
              // Error ↔ version cross-fades instead of snapping.
              subtitle: AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation, child: child),
                child: _updateCheckError != null
                    ? Text(_updateCheckError!,
                        key: const ValueKey<String>('update-error'),
                        style: const TextStyle(
                            fontSize: 11.5, color: AppColors.warn))
                    : Text('v${AppMeta.version} installed',
                        key: const ValueKey<String>('update-ok'),
                        style: const TextStyle(
                            fontSize: 11.5, color: AppColors.textMuted)),
              ),
              trailing: const Icon(Icons.chevron_right_rounded,
                  color: AppColors.textMuted, size: 20),
              dense: true,
              onTap: _isCheckingUpdate ? null : _checkForUpdate,
            ),
          )),
          step(_section('ABOUT', Icons.info_outline_rounded)),
          step(const _AboutCard()),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _customSourceRow(String url, ProxyListNotifier notifier) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          const Icon(Icons.rss_feed_rounded,
              size: 14, color: AppColors.signal),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              Uri.tryParse(url)?.host ?? url,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                fontFamily: 'monospace',
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Semantics(
            label: 'Remove custom source $url',
            child: IconButton(
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.close_rounded, size: 16),
              tooltip: 'Remove source',
              onPressed: () => notifier.removeCustomSource(url),
            ),
          ),
        ],
      ),
    );
  }

  Widget _builtinSourceRow(ProxySource source) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      child: Row(
        children: [
          const Icon(Icons.dns_rounded,
              size: 18, color: AppColors.textMuted),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(source.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 13.5, fontWeight: FontWeight.w500)),
                const SizedBox(height: 2),
                Text(
                  source.format == 'html'
                      ? 'HTML fallback · trust ${source.weight}/5'
                      : 'Auto format · trust ${source.weight}/5',
                  style: const TextStyle(
                      fontSize: 11.5, color: AppColors.textMuted),
                ),
              ],
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 1; i <= 5; i++)
                Container(
                  width: 5,
                  height: 5,
                  margin: const EdgeInsets.only(left: 3),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: i <= source.weight
                        ? AppColors.signal
                        : AppColors.surfaceBorder,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _card({
    required Widget child,
    EdgeInsetsGeometry? padding,
  }) {
    // Material *inside* the decorated box so Switch/ListTile ink + splash
    // paint above the card background (fixes "ink splashes may be invisible"
    // debug warning and restores the M3 ripple). Same taps, pure polish.
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.surfaceCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.surfaceBorder, width: 1),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: padding ?? const EdgeInsets.all(16),
          child: child,
        ),
      ),
    );
  }

  Widget _section(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 26, 4, 10),
      child: Row(
        children: [
          Icon(icon, size: 14, color: AppColors.signal),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              color: AppColors.textMuted,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Container(height: 1, color: AppColors.surfaceBorder),
          ),
        ],
      ),
    );
  }

  Widget _divider() => const Divider(height: 1, indent: 16, endIndent: 16);

  Widget _stat(String label, String value, Color color) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value,
                maxLines: 1,
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                  color: color,
                  fontFamily: 'monospace',
                )),
          ),
          const SizedBox(height: 2),
          Text(label,
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.textMuted,
                letterSpacing: 0.3,
              )),
        ],
      ),
    );
  }

  Future<void> _addSource(ProxyListNotifier notifier) async {
    final url = _customUrlController.text.trim();
    if (url.isEmpty || _isAdding) return;

    setState(() => _isAdding = true);
    AppHaptics.light();

    final result = await notifier.addCustomSource(url);
    if (!mounted) return;
    setState(() => _isAdding = false);

    final (message, ok) = switch (result) {
      CustomSourceResult.added => ('Custom source added', true),
      CustomSourceResult.duplicate => ('This source is already added', true),
      CustomSourceResult.insecureScheme => (
          'Only HTTPS sources are allowed — unencrypted lists can be rewritten in transit',
          false,
        ),
      CustomSourceResult.invalidUrl => (
          'Enter a valid https:// URL',
          false,
        ),
      CustomSourceResult.noProxiesFound => (
          'No proxies found at that URL',
          false,
        ),
    };

    if (result == CustomSourceResult.added ||
        result == CustomSourceResult.duplicate) {
      _customUrlController.clear();
    }
    ok ? AppHaptics.success() : AppHaptics.error();
    // Same message/duration/tap behavior — only the content gets a bounded
    // 180ms fade+slide entrance (M3 snackbar route animation is unchanged).
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: _SnackEntrance(text: message),
      duration: Duration(seconds: ok ? 2 : 4),
    ));
  }

  Future<void> _confirmClear(ProxyListNotifier notifier) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear cached proxies?'),
        content: const Text(
            'Saved scan results will be removed from this device. Your favorites, custom sources and preferences are kept.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.dead),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _clearing = true);
    await notifier.clearCachedData();
    if (!mounted) return;
    setState(() => _clearing = false);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: _SnackEntrance(text: 'Cached data cleared'),
      duration: Duration(seconds: 2),
    ));
  }

  Future<void> _confirmDeleteAll(ProxyListNotifier notifier) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete all local data?'),
        content: const Text(
            'Caches, favorites, custom sources, preferences and update state will all be removed from this device. This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.dead),
            child: const Text('Delete all'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _clearing = true);
    await notifier.deleteAllData();
    if (!mounted) return;
    setState(() => _clearing = false);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: _SnackEntrance(text: 'All local data deleted'),
      duration: Duration(seconds: 2),
    ));
  }

  Future<void> _checkForUpdate() async {
    setState(() {
      _isCheckingUpdate = true;
      _updateCheckError = null;
    });
    AppHaptics.light();

    try {
      final service = ref.read(updateServiceProvider);
      final update = await service.checkForUpdate(force: true);
      if (!mounted) return;
      setState(() => _isCheckingUpdate = false);

      if (update == null) {
        final version = await service.currentVersion;
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:
              _SnackEntrance(text: 'TelePulse v${version ?? "--"} is up to date'),
          duration: const Duration(seconds: 2),
        ));
        return;
      }
      if (!mounted) return;
      final skipped = await service.skippedVersion;
      if (skipped == update.latestVersion) return;
      _showUpdateDialog(update, service);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isCheckingUpdate = false;
        _updateCheckError = snackbarFor(e);
      });
    }
  }

  void _showUpdateDialog(UpdateInfo update, UpdateService service) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.system_update_rounded, color: AppColors.signal, size: 22),
            SizedBox(width: 10),
            Text('Update available'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('v${update.latestVersion} is now available',
                style: const TextStyle(
                    color: AppColors.signal,
                    fontWeight: FontWeight.w600,
                    fontSize: 14)),
            if (update.releaseNotes?.isNotEmpty == true) ...[
              const SizedBox(height: 12),
              const Text('Release notes:',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textMuted)),
              const SizedBox(height: 4),
              Container(
                width: double.maxFinite,
                constraints: const BoxConstraints(maxHeight: 160),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.surfaceElevated,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SingleChildScrollView(
                  child: Text(
                    update.releaseNotes!,
                    style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                        height: 1.5),
                  ),
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Not now',
                style: TextStyle(color: AppColors.textMuted)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              service.skipVersion(update.latestVersion);
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: _SnackEntrance(
                    text:
                        'v${update.latestVersion} hidden until next release'),
                duration: const Duration(seconds: 2),
              ));
            },
            child: const Text('Ignore this version',
                style: TextStyle(color: AppColors.textMuted)),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              _openUrl(update.downloadUrl);
            },
            child: const Text('Download'),
          ),
        ],
      ),
    );
  }

  Future<void> _openUrl(String url) async {
    try {
      AppHaptics.light();
    } catch (_) {}
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    var opened = false;
    try {
      opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      opened = false;
    }
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the link.')),
      );
    }
  }
}

/// Shared-controller stagger (mirrors home/proxies): bounded, first ~10.
/// Returns [child] untouched when reduced motion is on.
class _SettingsEntrance extends StatelessWidget {
  final int index;
  final Animation<double> animation;
  final Widget child;

  const _SettingsEntrance({
    required this.index,
    required this.animation,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.of(context).disableAnimations) return child;
    final double start = (index * 0.06).clamp(0.0, 0.6);
    final CurvedAnimation curved = CurvedAnimation(
      parent: animation,
      curve: Interval(start, (start + 0.5).clamp(0.0, 1.0),
          curve: Curves.easeOutCubic),
    );
    return AnimatedBuilder(
      animation: curved,
      builder: (context, child) {
        return Opacity(
          opacity: curved.value,
          child: Transform.translate(
            offset: Offset(0, 22 * (1 - curved.value)),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}

/// Bounded 180ms fade+slide for snackbar *content* only.
/// The M3 snackbar route animation is untouched — same duration/behavior.
class _SnackEntrance extends StatefulWidget {
  final String text;

  const _SnackEntrance({required this.text});

  @override
  State<_SnackEntrance> createState() => _SnackEntranceState();
}

class _SnackEntranceState extends State<_SnackEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    )..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.of(context).disableAnimations) {
      return Text(widget.text);
    }
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final double t =
            Curves.easeOut.transform(_controller.value.clamp(0.0, 1.0));
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, 8 * (1 - t)),
            child: Text(widget.text),
          ),
        );
      },
    );
  }
}

class _AboutCard extends StatelessWidget {
  const _AboutCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.surfaceCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.surfaceBorder, width: 1),
      ),
      child: Material(
        type: MaterialType.transparency,
        borderRadius: BorderRadius.circular(14),
        child: Column(
          children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 16),
            child: Column(
              children: [
                const AnimatedBrandMark(size: 64, active: true),
                const SizedBox(height: 14),
                const Text(
                  'TelePulse',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.4,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.signal.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: AppColors.signal.withValues(alpha: 0.35)),
                  ),
                  child: Text(
                    'v${AppMeta.version} (build ${AppMeta.buildNumber})',
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'monospace',
                      color: AppColors.signal,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'MTProto proxy discovery — find signal anywhere.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.5,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          _AboutRow(
            icon: Icons.code_rounded,
            title: 'Open source (MIT)',
            subtitle: 'github.com/krsnaSuraj/TelePulse',
            onTap: () => _AboutCard.openUrl(
                context, 'https://github.com/krsnaSuraj/TelePulse'),
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          _AboutRow(
            icon: Icons.privacy_tip_outlined,
            title: 'Privacy',
            subtitle: 'Collects nothing — see what leaves your phone',
            onTap: () => _AboutCard.showPrivacy(context),
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 14, 20, 16),
            child: Text(
              'Built with Flutter · Proxy lists curated by SoliSpirit, kort0881, Grim1313, iwh3n and ALIILAPRO.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                height: 1.6,
                color: AppColors.textFaint,
              ),
            ),
          ),
          ],
        ),
      ),
    );
  }

  static Future<void> openUrl(BuildContext context, String url) async {
    try {
      AppHaptics.light();
    } catch (_) {}
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    var opened = false;
    try {
      opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      opened = false;
    }
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the link.')),
      );
    }
  }

  static void showPrivacy(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Privacy at a glance'),
        content: const SingleChildScrollView(
          child: Text(
            '• Collects nothing: no analytics, no accounts, no identifiers.\n\n'
            '• Leaves your phone only to fetch proxy lists (GitHub/CDN), check updates manually (GitHub API), and hand a proxy to Telegram when you tap.\n\n'
            '• Cache, favorites and sources stay on-device and are excluded from cloud backup.\n\n'
            '• If Telegram is missing, the proxy link is copied to your clipboard — clear it if that concerns you.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

class _AboutRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _AboutRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, size: 18, color: AppColors.signal),
      title: Text(title, style: const TextStyle(fontSize: 14)),
      subtitle: Text(subtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style:
              const TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
      trailing: const Icon(Icons.chevron_right_rounded,
          color: AppColors.textMuted, size: 18),
      dense: true,
      onTap: () {
        AppHaptics.selection();
        onTap();
      },
    );
  }
}
