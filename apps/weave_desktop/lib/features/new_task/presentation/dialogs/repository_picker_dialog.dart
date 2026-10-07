import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;

import '../../../../core/design_system/design_system.dart';
import '../../domain/loaded_repository.dart';
import '../../domain/repository_picker_platform.dart';

enum _RepositorySource { local, remote }

enum _CloneProtocol { https, ssh }

/// Opens the repository picker and returns a validated local repository.
Future<LoadedRepository?> showRepositoryPickerDialog({
  required BuildContext context,
  required List<String> recentRepositories,
  required String initialPath,
  required RepositoryPickerPlatform platform,
  required Future<LoadedRepository> Function(String directory) loadRepository,
  required Future<LoadedRepository> Function(String url, String parentDirectory) cloneRepository,
}) => showDialog<LoadedRepository>(
  context: context,
  traversalEdgeBehavior: TraversalEdgeBehavior.closedLoop,
  requestFocus: true,
  builder: (BuildContext context) => _RepositoryPickerDialog(
    recentRepositories: recentRepositories,
    initialPath: initialPath,
    platform: platform,
    loadRepository: loadRepository,
    cloneRepository: cloneRepository,
  ),
);

class _RepositoryPickerDialog extends StatefulWidget {
  const _RepositoryPickerDialog({
    required this.recentRepositories,
    required this.initialPath,
    required this.platform,
    required this.loadRepository,
    required this.cloneRepository,
  });

  final List<String> recentRepositories;
  final String initialPath;
  final RepositoryPickerPlatform platform;
  final Future<LoadedRepository> Function(String directory) loadRepository;
  final Future<LoadedRepository> Function(String url, String parentDirectory) cloneRepository;

  @override
  State<_RepositoryPickerDialog> createState() => _RepositoryPickerDialogState();
}

class _RepositoryPickerDialogState extends State<_RepositoryPickerDialog> {
  final TextEditingController _url = TextEditingController();

  /// Parent folder for a clone, chosen in Finder.
  String? _destination;
  late final StreamSubscription<String> _dropSubscription;
  late final StreamSubscription<bool> _hoverSubscription;

