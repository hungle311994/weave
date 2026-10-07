import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:weave_agents/weave_agents.dart';

import '../../../core/design_system/design_system.dart';
import 'agents_controller.dart';
import 'dialogs/add_account_dialog.dart';
import 'dialogs/agent_gallery_dialog.dart';

/// Every agent from the presets and `agents.json`: whether it is installed
/// and signed in, its plan usage, and the default agent per role.
class AgentsPage extends StatefulWidget {
  const AgentsPage({required this.controller, super.key});

  final AgentsController controller;

  @override
  State<AgentsPage> createState() => _AgentsPageState();
}

class _AgentsPageState extends State<AgentsPage> {
  AgentsController get controller => widget.controller;

  /// Re-checks sign-in when the user comes back to Weave, e.g. from Terminal.
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: () => controller.refresh());
    // Sign-in is re-checked on every visit (local commands, no model). Plan
    // usage is read only the first time the screen opens after launch;
    // Refresh usage re-reads it. After the first frame, because both notify.
    WidgetsBinding.instance.addPostFrameCallback((Duration _) async {
      if (mounted) {
        await controller.refresh();
      }
      if (mounted) {
        await controller.ensurePlanUsage();
      }
    });
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  Future<void> _addAccount(AgentAdapter adapter) async {
    final String? name = await showAddAccountDialog(context, agentName: adapter.displayName);
    if (name == null || !mounted) {
      return;
    }
    try {
      final AgentAccount account = await controller.addAccount(adapter.id, name);
      if (mounted) {
        showWeaveToast(context, message: 'Sign in to ${adapter.displayName} · ${account.name} in the Terminal window that opened, then come back to Weave.', tone: WeaveToastTone.success);
      }
    } on Object catch (error) {
      if (mounted) {
        showWeaveToast(context, message: 'Could not add the account: ${error is StateError ? error.message : error}', tone: WeaveToastTone.danger);
      }
    }
  }

  Future<void> _signIn(AgentAdapter adapter) async {
    try {
      if (await controller.signIn(adapter.id) && mounted) {
        showWeaveToast(context, message: 'Finish signing in to ${adapter.displayName} in Terminal, then come back to Weave.', tone: WeaveToastTone.success);
      }
    } on Object catch (error) {
      if (mounted) {
        showWeaveToast(context, message: error is StateError ? error.message : 'Terminal could not be opened: $error', tone: WeaveToastTone.danger);
      }
    }
  }

  Future<void> _removeAccount(AgentAdapter adapter) async {
    final bool confirmed =
        await showWeaveDialog<bool>(
          context: context,
          title: 'Remove ${adapter.displayName}?',
          subtitle: 'Weave deletes this account\'s configuration folder, which signs it out of the agent on this Mac. Your subscription and workflow history are not affected.',
          body: const SizedBox.shrink(),
          accent: WeaveColors.redStrong,
          actions: <Widget>[
            WeaveButton(label: 'Keep', onPressed: () => Navigator.of(context).pop(false)),
            WeaveButton.danger(key: const Key('confirm-remove-account'), label: 'Remove account', onPressed: () => Navigator.of(context).pop(true)),
          ],
        ) ??
        false;
    if (confirmed && mounted) {
      await controller.removeAccount(adapter.id);
    }
  }

  Future<void> _addAgent() async {
    final AgentDefinition? definition = await showAgentGalleryDialog(context, existingIds: <String>{for (final AgentAdapter adapter in controller.agents) adapter.id}, isInstalled: controller.isInstalled);
    if (definition == null || !mounted) {
      return;
    }
    await controller.addAgent(definition);
    if (mounted) {
      showWeaveToast(context, message: '${definition.displayName} was added to agents.json.', tone: WeaveToastTone.success);
    }
  }

  Future<void> _removeAgent(AgentAdapter adapter) async {
    final bool confirmed =
        await showWeaveDialog<bool>(
          context: context,
          title: 'Remove ${adapter.displayName}?',
          subtitle: 'It is removed from agents.json. Workflows that already ran keep their history; a built-in agent it replaced comes back.',
          body: const SizedBox.shrink(),
          accent: WeaveColors.redStrong,
          actions: <Widget>[
            WeaveButton(label: 'Keep', onPressed: () => Navigator.of(context).pop(false)),
            WeaveButton.danger(key: const Key('confirm-remove-agent'), label: 'Remove agent', onPressed: () => Navigator.of(context).pop(true)),
          ],
        ) ??
        false;
    if (confirmed && mounted) {
      await controller.removeAgent(adapter.id);
    }
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(WeaveLayout.pageGutter, WeaveLayout.windowContentTopPadding, WeaveSpacing.s28, WeaveSpacing.s40),
    children: <Widget>[
      WeavePageHeader(
        breadcrumb: const <String>['Workspace', 'Agents'],
        title: 'Agents',
        subtitle: 'Command-line agents Weave can run: their sign-in, plan usage, and who handles each stage by default.',
        trailing: Wrap(
          spacing: WeaveSpacing.s12,
          runSpacing: WeaveSpacing.s8,
          children: <Widget>[
            WeaveButton(
              key: const Key('refresh-usage'),
              label: controller.refreshingPlanUsage ? 'Refreshing…' : 'Refresh usage',
              icon: WeaveIcons.refresh,
              onPressed: controller.refreshingPlanUsage || controller.planUsageAgents.isEmpty ? null : controller.refreshPlanUsage,
            ),
            WeaveButton.primary(key: const Key('add-agent'), label: 'Add agent', icon: WeaveIcons.plus, onPressed: _addAgent),
          ],
        ),
      ),
      const SizedBox(height: WeaveSpacing.s32),
      LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final int maximumGridColumns = constraints.maxWidth >= WeaveLayout.agentsSideColumnBreakpoint ? WeaveLayout.agentGridMaxColumns : 2;
          final Widget main = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              LayoutBuilder(
                builder: (BuildContext context, BoxConstraints grid) => _AgentGrid(width: grid.maxWidth, maximumColumns: maximumGridColumns, cards: <Widget>[for (final AgentAdapter adapter in controller.agents) _cardFor(adapter)]),
              ),
            ],
          );
          final Widget health = _ConnectionHealth(controller: controller);
          if (constraints.maxWidth >= WeaveLayout.agentsSideColumnBreakpoint) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(child: main),
                const SizedBox(width: WeaveSpacing.s24),
                SizedBox(width: WeaveLayout.newTaskPreviewWidth, child: health),
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              main,
              const SizedBox(height: WeaveSpacing.s24),
              health,
            ],
          );
        },
      ),
    ],
  );

  Widget _cardFor(AgentAdapter adapter) => _AgentCard(
    key: ValueKey<String>('agent-card-${adapter.id}'),
    adapter: adapter,
    availability: controller.availabilityOf(adapter.id),
    account: controller.accountOf(adapter.id),
    onRemove: adapter.account != null ? () => _removeAccount(adapter) : (controller.isCustom(adapter.id) ? () => _removeAgent(adapter) : null),
    onAddAccount: adapter.supportsAccounts && (controller.availabilityOf(adapter.id)?.isInstalled ?? false) ? () => _addAccount(adapter) : null,
    onSignIn: () => _signIn(adapter),
    planUsage: _PlanUsageSection(adapter: adapter, usage: controller.planUsageOf(adapter.id), error: controller.planUsageErrorOf(adapter.id), refreshing: controller.refreshingPlanUsage),
  );
}

