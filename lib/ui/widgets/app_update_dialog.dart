import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/services/app_update_service.dart';
import '../../l10n/app_localizations.dart';
import '../../util/app_distribution.dart';
import '../../util/platform_detection.dart';
import 'track_selector_dialog.dart';

const _installChannel = MethodChannel('org.moonfin.androidtv/update');

/// Checks for an update and shows the dialog or an appropriate snackbar.
/// Returns true if an update was found and the dialog was shown.
Future<void> checkAndShowUpdateResult(BuildContext context) async {
  final result =
      await GetIt.instance<AppUpdateService>().checkForUpdateNowDetailed();
  if (!context.mounted) return;

  final update = result.update;
  if (update != null) {
    await showAppUpdateDialog(context, update);
    return;
  }

  if (!context.mounted) return;
  final l10n = AppLocalizations.of(context);
  final message = switch (result.status) {
    DesktopUpdateCheckStatus.upToDate => l10n.youAreUpToDate,
    DesktopUpdateCheckStatus.checkFailed => l10n.couldNotCheckForUpdates,
    DesktopUpdateCheckStatus.noMatchingAsset => l10n.noCompatibleUpdate,
    DesktopUpdateCheckStatus.unsupportedPlatform => l10n.updateChecksNotSupported,
    DesktopUpdateCheckStatus.disabledByPreference => l10n.updateNotificationsDisabled,
    DesktopUpdateCheckStatus.rateLimited => l10n.pleaseWaitBeforeChecking,
    DesktopUpdateCheckStatus.alreadyNotified => l10n.latestUpdateAlreadyShown,
    DesktopUpdateCheckStatus.updateAvailable => l10n.updateAvailable,
  };
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(message), duration: const Duration(seconds: 4)),
  );
}

Future<void> showAppUpdateDialog(
  BuildContext context,
  DesktopUpdateInfo update,
) async {
  final l10n = AppLocalizations.of(context);

  final opensBrowser = AppDistribution.opensReleasesInBrowser;
  final downloadLabel =
      opensBrowser ? l10n.openReleasesPage : l10n.download;

  final choice = await showStyledPlayerDialog<String>(
    context,
    title: l10n.updateAvailableTitle(update.version),
    showCancel: true,
    builder: (ctx) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!PlatformDetection.isTV)
          _UpdateOption(
            icon: Icons.download_rounded,
            label: downloadLabel,
            value: 'download',
          ),
        _UpdateOption(
          icon: Icons.article_outlined,
          label: l10n.readReleaseNotes,
          value: 'notes',
        ),
      ],
    ),
  );

  if (choice == null || !context.mounted) return;

  if (choice == 'notes') {
    await launchUrl(
      Uri.parse(update.releaseNotesUrl),
      mode: LaunchMode.externalApplication,
    );
    return;
  }

  if (opensBrowser) {
    await launchUrl(
      update.downloadUri,
      mode: LaunchMode.externalApplication,
    );
    return;
  }

  if (!context.mounted) return;
  await _startInAppDownload(context, update);
}

Future<void> _startInAppDownload(
  BuildContext context,
  DesktopUpdateInfo update,
) async {
  final l10n = AppLocalizations.of(context);
  final progress = ValueNotifier<double>(-1);
  String? errorMessage;
  String? donePath;

  final completer = Completer<void>();

  final downloadStream = GetIt.instance<AppUpdateService>().downloadUpdate(update);

  late final StreamSubscription<dynamic> sub;
  sub = downloadStream.listen(
    (event) {
      if (event is DownloadProgressEvent) {
        progress.value = event.fraction;
      } else if (event is DownloadDoneEvent) {
        donePath = event.filePath;
        completer.complete();
        sub.cancel();
      } else if (event is DownloadFailedEvent) {
        errorMessage = event.error;
        completer.complete();
        sub.cancel();
      }
    },
    onError: (dynamic e) {
      errorMessage = e.toString();
      completer.complete();
      sub.cancel();
    },
    onDone: () {
      if (!completer.isCompleted) completer.complete();
    },
  );

  if (!context.mounted) {
    sub.cancel();
    return;
  }

  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogCtx) => _DownloadProgressDialog(
      progressNotifier: progress,
      label: l10n.downloadingUpdate,
      onCompleted: completer.future,
      onCancel: () {
        sub.cancel();
        completer.complete();
        Navigator.of(dialogCtx).pop();
      },
    ),
  );

  if (errorMessage != null) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.updateDownloadFailed),
          duration: const Duration(seconds: 5),
        ),
      );
    }
    return;
  }

  final path = donePath;
  if (path == null) return;
  if (!context.mounted) return;

  if (AppDistribution.isAndroidApkBuild) {
    await _installApkAndroid(path, context);
  } else {
    await _openFileDesktop(path, context);
  }
}

Future<void> _installApkAndroid(String path, BuildContext context) async {
  try {
    final canInstall = await _installChannel
        .invokeMethod<bool>('canInstallPackages') ?? false;
    if (!canInstall) {
      await _installChannel.invokeMethod<void>('requestInstallPermission');
      return;
    }
    await _installChannel.invokeMethod<void>('installApk', {'path': path});
  } catch (_) {
    if (context.mounted) {
      final l10n = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.updateDownloadFailed),
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }
}

Future<void> _openFileDesktop(String path, BuildContext context) async {
  try {
    if (PlatformDetection.isMacOS) {
      await Process.run('open', [path]);
    } else if (PlatformDetection.isWindows) {
      await Process.run('explorer', [path]);
    } else {
      await launchUrl(
        Uri.file(path),
        mode: LaunchMode.externalApplication,
      );
    }
  } catch (_) {
    if (context.mounted) {
      final l10n = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.updateDownloadFailed),
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }
}

class _UpdateOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _UpdateOption({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => Navigator.of(context).pop(value),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        child: Row(
          children: [
            Icon(icon, size: 22, color: Colors.white70),
            const SizedBox(width: 16),
            Text(
              label,
              style: const TextStyle(fontSize: 15, color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }
}

class _DownloadProgressDialog extends StatefulWidget {
  final ValueNotifier<double> progressNotifier;
  final String label;
  final Future<void> onCompleted;
  final VoidCallback onCancel;

  const _DownloadProgressDialog({
    required this.progressNotifier,
    required this.label,
    required this.onCompleted,
    required this.onCancel,
  });

  @override
  State<_DownloadProgressDialog> createState() =>
      _DownloadProgressDialogState();
}

class _DownloadProgressDialogState extends State<_DownloadProgressDialog> {
  @override
  void initState() {
    super.initState();
    widget.onCompleted.then((_) {
      if (mounted) Navigator.of(context).pop();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      backgroundColor: Theme.of(context).colorScheme.surface,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          Text(widget.label),
          const SizedBox(height: 20),
          ValueListenableBuilder<double>(
            valueListenable: widget.progressNotifier,
            builder: (_, fraction, _) {
              return LinearProgressIndicator(
                value: fraction < 0 ? null : fraction.clamp(0.0, 1.0),
              );
            },
          ),
          const SizedBox(height: 8),
        ],
      ),
      actions: [
        TextButton(
          onPressed: widget.onCancel,
          child: Text(l10n.cancel),
        ),
      ],
    );
  }
}
