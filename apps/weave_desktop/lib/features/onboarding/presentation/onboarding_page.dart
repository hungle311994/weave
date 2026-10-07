import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:weave_agents/weave_agents.dart';

import '../../../core/design_system/design_system.dart';
import '../../agents/presentation/agents_controller.dart';
import 'onboarding_controller.dart';

/// First-run setup for local mode and agent readiness.
class OnboardingPage extends StatelessWidget {
  const OnboardingPage({required this.controller, required this.agents, super.key});

  final OnboardingController controller;
  final AgentsController agents;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: WeaveColors.canvas,
      body: ListenableBuilder(
        listenable: Listenable.merge(<Listenable>[controller, agents]),
        builder: (BuildContext context, Widget? child) => Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(WeaveSpacing.s40),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: WeaveLayout.newTaskFormWidth),
              child: controller.showAgentSetup ? _AgentSetup(controller: controller, agents: agents) : _Welcome(controller: controller),
            ),
          ),
        ),
      ),
    );
  }
}

class _Welcome extends StatelessWidget {
  const _Welcome({required this.controller});

  final OnboardingController controller;

  @override
  Widget build(BuildContext context) {
    return WeaveCard(
      padding: const EdgeInsets.all(WeaveSpacing.s40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const Align(
            alignment: Alignment.centerLeft,
            child: WeaveLogoMark(key: Key('onboarding-logo'), size: WeaveSpacing.s48),
          ),
          const SizedBox(height: WeaveSpacing.s24),
          Text('Welcome to Weave', style: WeaveTypography.display),
          const SizedBox(height: WeaveSpacing.s12),
          Text('Coordinate coding agents locally without creating a Weave account. Your repositories and agent credentials stay under your control.', style: WeaveTypography.body),
          const SizedBox(height: WeaveSpacing.s28),
          WeaveCard(
            surface: WeaveSurface.sunken,
            padding: const EdgeInsets.all(WeaveSpacing.s16),
            child: Row(
              children: <Widget>[
                const WeaveIcon(WeaveIcons.lock, color: WeaveColors.green),
                const SizedBox(width: WeaveSpacing.s12),
                Expanded(child: Text('Weave does not store agent passwords, API keys, or session cookies.', style: WeaveTypography.bodySmall)),
              ],
            ),
          ),
          const SizedBox(height: WeaveSpacing.s28),
          WeaveButton.primary(key: const Key('continue-locally'), label: 'Continue locally', icon: WeaveIcons.arrowRight, onPressed: controller.continueLocally, expand: true),
          const SizedBox(height: WeaveSpacing.s12),
          Text('Cloud sign-in and cross-device sync are not available yet.', textAlign: TextAlign.center, style: WeaveTypography.caption),
        ],
      ),
    );
  }
}

class _AgentSetup extends StatelessWidget {
  const _AgentSetup({required this.controller, required this.agents});

  final OnboardingController controller;
  final AgentsController agents;

  @override
  Widget build(BuildContext context) {
    final bool hasReadyAgent = agents.hasReadyAgent;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            WeaveIconButton(icon: WeaveIcons.arrowLeft, tooltip: 'Back to welcome', onPressed: controller.back),
            const SizedBox(width: WeaveSpacing.s12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text('Set up an AI agent', style: WeaveTypography.display),
                  Text('Weave found these configured command-line agents on this Mac.', style: WeaveTypography.body),
                ],
              ),
            ),
            WeaveButton(
              key: const Key('scan-agents'),
              label: agents.refreshing ? 'Scanning…' : 'Scan again',
              icon: WeaveIcons.refresh,
              onPressed: agents.refreshing ? null : agents.refresh,
            ),
          ],
        ),
        const SizedBox(height: WeaveSpacing.s24),
        for (final AgentAdapter adapter in agents.agents) ...<Widget>[
          _AgentSetupCard(adapter: adapter, availability: agents.availabilityOf(adapter.id)),
          const SizedBox(height: WeaveSpacing.s12),
        ],
        if (agents.agents.isEmpty)
          WeaveCard(
            child: Text('No configured agents were found. Add an agent definition, then scan again.', style: WeaveTypography.body),
          ),
        if (!hasReadyAgent) ...<Widget>[
          const SizedBox(height: WeaveSpacing.s8),
          Text('Set up at least one agent before continuing.', style: WeaveTypography.bodySmall.copyWith(color: WeaveColors.amber)),
        ],
        if (controller.error case final String error) ...<Widget>[
          const SizedBox(height: WeaveSpacing.s12),
          Text(error, style: WeaveTypography.bodySmall.copyWith(color: WeaveColors.red)),
        ],
        const SizedBox(height: WeaveSpacing.s24),
        WeaveButton.primary(
          key: const Key('finish-onboarding'),
          label: controller.saving ? 'Saving…' : 'Start using Weave',
          icon: WeaveIcons.arrowRight,
          onPressed: hasReadyAgent && !controller.saving ? controller.finish : null,
          expand: true,
        ),
      ],
    );
  }
}

