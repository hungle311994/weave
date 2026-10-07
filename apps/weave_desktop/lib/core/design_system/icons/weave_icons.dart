import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../tokens/weave_colors.dart';

/// UI icons of the design, stored as monochrome SVGs in `assets/icons`.
enum WeaveIcons {
  alertTriangle('alert_triangle'),
  arrowLeft('arrow_left'),
  arrowRight('arrow_right'),
  arrowUp('arrow_up'),
  atSign('at_sign'),
  bot('bot'),
  check('check'),
  checkCircle('check_circle'),
  chevronDown('chevron_down'),
  chevronLeft('chevron_left'),
  chevronRight('chevron_right'),
  chevronUp('chevron_up'),
  circle('circle'),
  clock('clock'),
  close('close'),
  copy('copy'),
  download('download'),
  eye('eye'),
  file('file'),
  fileCode('file_code'),
  folder('folder'),
  gitBranch('git_branch'),
  gitCommit('git_commit'),
  grid('grid'),
  grip('grip'),
  history('history'),
  home('home'),
  info('info'),
  layers('layers'),
  listChecks('list_checks'),
  lock('lock'),
  more('more'),
  panelClose('panel_close'),
  panelOpen('panel_open'),
  paperclip('paperclip'),
  pencil('pencil'),
  play('play'),
  plus('plus'),
  refresh('refresh'),
  search('search'),
  settings('settings'),
  shield('shield'),
  squareSlash('square_slash'),
  stop('stop'),
  terminal('terminal'),
  thinking('thinking'),
  trash('trash'),
  user('user');

  const WeaveIcons(this.fileName);

  final String fileName;

  String get assetPath => 'assets/icons/$fileName.svg';
}

/// Brand marks shown for agents and integrations, with their design colours.
enum BrandMark {
  openai('openai', 'OpenAI', WeaveColors.purple),
  anthropic('anthropic', 'Anthropic', WeaveColors.coral),
  gemini('gemini', 'Google Gemini', WeaveColors.cyan),
  figma('figma', 'Figma', WeaveColors.purple),
  github('github', 'GitHub', WeaveColors.textPrimary),
  linear('linear', 'Linear', Color(0xFF8A93F5)),
  sentry('sentry', 'Sentry', Color(0xFFFF6484));

  const BrandMark(this.fileName, this.displayName, this.color);

  final String fileName;
  final String displayName;
  final Color color;

  String get assetPath => 'assets/icons/brand/$fileName.svg';

  /// The mark whose [fileName] is [name] (as written in agent or MCP data), if any.
  static BrandMark? byName(String? name) {
    for (final BrandMark mark in values) {
      if (mark.fileName == name) {
        return mark;
      }
    }
    return null;
  }
}

/// A [WeaveIcons] glyph tinted with [color], or the ambient [IconTheme] colour.
class WeaveIcon extends StatelessWidget {
  const WeaveIcon(this.icon, {this.size = 20, this.color, this.semanticLabel, super.key});

  final WeaveIcons icon;
  final double size;
  final Color? color;

  /// Read by screen readers; decorative icons leave it null.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final Color tint = color ?? IconTheme.of(context).color ?? WeaveColors.textSecondary;
    return SvgPicture.asset(icon.assetPath, width: size, height: size, colorFilter: ColorFilter.mode(tint, BlendMode.srcIn), semanticsLabel: semanticLabel, excludeFromSemantics: semanticLabel == null);
  }
}

/// A [BrandMark] in its design colour unless [color] overrides it.
class BrandIcon extends StatelessWidget {
  const BrandIcon(this.mark, {this.size = 24, this.color, super.key});

  final BrandMark mark;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) => SvgPicture.asset(mark.assetPath, width: size, height: size, colorFilter: ColorFilter.mode(color ?? mark.color, BlendMode.srcIn), semanticsLabel: mark.displayName);
}
