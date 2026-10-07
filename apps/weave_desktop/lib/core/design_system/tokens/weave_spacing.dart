import 'package:flutter/painting.dart';

/// Spacing scale used for gaps and padding in the design.
abstract final class WeaveSpacing {
  static const double s2 = 2;
  static const double s4 = 4;
  static const double s6 = 6;
  static const double s8 = 8;
  static const double s10 = 10;
  static const double s12 = 12;
  static const double s14 = 14;
  static const double s16 = 16;
  static const double s18 = 18;
  static const double s20 = 20;
  static const double s24 = 24;
  static const double s28 = 28;
  static const double s32 = 32;
  static const double s40 = 40;
  static const double s48 = 48;
}

/// Corner radii used in the design.
abstract final class WeaveRadii {
  static const double xs = 4;
  static const double sm = 6;
  static const double md = 8;
  static const double control = 10;
  static const double card = 12;
  static const double panel = 14;
  static const double dialog = 16;
  static const double window = 20;
  static const double pill = 999;

  static const BorderRadius xsAll = BorderRadius.all(Radius.circular(xs));
  static const BorderRadius smAll = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius mdAll = BorderRadius.all(Radius.circular(md));
  static const BorderRadius controlAll = BorderRadius.all(Radius.circular(control));
  static const BorderRadius cardAll = BorderRadius.all(Radius.circular(card));
  static const BorderRadius panelAll = BorderRadius.all(Radius.circular(panel));
  static const BorderRadius dialogAll = BorderRadius.all(Radius.circular(dialog));
  static const BorderRadius pillAll = BorderRadius.all(Radius.circular(pill));
}

/// Fixed sizes of the app layout.
abstract final class WeaveLayout {
  static const Size minimumWindow = Size(1100, 720);
  static const Size defaultWindow = Size(1600, 1000);

  /// Full-width macOS chrome above every app column, keeping the native
  /// traffic-light controls away from sidebar dividers and content. Used
  /// until macOS reports where it draws the traffic lights; this is the
  /// native title bar height measured on current macOS (lights centred at 16).
  static const double windowTitleBarHeight = 32;

  /// Gap between the custom title bar and the first item in each app column.
  static const double windowContentTopPadding = 8;

  /// How close to the end a log must be scrolled to keep following new lines.
  static const double followTailThreshold = 24;

  /// Room kept left of the title-bar controls for the native traffic lights.
  static const double windowControlsInset = 84;

  /// The shortest and tallest title bar when it is sized around the native
  /// traffic lights (twice their distance from the top of the window).
  static const double windowTitleBarMinHeight = 32;
  static const double windowTitleBarMaxHeight = 52;

  /// Back, forward and sidebar buttons in the title bar, sized to read
  /// alongside the traffic lights.
  static const double windowControlSize = 28;

  static const double sidebarExpanded = 288;
  static const double sidebarCollapsed = 64;

  /// Width used when Command-B hides the fixed icon rail.
  static const double sidebarHidden = 0;

  /// Width at which a resizing sidebar switches between its full layout and
  /// the icon rail, and the side it snaps to when a drag ends.
  static const double sidebarLayoutBreakpoint = (sidebarExpanded + sidebarCollapsed) / 2;

  /// Sidebar navigation hit area in both expanded and collapsed states.
  static const double sidebarItemHeight = 48;

  /// Thin contextual-sidebar drag target, highlighted only while in use.
  static const double sidebarResizeHandleWidth = 4;

  /// Trailing action (status dot or delete button) of a recent-workflow row.
  static const double sidebarRowActionSize = 24;

  /// Weave mark size in the app sidebar.
  static const double sidebarLogoSize = 38;

  /// Window width from which the sidebar starts expanded.
  static const double sidebarExpandBreakpoint = 1360;

  static const double divider = 1;

  /// The ambient glow ellipse behind the top of each screen, placed relative
  /// to the workspace (x 380 with the 288 px sidebar, x 164 with the 72 px one).
  static const Size ambientGlowSize = Size(900, 720);
  static const Offset ambientGlowOffset = Offset(92, -420);

  static const double chatPanelWidth = 440;
  static const double pageGutter = 34;
  static const double controlHeight = 44;

  /// Narrowest regular button (the dialogs' "Cancel" and "Reset" in the design).
  static const double buttonMinWidth = 112;
  static const double statusPillHeight = 26;

  /// Compact status used where a card title needs the full first row.
  static const double compactStatusPillHeight = 20;

  /// Width of the New Task form.
  static const double newTaskFormWidth = 824;

  /// Side column width and the breakpoint for it, used by Plan Approval.
  static const double newTaskPreviewWidth = 402;
  static const double newTaskPreviewBreakpoint = 1200;