  /// A folder is being dragged over the window.
  bool _dragHovering = false;
  _RepositorySource _source = _RepositorySource.local;
  _CloneProtocol _cloneProtocol = _CloneProtocol.https;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _dropSubscription = widget.platform.droppedDirectories.listen(_useDroppedDirectory);
    _hoverSubscription = widget.platform.dragHovering.listen((bool hovering) {
      if (mounted) {
        setState(() => _dragHovering = hovering);
      }
    });
  }

  @override
  void dispose() {
    _dropSubscription.cancel();
    _hoverSubscription.cancel();
    _url.dispose();
    super.dispose();
  }

  void _selectSource(_RepositorySource source) {
    setState(() {
      _source = source;
      _error = null;
    });
  }

  /// The folder picked in Finder, or null when cancelled or when the native
  /// picker is unavailable (then the dialog says so).
  Future<String?> _pickDirectory() async {
    try {
      return await widget.platform.chooseDirectory();
    } on DirectoryPickerUnavailableException {
      if (mounted) {
        setState(() => _error = 'Finder could not open. Quit and reopen Weave, then try again.');
      }
      return null;
    }
  }

  /// Opens Finder and uses the chosen folder right away.
  Future<void> _chooseLocalDirectory() async {
    final String? directory = await _pickDirectory();
    if (directory == null || !mounted) {
      return;
    }
    await _loadLocal(directory);
  }

  Future<void> _chooseDestination() async {
    final String? directory = await _pickDirectory();
    if (directory == null || !mounted) {
      return;
    }
    setState(() {
      _destination = directory;
      _error = null;
    });
  }

  void _useDroppedDirectory(String directory) {
    if (!mounted || _busy) {
      return;
    }
    setState(() {
      _source = _RepositorySource.local;
      _error = null;
    });
    unawaited(_loadLocal(directory));
  }

  Future<void> _loadLocal(String directory) => _complete(() => widget.loadRepository(directory));

  Future<void> _cloneRemote() async {
    final String url = _url.text.trim();
    if (url.isEmpty) {
      setState(() => _error = 'Enter a Git repository URL.');
      return;
    }
    final bool matchesProtocol = switch (_cloneProtocol) {
      _CloneProtocol.https => url.startsWith('https://'),
      _CloneProtocol.ssh => url.startsWith('ssh://') || RegExp(r'^[^\s/@]+@[^\s/:]+:[^\s]+$').hasMatch(url),
    };
    if (!matchesProtocol) {
      setState(() => _error = _cloneProtocol == _CloneProtocol.https ? 'Enter an HTTPS repository URL.' : 'Enter an SSH URL such as git@host:owner/repository.git.');
      return;
    }
    String? parentDirectory = _destination;
    if (parentDirectory == null) {
      parentDirectory = await _pickDirectory();
      if (parentDirectory == null || !mounted) {
        return;
      }
      setState(() => _destination = parentDirectory);
    }
    final String destination = parentDirectory;
    await _complete(() => widget.cloneRepository(url, destination));
  }

  Future<void> _complete(Future<LoadedRepository> Function() operation) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final LoadedRepository loaded = await operation();
      if (mounted) {
        Navigator.of(context).pop(loaded);
      }
    } on Object catch (error) {
      if (mounted) {
        setState(() => _error = _describe(error));
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool local = _source == _RepositorySource.local;
    return Dialog(
      backgroundColor: WeaveColors.surface.withValues(alpha: 0),
      elevation: 0,
      child: WeaveDialog(
        title: 'Choose repository',
        subtitle: local ? 'Use a Git repository already cloned on this Mac.' : 'Clone a remote Git repository into a folder you choose.',
        onClose: _busy ? () {} : null,
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Align(
              alignment: Alignment.centerLeft,
              child: WeaveSegmentedControl<_RepositorySource>(
                semanticLabel: 'Repository source',
                segments: const <WeaveSegment<_RepositorySource>>[
                  WeaveSegment<_RepositorySource>(value: _RepositorySource.local, label: 'Local folder', icon: WeaveIcons.folder),
                  WeaveSegment<_RepositorySource>(value: _RepositorySource.remote, label: 'Clone from URL', icon: WeaveIcons.download),
                ],
                value: _source,
                onChanged: _busy ? null : _selectSource,
              ),
            ),
            const SizedBox(height: WeaveSpacing.s20),
            if (local) ..._localFields() else ..._remoteFields(),
          ],
        ),
        // A local folder is used as soon as it is chosen, so only cloning
        // needs a confirming action.
        actions: <Widget>[
          WeaveButton(label: 'Cancel', onPressed: _busy ? null : () => Navigator.of(context).pop()),
          if (!local) WeaveButton.primary(key: const Key('repository-clone'), label: _busy ? 'Cloning…' : 'Clone repository', onPressed: _busy ? null : _cloneRemote),
        ],
      ),
    );
  }

  List<Widget> _localFields() => <Widget>[
    // One target, like an image upload: click to open Finder, or drop a folder.
    WeaveCard(
      key: const Key('repository-browse'),
      surface: _dragHovering ? WeaveSurface.selected : WeaveSurface.sunken,
      padding: const EdgeInsets.symmetric(horizontal: WeaveSpacing.s24, vertical: WeaveSpacing.s32),
      onTap: _busy ? null : _chooseLocalDirectory,
      child: Column(
        children: <Widget>[
          WeaveIcon(_dragHovering ? WeaveIcons.download : WeaveIcons.folder, size: WeaveSpacing.s28, color: WeaveColors.purpleSoft),
          const SizedBox(height: WeaveSpacing.s12),
          Text(
            _busy
                ? 'Checking the repository…'
                : _dragHovering
                ? 'Drop the folder to use it'
                : 'Click to choose a folder in Finder',
            style: WeaveTypography.bodyStrong,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: WeaveSpacing.s4),
          Text('or drag a cloned Git repository folder here', style: WeaveTypography.caption, textAlign: TextAlign.center),
        ],
      ),
    ),
    if (_error case final String error) ...<Widget>[
      const SizedBox(height: WeaveSpacing.s12),
      Text(
        error,
        key: const Key('repository-error'),
        style: WeaveTypography.bodySmall.copyWith(color: WeaveColors.red),
      ),
    ],
    if (widget.recentRepositories.isNotEmpty) ...<Widget>[
      const SizedBox(height: WeaveSpacing.s20),
      Text('RECENTLY USED', style: WeaveTypography.overline),
      const SizedBox(height: WeaveSpacing.s8),
      for (final String repository in widget.recentRepositories) ...<Widget>[
        WeaveCard(
          key: ValueKey<String>('repository-recent-$repository'),
          surface: repository == widget.initialPath ? WeaveSurface.selected : WeaveSurface.elevated,
          padding: const EdgeInsets.symmetric(horizontal: WeaveSpacing.s16, vertical: WeaveSpacing.s10),
          onTap: _busy ? null : () => _loadLocal(repository),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(path.basename(repository), style: WeaveTypography.bodyStrong),
              Text(repository, style: WeaveTypography.caption, maxLines: 1, overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
        const SizedBox(height: WeaveSpacing.s10),
      ],
    ],
  ];

  List<Widget> _remoteFields() => <Widget>[
    Align(
      alignment: Alignment.centerLeft,
      child: WeaveSegmentedControl<_CloneProtocol>(
        semanticLabel: 'Git clone protocol',
        segments: const <WeaveSegment<_CloneProtocol>>[
          WeaveSegment<_CloneProtocol>(value: _CloneProtocol.https, label: 'HTTPS', icon: WeaveIcons.atSign),
          WeaveSegment<_CloneProtocol>(value: _CloneProtocol.ssh, label: 'SSH', icon: WeaveIcons.terminal),
        ],
        value: _cloneProtocol,
        onChanged: _busy
            ? null
            : (_CloneProtocol value) {
                setState(() {
                  _cloneProtocol = value;
                  _url.clear();
                  _error = null;
                });
              },
      ),
    ),
    const SizedBox(height: WeaveSpacing.s16),
    WeaveTextField(
      key: const Key('repository-url'),
      controller: _url,
      label: 'Repository URL',
      hintText: _cloneProtocol == _CloneProtocol.https ? 'https://github.com/owner/repository.git' : 'git@github.com:owner/repository.git',
      helperText: _cloneProtocol == _CloneProtocol.https ? 'Public repositories need no setup. Private repositories use Git credentials already configured on this Mac.' : 'Weave uses your existing SSH agent and never stores the private key.',
      errorText: _error,
      prefixIcon: WeaveIcons.gitBranch,
      enabled: !_busy,
      autofocus: true,
      onChanged: (String _) => setState(() => _error = null),
      onSubmitted: (String _) => _cloneRemote(),
    ),
    if (_cloneProtocol == _CloneProtocol.ssh) ...<Widget>[
      const SizedBox(height: WeaveSpacing.s12),
      WeaveCard(
        key: const Key('ssh-setup'),
        surface: WeaveSurface.sunken,
        padding: const EdgeInsets.all(WeaveSpacing.s14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('SSH not set up yet?', style: WeaveTypography.bodyStrong),
            const SizedBox(height: WeaveSpacing.s4),
            Text('Create a key in Terminal, add the public key to your Git provider, then retry. Weave does not read or store the key.', style: WeaveTypography.caption),
            const SizedBox(height: WeaveSpacing.s10),
            WeaveButton(
              key: const Key('copy-ssh-setup'),
              label: 'Copy setup commands',
              icon: WeaveIcons.copy,
              size: WeaveButtonSize.small,
              onPressed: () async {
                await Clipboard.setData(const ClipboardData(text: 'ssh-keygen -t ed25519\nssh-add ~/.ssh/id_ed25519'));
                if (mounted) {
                  showWeaveToast(context, message: 'SSH setup commands copied.', tone: WeaveToastTone.success);
                }
              },
            ),
          ],
        ),
      ),
    ],
    const SizedBox(height: WeaveSpacing.s16),
    Text('Clone into', style: WeaveTypography.label),
    const SizedBox(height: WeaveSpacing.s8),
    WeaveCard(
      key: const Key('repository-destination'),
      surface: WeaveSurface.field,
      padding: const EdgeInsets.fromLTRB(WeaveSpacing.s14, WeaveSpacing.s8, WeaveSpacing.s8, WeaveSpacing.s8),
      child: Row(
        children: <Widget>[
          const WeaveIcon(WeaveIcons.folder, size: WeaveIconSize.compact, color: WeaveColors.textDisabled),
          const SizedBox(width: WeaveSpacing.s10),
          Expanded(
            child: Text(
              _destination ?? 'No folder chosen — Finder opens when you clone',
              style: _destination == null ? WeaveTypography.body.copyWith(color: WeaveColors.textDisabled) : WeaveTypography.body.copyWith(color: WeaveColors.textPrimary),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: WeaveSpacing.s8),
          WeaveButton(key: const Key('repository-destination-browse'), label: 'Choose…', size: WeaveButtonSize.small, onPressed: _busy ? null : _chooseDestination),
        ],
      ),
    ),
    const SizedBox(height: WeaveSpacing.s6),
    Text('Weave creates a new project folder inside this location.', style: WeaveTypography.caption),
  ];

  static String _describe(Object error) {
    final String message = error.toString();
    final int separator = message.indexOf(': ');
    return separator < 0 ? message : message.substring(separator + 2);
  }
}
