import 'package:flutter/material.dart';

import '../../../core/design_system/design_system.dart';

/// The fixed safety policy enforced independently of the selected agents.
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (BuildContext context, BoxConstraints constraints) {
      final bool useColumns = constraints.maxWidth >= WeaveLayout.settingsColumnsBreakpoint;
      final Widget navigation = const _SettingsNavigation();
      final Widget permissions = const _PermissionsCard();
      final Widget policy = const _CurrentPolicyCard();
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(WeaveLayout.pageGutter, WeaveLayout.windowContentTopPadding, WeaveLayout.pageGutter, WeaveSpacing.s40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const WeavePageHeader(
              breadcrumb: <String>['Workspace', 'Settings'],
              title: 'Settings',
              subtitle: 'Review Weave’s fixed safety policy and workflow behavior.',
            ),
            const SizedBox(height: WeaveSpacing.s32),
            if (useColumns)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  SizedBox(width: WeaveLayout.settingsNavigationWidth, child: navigation),
                  const SizedBox(width: WeaveSpacing.s24),
                  Expanded(child: permissions),
                  const SizedBox(width: WeaveSpacing.s24),
                  SizedBox(width: WeaveLayout.settingsPolicyWidth, child: policy),
                ],
              )
            else
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  navigation,
                  const SizedBox(height: WeaveSpacing.s24),
                  permissions,
                  const SizedBox(height: WeaveSpacing.s24),
                  policy,
                ],
              ),
          ],
        ),
      );
    },
  );
}

class _SettingsNavigation extends StatelessWidget {
  const _SettingsNavigation();

  @override
  Widget build(BuildContext context) => WeaveCard(
    key: const Key('settings-navigation'),
    padding: const EdgeInsets.all(WeaveSpacing.s10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (final String section in const <String>['General', 'Permissions', 'Workflow defaults', 'Storage', 'Notifications', 'About']) ...<Widget>[
          WeaveCard(
            surface: section == 'Permissions' ? WeaveSurface.selected : WeaveSurface.sunken,
            padding: const EdgeInsets.symmetric(horizontal: WeaveSpacing.s14, vertical: WeaveSpacing.s10),
            child: Text(
              section,
              style: (section == 'Permissions' ? WeaveTypography.breadcrumb.copyWith(color: WeaveColors.purpleSoft, fontWeight: WeaveTypography.semiBold) : WeaveTypography.bodySmall),
            ),
          ),
          if (section != 'About') const SizedBox(height: WeaveSpacing.s8),
        ],
      ],
    ),
  );
}

class _PermissionsCard extends StatelessWidget {
  const _PermissionsCard();

  @override
  Widget build(BuildContext context) => WeaveCard(
    key: const Key('permissions-card'),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text('Permissions & safety', style: WeaveTypography.titleMedium),
        const SizedBox(height: WeaveSpacing.s4),
        Text('These guards are enforced by Weave and cannot be weakened by an agent.', style: WeaveTypography.bodySmall),
        const SizedBox(height: WeaveSpacing.s28),
        const _PolicyDetail(
          icon: WeaveIcons.eye,
          title: 'Plan and review',
          description: 'Planner and reviewer roles are read-only. The workflow stops if either changes the working tree.',
          status: 'Read only',
          tone: WeaveTone.success,
        ),
        const _PolicyDetail(
          icon: WeaveIcons.pencil,
          title: 'Implementation',
          description: 'The implementer may leave uncommitted edits. HEAD and the current branch must not move.',
          status: 'Guarded',
          tone: WeaveTone.success,
        ),
        const _PolicyDetail(
          icon: WeaveIcons.terminal,
          title: 'Verification',
          description: 'Weave starts each validation executable directly with arguments; it never invokes a shell.',
          status: 'No shell',
          tone: WeaveTone.info,
        ),
        const _PolicyDetail(
          icon: WeaveIcons.gitCommit,
          title: 'Commit and push',
          description: 'A commit needs approval of the exact file list. Push is not supported.',
          status: 'Approval',
          tone: WeaveTone.warning,
          last: true,
        ),
      ],
    ),
  );
}

class _PolicyDetail extends StatelessWidget {
  const _PolicyDetail({required this.icon, required this.title, required this.description, required this.status, required this.tone, this.last = false});

  final WeaveIcons icon;
  final String title;
  final String description;
  final String status;
  final WeaveTone tone;
  final bool last;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: last ? 0 : WeaveSpacing.s24),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        WeaveCard(
          surface: WeaveSurface.sunken,
          padding: const EdgeInsets.all(WeaveSpacing.s10),
          child: WeaveIcon(icon, size: WeaveSpacing.s20),
        ),
        const SizedBox(width: WeaveSpacing.s12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(title, style: WeaveTypography.label),
              const SizedBox(height: WeaveSpacing.s2),
              Text(description, style: WeaveTypography.caption),
            ],
          ),
        ),
        const SizedBox(width: WeaveSpacing.s12),
        WeaveStatusPill.compact(label: status, tone: tone),
      ],
    ),
  );
}

class _CurrentPolicyCard extends StatelessWidget {
  const _CurrentPolicyCard();

  @override
  Widget build(BuildContext context) => WeaveCard(
    key: const Key('current-policy-card'),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text('Current policy', style: WeaveTypography.titleMedium),
        const SizedBox(height: WeaveSpacing.s24),
        const _PolicySummary(label: 'Planner & reviewer', value: 'Read only', tone: WeaveTone.success),
        const _PolicySummary(label: 'Implementer', value: 'Uncommitted edits', tone: WeaveTone.success),
        const _PolicySummary(label: 'Network', value: 'Approval', tone: WeaveTone.warning),
        const _PolicySummary(label: 'Commits', value: 'Approval', tone: WeaveTone.warning),
        const _PolicySummary(label: 'Push', value: 'Unsupported', tone: WeaveTone.neutral),
        const SizedBox(height: WeaveSpacing.s24),
        Text('Safe by default. Agent output and stored workflow data pass through secret redaction.', style: WeaveTypography.caption),
      ],
    ),
  );
}

class _PolicySummary extends StatelessWidget {
  const _PolicySummary({required this.label, required this.value, required this.tone});

  final String label;
  final String value;
  final WeaveTone tone;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: WeaveSpacing.s16),
    child: Row(
      children: <Widget>[
        Expanded(child: Text(label, style: WeaveTypography.bodySmall)),
        const SizedBox(width: WeaveSpacing.s8),
        WeaveStatusPill.compact(label: value, tone: tone),
      ],
    ),
  );
}