  /// Agent pipeline card height and Start button width in New Task.
  static const double newTaskAgentCardHeight = 130;
  static const double newTaskStartButtonWidth = 246;

  /// Home card width for a recent workflow.
  static const double recentWorkflowCardWidth = 260;

  /// Narrowest agent pipeline that fits its three cards side by side without
  /// truncating "Review & test" next to its status pill; below it they stack.
  static const double newTaskPipelineRowMinWidth = 788;

  /// Available content width where Workflow Running splits timeline/details.
  static const double workflowSplitBreakpoint = 1000;

  /// Standard dialog size in the dialog-flow frames.
  static const double dialogWidth = 660;
  static const double dialogHeight = 510;

  /// Workspace switcher and chat-menu dimensions.
  static const double popoverWidth = 320;
  static const double popoverItemHeight = 56;

  /// Account control and menu dimensions in the sidebar footer.
  static const double accountAvatarSize = 40;
  static const double accountMenuWidth = 320;

  /// Width of app notifications anchored to the bottom-right corner.
  static const double toastWidth = 360;

  /// Distance of a toast from the top of the window, below the title bar.
  static const double toastTop = 40;

  /// Input dimensions used by repository access and role selectors.
  static const double segmentedControlHeight = 35;

  /// Space around and between segments, so the selected background never
  /// touches the border or its neighbour.
  static const double segmentedControlInset = 4;
  static const double segmentedControlGap = 4;
  static const double selectHeight = 52;
  static const double checkboxSize = 16;
  static const double switchWidth = 44;
  static const double switchHeight = 24;
  static const double switchThumbSize = 18;

  /// Space between a tooltip and the edge of the element it describes.
  static const double tooltipGap = 8;

  /// Compact gap between an icon-rail item and its tooltip.
  static const double railTooltipGap = 12;

  /// Closest a tooltip may come to the window edge.
  static const double tooltipScreenMargin = 10;

  /// Bar height of a usage meter on the Agents screen.
  static const double usageMeterHeight = 6;

  /// Agents screen grid: narrowest card (252 in the design) and most columns.
  static const double agentCardMinWidth = 252;
  static const int agentGridMaxColumns = 3;

  /// Integrations grid: narrowest server card (386 in the design) and most columns.
  static const double integrationCardMinWidth = 320;
  static const int integrationGridMaxColumns = 2;

  /// Content width from which Connection health sits beside the cards.
  static const double agentsSideColumnBreakpoint = 1100;

  /// Scrollbar thumb width and its inset from the viewport edge.
  static const double scrollbarThickness = 6;
  static const double scrollbarMargin = 3;

  /// Space reserved beside vertical scroll views so the thumb never covers content.
  static const double scrollbarGutter = scrollbarThickness + 2 * scrollbarMargin;

  /// Split diff in the Code Review screen: file header, column headers, one
  /// code line, the line-number gutter and the +/- marker after it.
  static const double diffFileHeaderHeight = 56;
  static const double diffColumnHeaderHeight = 36;
  static const double diffLineHeight = 20;
  static const double diffGutterWidth = 40;
  static const double diffNumberWidth = 32;
  static const double diffMarkerWidth = 16;

  /// Code Review columns: changed files on the left, checks on the right.
  static const double codeReviewFilesWidth = 242;
  static const double codeReviewChecksWidth = 320;

  /// Content width from which the three Code Review columns sit side by side.
  static const double codeReviewBreakpoint = 1100;

  /// Height of the file list and diff when the columns stack.
  static const double codeReviewStackedDiffHeight = 520;

  /// Settings uses the three-column design at this available page width.
  static const double settingsColumnsBreakpoint = 1120;

  /// Fixed side-column widths in the Settings design.
  static const double settingsNavigationWidth = 230;
  static const double settingsPolicyWidth = 312;

  /// Secondary navigation beside the fixed icon rail.
  static const double contextualSidebarWidth = 240;

  /// Width where dragging the contextual sidebar snaps between shown/hidden.
  static const double contextualSidebarBreakpoint = 120;

  /// Widest the contextual sidebar may become while dragging.
  static const double contextualSidebarMaxWidth = contextualSidebarWidth;

  /// Workflow preview and execution timeline marker dimensions.
  static const double timelineMarkerSize = 36;
  static const double timelineStrokeWidth = 2;

  /// Responsive showcase widths used only by the component gallery.
  static const double galleryTileWidth = 360;
  static const double galleryTimelineWidth = 520;
}

/// Icon sizes used by compact controls and menu rows.
abstract final class WeaveIconSize {
  static const double checkbox = 11;
  static const double segmented = 13;
  static const double compact = 16;
  static const double control = 18;
}