/// Agent cards in as many columns as the width allows (at least
/// [WeaveLayout.agentCardMinWidth] each, at most [WeaveLayout.agentGridMaxColumns]);
/// cards in one row share its height.
class _AgentGrid extends StatelessWidget {
  const _AgentGrid({required this.width, required this.maximumColumns, required this.cards});

  final double width;
  final int maximumColumns;
  final List<Widget> cards;

  @override
  Widget build(BuildContext context) {
    const double gap = WeaveSpacing.s16;
    final int columns = ((width + gap) / (WeaveLayout.agentCardMinWidth + gap)).floor().clamp(1, maximumColumns);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (int start = 0; start < cards.length; start += columns) ...<Widget>[
          if (start > 0) const SizedBox(height: gap),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                for (int column = 0; column < columns; column++) ...<Widget>[
                  if (column > 0) const SizedBox(width: gap),
                  Expanded(child: start + column < cards.length ? cards[start + column] : const SizedBox.shrink()),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// How ready an agent is, as a status pill.
(String, WeaveTone) _readiness(AgentAvailability? availability) => switch (availability) {
  null => ('Checking…', WeaveTone.neutral),
  AgentAvailability(isAvailable: true) => ('Ready', WeaveTone.success),
  AgentAvailability(needsSignIn: true) => ('Sign-in required', WeaveTone.warning),
  AgentAvailability(isInstalled: false) => ('Not installed', WeaveTone.warning),
  _ => ('Setup required', WeaveTone.warning),
};

class _AgentCard extends StatelessWidget {
  const _AgentCard({required this.adapter, required this.availability, required this.account, required this.onRemove, required this.onAddAccount, required this.onSignIn, required this.planUsage, super.key});

  final AgentAdapter adapter;
  final AgentAvailability? availability;

  /// Who the agent is signed in as, when it reports it.
  final AgentAccountInfo? account;

  /// Set for agents from `agents.json` and for extra accounts, which can be removed.
  final VoidCallback? onRemove;

  /// Set when another account of this agent can be added.
  final VoidCallback? onAddAccount;

  /// Opens the agent's sign-in in Terminal.
  final VoidCallback onSignIn;

  /// Shown for a ready agent.
  final Widget planUsage;

  @override
  Widget build(BuildContext context) {
    final AgentAvailability? availability = this.availability;
    final AgentDefinition? definition = switch (adapter) {
      CommandAgentAdapter(:final AgentDefinition definition) => definition,
      _ => null,
    };
    final bool ready = availability?.isAvailable ?? false;
    final String? signIn = ready ? null : availability?.signInCommand;
    final List<AgentInstallOption> installOptions = availability != null && !availability.isInstalled ? definition?.installOptions ?? const <AgentInstallOption>[] : const <AgentInstallOption>[];
    final BrandMark? brand = BrandMark.byName(definition?.brand);
    final (String status, WeaveTone tone) = _readiness(availability);
    return WeaveCard(
      padding: const EdgeInsets.all(WeaveSpacing.s20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              WeaveCard(
                surface: WeaveSurface.sunken,
                radius: WeaveRadii.control + WeaveSpacing.s2,
                borderColor: WeaveColors.agentTile,
                padding: const EdgeInsets.all(WeaveSpacing.s10),
                child: brand == null ? const WeaveIcon(WeaveIcons.bot, size: WeaveSpacing.s28) : BrandIcon(brand, size: WeaveSpacing.s28),
              ),
              const SizedBox(width: WeaveSpacing.s14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(adapter.displayName, style: WeaveTypography.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                    // The plan joins the vendor so a long email keeps a line of its own.
                    Text(<String>[definition?.vendor ?? definition?.executable ?? adapter.id, ?_planName(account?.plan)].join(' · '), key: Key('agent-vendor-${adapter.id}'), style: WeaveTypography.caption, maxLines: 1, overflow: TextOverflow.ellipsis),
                    if (_accountLine(account, availability) case final String line) ...<Widget>[
                      const SizedBox(height: WeaveSpacing.s2),
                      Text(
                        line,
                        key: Key('agent-account-${adapter.id}'),
                        style: WeaveTypography.caption.copyWith(color: WeaveColors.textSecondary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              if (onRemove != null)
                WeaveIconButton(
                  key: Key(adapter.account != null ? 'remove-account-${adapter.id}' : 'remove-agent-${adapter.id}'),
                  icon: WeaveIcons.trash,
                  tooltip: 'Remove ${adapter.displayName}',
                  iconSize: WeaveIconSize.compact,
                  onPressed: onRemove,
                ),
            ],
          ),
          const SizedBox(height: WeaveSpacing.s20),
          WeaveStatusPill(key: Key('agent-status-${adapter.id}'), label: status, tone: tone),
          if (!ready && availability?.reason != null) ...<Widget>[const SizedBox(height: WeaveSpacing.s8), Text(availability!.reason!, style: WeaveTypography.caption)],
          const SizedBox(height: WeaveSpacing.s18),
          Text('MODEL', style: WeaveTypography.overline),
          const SizedBox(height: WeaveSpacing.s4),
          Text(
            definition?.model ?? 'CLI default',
            style: WeaveTypography.bodySmall.copyWith(color: WeaveColors.textPrimary, fontWeight: WeaveTypography.medium),
          ),
          if (ready) ...<Widget>[const SizedBox(height: WeaveSpacing.s18), Text('PLAN USAGE', style: WeaveTypography.overline), const SizedBox(height: WeaveSpacing.s8), planUsage],
          if (installOptions.isNotEmpty) ...<Widget>[
            const SizedBox(height: WeaveSpacing.s14),
            for (final (int index, AgentInstallOption option) in installOptions.indexed)
              _InstallCommandRow(
                agentId: adapter.id,
                index: index,
                option: option,
                showLabel: installOptions.length > 1,
                onCopy: () => _copyCommand(context, option.commandText, 'Install command copied. Run it in Terminal, then come back to Weave.'),
              ),
          ],
          if (signIn != null) ...<Widget>[
            const SizedBox(height: WeaveSpacing.s14),
            // Weave never asks for passwords: the agent signs in through its
            // own command, in Terminal, and keeps the credentials itself.
            Row(
              children: <Widget>[
                WeaveButton.primary(key: Key('sign-in-${adapter.id}'), label: 'Sign in', icon: WeaveIcons.terminal, size: WeaveButtonSize.small, onPressed: onSignIn),
                const SizedBox(width: WeaveSpacing.s8),
                WeaveIconButton(
                  key: Key('copy-sign-in-${adapter.id}'),
                  icon: WeaveIcons.copy,
                  tooltip: 'Copy sign-in command',
                  size: WeaveSpacing.s28,
                  iconSize: WeaveIconSize.compact,
                  onPressed: () => _copyCommand(context, signIn, 'Sign-in command copied. Run it in Terminal, then come back to Weave.'),
                ),
              ],
            ),
          ],
          if (onAddAccount != null) ...<Widget>[
            const Spacer(),
            const SizedBox(height: WeaveSpacing.s16),
            WeaveButton(key: Key('add-account-${adapter.id}'), label: 'Add account', icon: WeaveIcons.plus, size: WeaveButtonSize.small, onPressed: onAddAccount),
          ],
        ],
      ),
    );
  }
}

/// The signed-in email, "Not signed in", or `null` when unknown.
String? _accountLine(AgentAccountInfo? account, AgentAvailability? availability) {
  if (account?.email case final String email) {
    return email;
  }
  return availability?.needsSignIn ?? false ? 'Not signed in' : null;
}

/// "Team" for `team`; `null` when the agent reports no plan.
String? _planName(String? plan) => plan == null || plan.isEmpty ? null : '${plan[0].toUpperCase()}${plan.substring(1)}';

Future<void> _copyCommand(BuildContext context, String command, String confirmation) async {
  await Clipboard.setData(ClipboardData(text: command));
  if (context.mounted) {
    showWeaveToast(context, message: confirmation, tone: WeaveToastTone.success);
  }
}

/// Readiness of every agent and how Weave treats credentials.
class _ConnectionHealth extends StatelessWidget {
  const _ConnectionHealth({required this.controller});

  final AgentsController controller;

  @override
  Widget build(BuildContext context) => WeaveCard(
    key: const Key('connection-health'),
    padding: const EdgeInsets.all(WeaveSpacing.s24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text('Connection health', style: WeaveTypography.titleMedium),
        const SizedBox(height: WeaveSpacing.s4),
        Text('Checked on this Mac each time you open this screen or come back to Weave.', style: WeaveTypography.caption),
        const SizedBox(height: WeaveSpacing.s20),
        for (final AgentAdapter adapter in controller.agents) ...<Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(adapter.displayName, style: WeaveTypography.label),
                    Text(_healthDetail(controller.availabilityOf(adapter.id)), style: WeaveTypography.caption, maxLines: 2, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              const SizedBox(width: WeaveSpacing.s12),
              WeaveStatusPill(label: _readiness(controller.availabilityOf(adapter.id)).$1, tone: _readiness(controller.availabilityOf(adapter.id)).$2),
            ],
          ),
          const SizedBox(height: WeaveSpacing.s20),
        ],
        const Divider(height: WeaveLayout.divider, thickness: WeaveLayout.divider, color: WeaveColors.borderSubtle),
        const SizedBox(height: WeaveSpacing.s24),
        Text('SECURITY', style: WeaveTypography.overline),
        const SizedBox(height: WeaveSpacing.s10),
        Text(
          'Weave stores no credentials. Each agent signs in with its own command and keeps its sign-in itself; an extra account keeps it in its own folder. When an account reaches its usage limit, a workflow moves on to another signed-in account of the same agent. MCP tokens are read from environment variables when a workflow starts.',
          style: WeaveTypography.bodySmall,
        ),
        const SizedBox(height: WeaveSpacing.s12),
        Text('Custom agents are defined in:', style: WeaveTypography.caption),
        SelectableText(controller.configurationPath, style: WeaveTypography.code.copyWith(color: WeaveColors.textSecondary)),
      ],
    ),
  );

  static String _healthDetail(AgentAvailability? availability) => switch (availability) {
    null => 'Checking…',
    AgentAvailability(isAvailable: true, :final String? version) => version ?? 'Ready',
    AgentAvailability(needsSignIn: true) => 'Sign in to continue',
    _ => availability.reason ?? 'Not available',
  };
}

class _InstallCommandRow extends StatelessWidget {
  const _InstallCommandRow({required this.agentId, required this.index, required this.option, required this.showLabel, required this.onCopy});

  final String agentId;
  final int index;
  final AgentInstallOption option;
  final bool showLabel;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final String keySuffix = index == 0 ? agentId : '$agentId-$index';
    final String prefix = showLabel ? option.label : 'Install in Terminal';
    return Padding(
      padding: EdgeInsets.only(top: index == 0 ? 0 : WeaveSpacing.s4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Flexible(
            child: Text('$prefix: ${option.commandText}', key: Key('install-command-$keySuffix'), style: WeaveTypography.code),
          ),
          const SizedBox(width: WeaveSpacing.s6),
          WeaveIconButton(
            key: Key('copy-install-$keySuffix'),
            icon: WeaveIcons.copy,
            tooltip: 'Copy ${showLabel ? option.label : 'install'} command',
            size: WeaveSpacing.s28,
            iconSize: WeaveIconSize.compact,
            onPressed: onCopy,
          ),
        ],
      ),
    );
  }
}

/// The plan limits a ready agent reports, or why there are none.
class _PlanUsageSection extends StatelessWidget {
  const _PlanUsageSection({required this.adapter, required this.usage, required this.error, required this.refreshing});

