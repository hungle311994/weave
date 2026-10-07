import 'package:flutter/material.dart';

import '../../core/design_system/design_system.dart';

/// Development-only catalogue of every Weave design-system component.
class ComponentGalleryPage extends StatefulWidget {
  const ComponentGalleryPage({super.key});

  @override
  State<ComponentGalleryPage> createState() => _ComponentGalleryPageState();
}

class _ComponentGalleryPageState extends State<ComponentGalleryPage> {
  bool _checked = true;
  bool _switched = true;
  String _access = 'write';
  String _agent = 'codex';

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SingleChildScrollView(
      padding: const EdgeInsets.all(WeaveSpacing.s32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          WeavePageHeader(
            breadcrumb: const <String>['Design system', 'Components'],
            title: 'Component gallery',
            subtitle: 'Interactive states and visual variants for Weave.',
            trailing: Row(
              children: <Widget>[
                const WeaveStatusPill(label: 'Ready', tone: WeaveTone.success),
                const SizedBox(width: WeaveSpacing.s12),
                WeaveButton.primary(label: 'Primary action', onPressed: () {}),
              ],
            ),
          ),
          const SizedBox(height: WeaveSpacing.s32),
          _section(
            'Buttons & feedback',
            Wrap(
              spacing: WeaveSpacing.s12,
              runSpacing: WeaveSpacing.s12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: <Widget>[
                const WeaveLogoMark(),
                const SizedBox(width: WeaveLayout.recentWorkflowCardWidth, child: WeaveMarqueeText('A recent workflow title that is intentionally too long for its card')),
                const WeaveAvatar(name: 'Hùng Lê Quang'),
                WeaveAccountButton(name: 'Hùng Lê Quang', expanded: true, onPressed: () {}),
                WeaveButton.primary(label: 'Primary', icon: WeaveIcons.play, onPressed: () {}),
                WeaveButton(label: 'Secondary', onPressed: () {}),
                WeaveButton.danger(label: 'Danger', onPressed: () {}),
                WeaveButton(label: 'Ghost', variant: WeaveButtonVariant.ghost, onPressed: () {}),
                const WeaveButton(label: 'Disabled', onPressed: null),
                WeaveButton(label: 'Small', size: WeaveButtonSize.small, onPressed: () {}),
                WeaveIconButton(icon: WeaveIcons.settings, tooltip: 'Settings', bordered: true, onPressed: () {}),
                WeaveIconButton(icon: WeaveIcons.check, tooltip: 'Selected', selected: true, onPressed: () {}),
                const WeaveIconButton(icon: WeaveIcons.close, tooltip: 'Disabled close', onPressed: null),
                const WeaveStatusPill(label: 'Running', tone: WeaveTone.success),
                const WeaveStatusPill(label: 'In progress', tone: WeaveTone.info),
                const WeaveStatusPill(label: 'Needs review', tone: WeaveTone.warning),
                const WeaveStatusPill(label: 'Failed', tone: WeaveTone.danger),
                const WeaveStatusPill(label: 'Planner', tone: WeaveTone.accent),
                const WeaveStatusPill(label: 'Idle', tone: WeaveTone.neutral),
                const WeaveStatusPill.compact(label: 'Ready', tone: WeaveTone.success),
                const WeaveBadge(label: 'Planner', tone: WeaveTone.accent),
                const WeaveBadge(label: 'Modified', tone: WeaveTone.info, icon: WeaveIcons.fileCode),
                const WeaveCountBubble(count: 12),
                const WeaveTooltip(message: 'Tooltip text', child: WeaveIcon(WeaveIcons.info)),
                WeaveButton(
                  label: 'Show toast',
                  onPressed: () => showWeaveToast(context, message: 'Command copied. Run it in Terminal, then scan again.', tone: WeaveToastTone.success),
                ),
              ],
            ),
          ),
          _section(
            'Surfaces & inputs',
            Wrap(
              spacing: WeaveSpacing.s20,
              runSpacing: WeaveSpacing.s20,
              crossAxisAlignment: WrapCrossAlignment.start,
              children: <Widget>[
                SizedBox(
                  width: WeaveLayout.galleryTileWidth,
                  child: WeaveCard(child: Text('Gradient card', style: WeaveTypography.body)),
                ),
                SizedBox(
                  width: WeaveLayout.galleryTileWidth,
                  child: WeaveCard(
                    surface: WeaveSurface.field,
                    child: Text('Field surface', style: WeaveTypography.body),
                  ),
                ),
                SizedBox(
                  width: WeaveLayout.galleryTileWidth,
                  child: WeaveCard(
                    surface: WeaveSurface.sunken,
                    child: Text('Sunken surface', style: WeaveTypography.body),
                  ),
                ),
                SizedBox(
                  width: WeaveLayout.galleryTileWidth,
                  child: WeaveCard(
                    surface: WeaveSurface.elevated,
                    onTap: () {},
                    child: Text('Interactive elevated surface', style: WeaveTypography.body),
                  ),
                ),
                SizedBox(
                  width: WeaveLayout.galleryTileWidth,
                  child: WeaveCard(
                    surface: WeaveSurface.selected,
                    child: Text('Selected card', style: WeaveTypography.body),
                  ),
                ),
                const SizedBox(
                  width: WeaveLayout.galleryTileWidth,
                  child: WeaveTextField(label: 'Task name', hintText: 'Describe the task'),
                ),
                const SizedBox(
                  width: WeaveLayout.galleryTileWidth,
                  child: WeaveTextField.multiline(label: 'Details', hintText: 'Add more context', minLines: 2, maxLines: 3),
                ),
                const SizedBox(
                  width: WeaveLayout.galleryTileWidth,
                  child: WeaveTextField(label: 'Invalid field', errorText: 'Required'),
                ),
                const SizedBox(
                  width: WeaveLayout.galleryTileWidth,
                  child: WeaveTextField(label: 'Disabled field', enabled: false),
                ),
                const WeaveChip(label: 'feature/gallery', icon: WeaveIcons.gitBranch, shape: WeaveChipShape.pill),
                WeaveChip(label: 'context.dart', icon: WeaveIcons.fileCode, onRemove: () {}),
                WeaveSegmentedControl<String>(
                  value: _access,
                  onChanged: (String value) => setState(() => _access = value),
                  semanticLabel: 'Repository access',
                  segments: const <WeaveSegment<String>>[
                    WeaveSegment<String>(value: 'write', label: 'Write', icon: WeaveIcons.pencil),
                    WeaveSegment<String>(value: 'read', label: 'Read only', icon: WeaveIcons.eye),
                  ],
                ),
                const WeaveSegmentedControl<String>(
                  value: 'read',
                  onChanged: null,
                  semanticLabel: 'Disabled repository access',
                  segments: <WeaveSegment<String>>[
                    WeaveSegment<String>(value: 'write', label: 'Write', icon: WeaveIcons.pencil),
                    WeaveSegment<String>(value: 'read', label: 'Read only', icon: WeaveIcons.eye),
                  ],
                ),
                WeaveCheckbox(value: _checked, semanticLabel: 'Include file', onChanged: (bool value) => setState(() => _checked = value)),
                const WeaveCheckbox(value: false, semanticLabel: 'Disabled file', onChanged: null),
                WeaveSwitch(value: _switched, semanticLabel: 'Plan checkpoint', onChanged: (bool value) => setState(() => _switched = value)),
                const WeaveSwitch(value: false, semanticLabel: 'Disabled checkpoint', onChanged: null),
                SizedBox(
                  width: WeaveLayout.galleryTileWidth,
                  child: WeaveSelect<String>(
                    label: 'Planner default',
                    value: _agent,
                    onChanged: (String value) => setState(() => _agent = value),
                    options: const <WeavePopoverItem<String>>[
                      WeavePopoverItem<String>(value: 'codex', title: 'Codex · gpt-4.1', brand: BrandMark.openai, selected: true),
                      WeavePopoverItem<String>(value: 'claude', title: 'Claude Code · Sonnet', brand: BrandMark.anthropic),
                    ],
                  ),
                ),
                const SizedBox(
                  width: WeaveLayout.galleryTileWidth,
                  child: WeaveSelect<String>(
                    label: 'Disabled select',
                    value: 'main',
                    onChanged: null,
                    options: <WeavePopoverItem<String>>[WeavePopoverItem<String>(value: 'main', title: 'main', icon: WeaveIcons.gitBranch, selected: true)],
                  ),
                ),
              ],
            ),
          ),
          _section(
            'Popover menu',
            Wrap(
              spacing: WeaveSpacing.s20,
              runSpacing: WeaveSpacing.s20,
              children: <Widget>[
                WeavePopoverMenu<String>(
                  onSelected: (String value) {},
                  groups: const <WeavePopoverGroup<String>>[
                    WeavePopoverGroup<String>(
                      label: 'Workspaces',
                      items: <WeavePopoverItem<String>>[
                        WeavePopoverItem<String>(value: 'weave', title: 'Weave', subtitle: '3 folders · flutter, backend, admin', icon: WeaveIcons.layers, selected: true),
                        WeavePopoverItem<String>(value: 'app', title: 'App', subtitle: 'Single folder', icon: WeaveIcons.folder),
                      ],
                    ),
                    WeavePopoverGroup<String>(
                      items: <WeavePopoverItem<String>>[WeavePopoverItem<String>(value: 'new', title: 'New workspace…', icon: WeaveIcons.plus)],
                    ),
                  ],
                ),
                const WeavePopoverMenu<String>(
                  onSelected: null,
                  groups: <WeavePopoverGroup<String>>[
                    WeavePopoverGroup<String>(
                      label: 'Disabled',
                      items: <WeavePopoverItem<String>>[WeavePopoverItem<String>(value: 'item', title: 'Unavailable action', icon: WeaveIcons.lock)],
                    ),
                  ],
                ),
              ],
            ),
          ),
          _section(
            'Window title bar',
            const SizedBox(
              width: WeaveLayout.galleryTileWidth,
              child: WeaveWindowTitleBar(),
            ),
          ),
          _section(
            'Sidebar resize handle',
            SizedBox(
              height: WeaveSpacing.s48,
              child: Row(
                children: <Widget>[
                  Text('Expanded', style: WeaveTypography.body),
                  const SizedBox(width: WeaveSpacing.s12),
                  WeaveSidebarResizeHandle(
                    expanded: true,
                    onToggle: () {},
                    onDragStart: (DragStartDetails details) {},
                    onDragUpdate: (DragUpdateDetails details) {},
                    onDragEnd: (DragEndDetails details) {},
                  ),
                  const SizedBox(width: WeaveSpacing.s24),
                  Text('Collapsed', style: WeaveTypography.body),
                  const SizedBox(width: WeaveSpacing.s12),
                  WeaveSidebarResizeHandle(
                    expanded: false,
                    onToggle: () {},
                    onDragStart: (DragStartDetails details) {},
                    onDragUpdate: (DragUpdateDetails details) {},
                    onDragEnd: (DragEndDetails details) {},
                  ),
                ],
              ),
            ),
          ),
          _section(
            'Workflow timeline',
            SizedBox(
              width: WeaveLayout.galleryTimelineWidth,
              child: WeaveStepTimeline(
                steps: <WeaveStep>[
                  const WeaveStep(title: 'Plan', subtitle: 'Completed by Codex', status: WeaveStepStatus.done),
                  WeaveStep(
                    title: 'Implement',
                    subtitle: 'Editing 4 files…',
                    status: WeaveStepStatus.active,
                    child: WeaveCard(
                      surface: WeaveSurface.sunken,
                      padding: const EdgeInsets.all(WeaveSpacing.s12),
                      child: Text('› Updating auth_provider.dart\n› Writing focused tests', style: WeaveTypography.code),
                    ),
                  ),
                  const WeaveStep(title: 'Verify', subtitle: 'Queued', status: WeaveStepStatus.pending),
                  const WeaveStep(title: 'Review', subtitle: 'Previous attempt failed', status: WeaveStepStatus.failed),
                ],
              ),
            ),
          ),
          _section(
            'Dialog',
            SizedBox(
              height: WeaveLayout.dialogHeight,
              child: WeaveDialog(
                title: 'Choose repository',
                subtitle: 'Select a local Git repository for this workflow.',
                onClose: () {},
                body: Column(
                  children: <Widget>[
                    WeaveCard(
                      surface: WeaveSurface.selected,
                      child: Text('mama-morsel / flutter', style: WeaveTypography.bodyStrong),
                    ),
                    const SizedBox(height: WeaveSpacing.s12),
                    WeaveCard(
                      surface: WeaveSurface.elevated,
                      child: Text('Weave', style: WeaveTypography.bodyStrong),
                    ),
                  ],
                ),
                actions: <Widget>[
                  WeaveButton(label: 'Cancel', onPressed: () {}),
                  WeaveButton.primary(label: 'Use repository', onPressed: () {}),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _section(String title, Widget child) => Padding(
    padding: const EdgeInsets.only(bottom: WeaveSpacing.s32),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(title, style: WeaveTypography.titleMedium),
        const SizedBox(height: WeaveSpacing.s16),
        child,
      ],
    ),
  );
}
