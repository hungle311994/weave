/// Source of every icon asset in `assets/icons`. Icons are drawn in black and
/// tinted at runtime with `BlendMode.srcIn`, so they must stay single-colour.
library;

String _stroke(String body) => '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="#000000" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">$body</svg>\n';

String _fill(String body, {String viewBox = '0 0 24 24'}) => '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="$viewBox" fill="#000000">$body</svg>\n';

/// UI icons by file name (without `.svg`); keep in sync with `WeaveIcons`.
final Map<String, String> uiIcons = <String, String>{
  'play': _fill('<path d="M5 5a2 2 0 0 1 3.008-1.728l11.997 6.998a2 2 0 0 1 .003 3.458l-12 7A2 2 0 0 1 5 19z"/>', viewBox: '2.8 2.5 19 19'),
  'stop': _fill('<rect x="6" y="6" width="12" height="12" rx="2.5"/>'),
  'more': _fill('<circle cx="5" cy="12" r="1.8"/><circle cx="12" cy="12" r="1.8"/><circle cx="19" cy="12" r="1.8"/>'),
  'grip': _fill('<circle cx="9" cy="7" r="1.4"/><circle cx="15" cy="7" r="1.4"/><circle cx="9" cy="12" r="1.4"/><circle cx="15" cy="12" r="1.4"/><circle cx="9" cy="17" r="1.4"/><circle cx="15" cy="17" r="1.4"/>'),
  'git_branch': _stroke('<path d="M6 3v12"/><circle cx="18" cy="6" r="3"/><circle cx="6" cy="18" r="3"/><path d="M18 9a9 9 0 0 1-9 9"/>'),
  'git_commit': _stroke('<circle cx="12" cy="12" r="3.2"/><path d="M3 12h5.8"/><path d="M15.2 12H21"/>'),
  'trash': _stroke('<path d="M4 7h16"/><path d="M10 11v6"/><path d="M14 11v6"/><path d="M6 7l1 12a2 2 0 0 0 2 2h6a2 2 0 0 0 2-2l1-12"/><path d="M9 7V4.5A1.5 1.5 0 0 1 10.5 3h3A1.5 1.5 0 0 1 15 4.5V7"/>'),
  'terminal': _stroke('<rect x="3" y="3" width="18" height="18" rx="3"/><path d="m7 9 3 3-3 3"/><path d="M13 15h4"/>'),
  'lock': _stroke('<rect x="4" y="10.5" width="16" height="10.5" rx="2.5"/><path d="M8 10.5V7a4 4 0 0 1 8 0v3.5"/><path d="M12 14.5v2.5"/>'),
  'shield': _stroke('<path d="M12 3 4.5 6v5.5c0 4.6 3.2 8.4 7.5 9.5 4.3-1.1 7.5-4.9 7.5-9.5V6z"/>'),
  'file': _stroke('<path d="M14.5 2.5H7a2 2 0 0 0-2 2v15a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V7z"/><path d="M14.5 2.5V7H19"/>'),
  'file_code': _stroke('<path d="M14.5 2.5H7a2 2 0 0 0-2 2v15a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V7z"/><path d="M14.5 2.5V7H19"/><path d="m10 12.5-2 2 2 2"/><path d="m14 12.5 2 2-2 2"/>'),
  'folder': _stroke('<path d="M3 7.5A2.5 2.5 0 0 1 5.5 5h3.6l2 2.2h7.4A2.5 2.5 0 0 1 21 9.7v7.8a2.5 2.5 0 0 1-2.5 2.5h-13A2.5 2.5 0 0 1 3 17.5z"/>'),
  'layers': _stroke('<path d="m12 3 9 4.5-9 4.5-9-4.5z"/><path d="m3 12 9 4.5 9-4.5"/><path d="m3 16.5 9 4.5 9-4.5"/>'),
  'settings': _stroke(
    '<circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.7 1.7 0 0 0 .3 1.9l.1.1-2.8 2.8-.1-.1a1.7 1.7 0 0 0-1.9-.3 1.7 1.7 0 0 0-1 1.6v.2h-4V21a1.7 1.7 0 0 0-1-1.6 1.7 1.7 0 0 0-1.9.3l-.1.1L4.2 17l.1-.1a1.7 1.7 0 0 0 .3-1.9A1.7 1.7 0 0 0 3 14H2.8v-4H3a1.7 1.7 0 0 0 1.6-1 1.7 1.7 0 0 0-.3-1.9L4.2 7 7 4.2l.1.1A1.7 1.7 0 0 0 9 4.6a1.7 1.7 0 0 0 1-1.6v-.2h4V3a1.7 1.7 0 0 0 1 1.6 1.7 1.7 0 0 0 1.9-.3l.1-.1L19.8 7l-.1.1a1.7 1.7 0 0 0-.3 1.9 1.7 1.7 0 0 0 1.6 1h.2v4H21a1.7 1.7 0 0 0-1.6 1Z"/>',
  ),
  'chevron_down': _stroke('<path d="m6 9 6 6 6-6"/>'),
  'chevron_up': _stroke('<path d="m18 15-6-6-6 6"/>'),
  'chevron_right': _stroke('<path d="m9 18 6-6-6-6"/>'),
  'chevron_left': _stroke('<path d="m15 18-6-6 6-6"/>'),
  'arrow_right': _stroke('<path d="M5 12h14"/><path d="m12 5 7 7-7 7"/>'),
  'arrow_left': _stroke('<path d="M19 12H5"/><path d="m12 19-7-7 7-7"/>'),
  'arrow_up': _stroke('<path d="M12 19V5"/><path d="m5 12 7-7 7 7"/>'),
  'check': _stroke('<path d="M20 6 9 17l-5-5"/>'),
  'check_circle': _stroke('<circle cx="12" cy="12" r="9"/><path d="m8 12.5 2.7 2.7L16.5 9.5"/>'),
  'circle': _stroke('<circle cx="12" cy="12" r="8"/>'),
  'close': _stroke('<path d="M18 6 6 18"/><path d="m6 6 12 12"/>'),
  'copy': _stroke('<rect x="9" y="9" width="12" height="12" rx="2"/><path d="M15 9V5a2 2 0 0 0-2-2H5a2 2 0 0 0-2 2v8a2 2 0 0 0 2 2h4"/>'),
  'plus': _stroke('<path d="M12 5v14"/><path d="M5 12h14"/>'),
  'search': _stroke('<circle cx="11" cy="11" r="6.5"/><path d="m20 20-4.4-4.4"/>'),
  'pencil': _stroke('<path d="M16.5 3.5a2.4 2.4 0 0 1 3.4 3.4L8 18.8 3.5 20.5l1.7-4.5z"/>'),
  'eye': _stroke('<path d="M2.5 12S6 5.5 12 5.5 21.5 12 21.5 12 18 18.5 12 18.5 2.5 12 2.5 12z"/><circle cx="12" cy="12" r="3"/>'),
  'download': _stroke('<path d="M12 3v12"/><path d="m7 10 5 5 5-5"/><path d="M4 17v2a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2v-2"/>'),
  'clock': _stroke('<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/>'),
  'history': _stroke('<path d="M3.5 12a8.5 8.5 0 1 0 2.6-6.1L3.5 8.5"/><path d="M3.5 3.5v5h5"/><path d="M12 7.5V12l3.5 2"/>'),
  'home': _stroke('<path d="m3 10 9-7 9 7"/><path d="M5 9v11h14V9"/><path d="M9 20v-6h6v6"/>'),
  'refresh': _stroke('<path d="M20.5 12a8.5 8.5 0 1 1-2.6-6.1l2.6 2.6"/><path d="M20.5 3.5v5h-5"/>'),
  'paperclip': _stroke('<path d="m20.5 11.5-8.4 8.4a5.5 5.5 0 0 1-7.8-7.8l8.4-8.4a3.7 3.7 0 0 1 5.2 5.2l-8.4 8.4a1.8 1.8 0 0 1-2.6-2.6l7.8-7.8"/>'),
  'at_sign': _stroke('<circle cx="12" cy="12" r="4"/><path d="M16 8v5a3 3 0 0 0 6 0v-1a10 10 0 1 0-3.9 7.9"/>'),
  'square_slash': _stroke('<rect x="3" y="3" width="18" height="18" rx="3.5"/><path d="m9.5 16 5-8"/>'),
  'thinking': _stroke('<path d="M12 3v2.5"/><path d="M12 18.5V21"/><path d="M3 12h2.5"/><path d="M18.5 12H21"/><path d="m5.6 5.6 1.8 1.8"/><path d="m16.6 16.6 1.8 1.8"/><path d="m5.6 18.4 1.8-1.8"/><path d="m16.6 7.4 1.8-1.8"/><circle cx="12" cy="12" r="3"/>'),
  'list_checks': _stroke('<path d="M9 6h11"/><path d="M9 12h11"/><path d="M9 18h11"/><path d="m3.5 6 1 1 2-2"/><path d="m3.5 12 1 1 2-2"/><path d="M4 18h1.5"/>'),
  'user': _stroke('<circle cx="12" cy="8" r="4"/><path d="M4.5 20.5a7.5 7.5 0 0 1 15 0"/>'),
  'bot': _stroke('<rect x="4" y="8" width="16" height="12" rx="3"/><path d="M12 8V4"/><circle cx="9" cy="14" r="1"/><circle cx="15" cy="14" r="1"/>'),
  'grid': _stroke('<rect x="4" y="4" width="6.5" height="6.5" rx="1.5"/><rect x="13.5" y="4" width="6.5" height="6.5" rx="1.5"/><rect x="4" y="13.5" width="6.5" height="6.5" rx="1.5"/><rect x="13.5" y="13.5" width="6.5" height="6.5" rx="1.5"/>'),
  'panel_close': _stroke('<rect x="3" y="3.5" width="18" height="17" rx="3"/><path d="M9 3.5v17"/><path d="m16 15-3-3 3-3"/>'),
  'panel_open': _stroke('<rect x="3" y="3.5" width="18" height="17" rx="3"/><path d="M9 3.5v17"/><path d="m13 9 3 3-3 3"/>'),
  'alert_triangle': _stroke('<path d="M10.3 3.9 1.8 18a2 2 0 0 0 1.7 3h17a2 2 0 0 0 1.7-3L13.7 3.9a2 2 0 0 0-3.4 0z"/><path d="M12 9v4"/><path d="M12 17h.01"/>'),
  'info': _stroke('<circle cx="12" cy="12" r="9"/><path d="M12 16v-4"/><path d="M12 8h.01"/>'),
};