class _AgentSetupCard extends StatelessWidget {
  const _AgentSetupCard({required this.adapter, required this.availability});

  final AgentAdapter adapter;
  final AgentAvailability? availability;

  @override
  Widget build(BuildContext context) {
    final AgentAvailability? availability = this.availability;
    final bool ready = availability?.isAvailable ?? false;
    final String? signIn = availability?.signInCommand;
    final AgentDefinition? definition = switch (adapter) {
      CommandAgentAdapter(:final AgentDefinition definition) => definition,
      _ => null,
    };
    final List<AgentInstallOption> installOptions = availability != null && !availability.isInstalled ? definition?.installOptions ?? const <AgentInstallOption>[] : const <AgentInstallOption>[];
    final String statusLabel = ready
        ? 'Ready'
        : installOptions.isNotEmpty
        ? 'Not installed'
        : 'Needs setup';
    return WeaveCard(
      key: Key('onboarding-agent-${adapter.id}'),
      padding: const EdgeInsets.all(WeaveSpacing.s16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(top: WeaveSpacing.s4),
            child: WeaveIcon(
              ready
                  ? WeaveIcons.checkCircle
                  : signIn == null
                  ? WeaveIcons.alertTriangle
                  : WeaveIcons.terminal,
              color: ready ? WeaveColors.green : WeaveColors.amber,
            ),
          ),
          const SizedBox(width: WeaveSpacing.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(adapter.displayName, style: WeaveTypography.bodyStrong),
                Text(availability?.reason ?? availability?.version ?? 'Checking availability…', style: WeaveTypography.caption),
                if (installOptions.isNotEmpty) ...<Widget>[
                  const SizedBox(height: WeaveSpacing.s6),
                  for (final (int index, AgentInstallOption option) in installOptions.indexed)
                    _InstallCommandRow(
                      agentId: adapter.id,
                      index: index,
                      option: option,
                      showLabel: installOptions.length > 1,
                      onCopy: () => _copyCommand(context, option.commandText, 'Install command copied. Run it in Terminal, then scan again.'),
                    ),
                ],
              ],
            ),
          ),
          WeaveStatusPill(label: statusLabel, tone: ready ? WeaveTone.success : WeaveTone.warning),
          if (signIn != null && !ready) ...<Widget>[
            const SizedBox(width: WeaveSpacing.s12),
            WeaveButton(
              key: Key('copy-sign-in-${adapter.id}'),
              label: 'Copy sign-in',
              icon: WeaveIcons.terminal,
              onPressed: () => _copyCommand(context, signIn, 'Sign-in command copied. Run it in Terminal, then scan again.'),
            ),
          ],
        ],
      ),
    );
  }

  static Future<void> _copyCommand(
    BuildContext context,
    String command,
    String confirmation,
  ) async {
    await Clipboard.setData(ClipboardData(text: command));
    if (context.mounted) {
      showWeaveToast(context, message: confirmation, tone: WeaveToastTone.success);
    }
  }
}

class _InstallCommandRow extends StatelessWidget {
  const _InstallCommandRow({
    required this.agentId,
    required this.index,
    required this.option,
    required this.showLabel,
    required this.onCopy,
  });

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
