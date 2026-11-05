import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'desktop_ambient_background.dart';
import 'desktop_now_playing_panel.dart';
import 'desktop_page_surface.dart';
import 'desktop_panel_provider.dart';
import 'desktop_player_bar.dart';
import 'desktop_shell_policy.dart';
import 'desktop_sidebar.dart';
import 'desktop_tokens.dart';

/// The desktop application chrome.
///
/// Layout at >= 1180 px:
///   sidebar | rounded content plate | now-playing panel
///   player bar (full width)
///
/// Below 1180 px the panel is hidden and the sidebar loses its labels; the
/// player bar compacts. The shell never falls back to the phone navigation
/// capsule, so resizing a desktop window cannot resurrect the mobile UI.
class DesktopShell extends ConsumerWidget {
  final Widget child;
  final String? path;

  const DesktopShell({super.key, required this.child, this.path});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final media = MediaQuery.of(context);
    final view = View.of(context);
    final viewLogicalSize = view.physicalSize / view.devicePixelRatio;
    // Flutter 3.47's Windows embedder can report the physical client size as
    // the logical size while also reporting a >1 device pixel ratio (observed
    // on a 175% display: MediaQuery 1355x832, dpr 1.75, client 1355x832). That
    // makes every logical widget 1.75x too large and clips the right-hand panel.
    // When the reported size is clearly the physical size, lay out against the
    // size the view itself implies.
    final needsSizeCorrection =
        viewLogicalSize.width > 0 &&
        media.size.width > viewLogicalSize.width * 1.05;
    final correctedSize = needsSizeCorrection ? viewLogicalSize : media.size;
    final width = correctedSize.width;
    final panelTab = ref.watch(desktopPanelTabProvider);
    final userCollapsed = ref.watch(desktopSidebarCollapsedProvider);
    final collapsed =
        userCollapsed || width < DesktopShellPolicy.sidebarLabelBreakpoint;
    final showPanel =
        panelTab != null && width >= DesktopShellPolicy.mediumBreakpoint;
    final compactPlayer = width < DesktopShellPolicy.mediumBreakpoint;

    return MediaQuery(
      data: media.copyWith(size: correctedSize),
      child: ScrollConfiguration(
        // Desktop pages use explicit, styled scrollbars where they need one.
        // The automatic Material scrollbar otherwise paints a second, native-
        // looking track at the bottom of a vertical list.
        behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
        child: DesktopAmbientBackground(
          child: Stack(
            fit: StackFit.expand,
            children: [
              Column(
                children: [
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        DesktopSidebar(collapsed: collapsed, currentPath: path),
                        const SizedBox(width: DesktopSpacing.sm),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(
                              top: DesktopSpacing.sm,
                              bottom: DesktopSpacing.sm,
                            ),
                            child: DesktopPageSurface(child: child),
                          ),
                        ),
                        if (showPanel) ...[
                          const SizedBox(width: DesktopSpacing.sm),
                          SizedBox(
                            width: DesktopShellPolicy.nowPlayingWidth,
                            child: const DesktopNowPlayingPanel(),
                          ),
                        ],
                        const SizedBox(width: DesktopSpacing.sm),
                      ],
                    ),
                  ),
                  DesktopPlayerBar(compact: compactPlayer),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