  final AgentAdapter adapter;
  final AgentPlanUsage? usage;
  final String? error;
  final bool refreshing;

  @override
  Widget build(BuildContext context) {
    final AgentPlanUsage? usage = this.usage;
    final Widget content;
    if (!adapter.reportsPlanUsage) {
      content = Text('This agent does not report plan usage to Weave.', style: WeaveTypography.caption);
    } else if (usage != null) {
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (final AgentPlanUsageWindow window in usage.windows) ...<Widget>[
            WeaveUsageMeter(label: window.label, percentUsed: window.percentUsed, detail: _resetDetail(window), refreshing: refreshing),
            const SizedBox(height: WeaveSpacing.s10),
          ],
          if (error != null) Text('Last refresh failed: $error', style: WeaveTypography.caption.copyWith(color: WeaveColors.amber)),
        ],
      );
    } else if (refreshing) {
      content = Text('Reading plan usage…', style: WeaveTypography.caption);
    } else if (error case final String message) {
      content = Text(message, style: WeaveTypography.caption.copyWith(color: WeaveColors.amber));
    } else {
      content = Text('Plan usage not checked yet.', style: WeaveTypography.caption);
    }
    return KeyedSubtree(key: Key('plan-usage-${adapter.id}'), child: content);
  }

  static String _twoDigits(int value) => value.toString().padLeft(2, '0');

  static const List<String> _months = <String>['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  /// An exact reset time in local time, worded like the CLIs' own reports
  /// ("Oct 7 at 7:15pm"); otherwise the CLI's wording as is.
  static String? _resetDetail(AgentPlanUsageWindow window) {
    if (window.resetTime case final DateTime time) {
      final DateTime local = time.toLocal();
      final int hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
      return 'Resets ${_months[local.month - 1]} ${local.day} at $hour:${_twoDigits(local.minute)}${local.hour < 12 ? 'am' : 'pm'}';
    }
    return window.resetsAt == null ? null : 'Resets ${window.resetsAt}';
  }
}