/// Where a brand mark comes from: a single-path SVG in a brand source folder
/// (Simple Icons, CC0, or the official OpenAI logo) and the viewBox to keep.
final class BrandSource {
  const BrandSource(this.sourceFile, {this.viewBox = '0 0 24 24'});

  final String sourceFile;
  final String viewBox;
}

/// Brand marks by file name (without `.svg`); keep in sync with `BrandMark`.
const Map<String, BrandSource> brandSources = <String, BrandSource>{
  // Cropped to the blossom so the mark is optically centred.
  'openai': BrandSource('openai.svg', viewBox: '117.63 116.87 486 486'),
  'anthropic': BrandSource('anthropic.svg'),
  'gemini': BrandSource('googlegemini.svg'),
  'figma': BrandSource('figma.svg'),
  'github': BrandSource('github.svg'),
  'linear': BrandSource('linear.svg'),
  'sentry': BrandSource('sentry.svg'),
};

/// The asset for a brand mark whose source SVG is [source].
String brandSvg(String source, BrandSource brand) {
  final List<String> paths = <String>[for (final RegExpMatch match in RegExp(r' d="([^"]+)"').allMatches(source)) match.group(1)!];
  if (paths.length != 1) {
    throw FormatException('${brand.sourceFile}: expected one path, found ${paths.length}');
  }
  return _fill('<path d="${paths.single}"/>', viewBox: brand.viewBox);
}
