import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../search/presentation/screens/search_screen.dart';
import '../../../library/presentation/screens/library_screen.dart';
import '../../../discovery/presentation/screens/discovery_screen.dart';
import '../../../download/presentation/screens/download_page.dart';
import '../../../player/presentation/widgets/mini_player_bar.dart';
import '../../../../core/router/app_router.dart' show TabHostScope;
import '../../../../core/theme/ui_style_provider.dart';
import '../../../../core/widgets/app_bottom_nav_bar.dart';
import '../../../../core/widgets/miuix_bottom_stack.dart';

class HomeScreen extends ConsumerStatefulWidget {
  final Widget? child;
  final Map<int, Widget Function()>? screenFactories;

  const HomeScreen({super.key, this.child, this.screenFactories});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  late final PageController _pageController;
  int _currentIndex = 0;
  Timer? _tabDebounce;

  static const _screenFactories = <int, Widget Function()>{
    0: SearchScreen.new,
    1: DiscoveryScreen.new,
    2: LibraryScreen.new,
    3: DownloadPage.new,
  };
  late final Map<int, Widget Function()> _activeScreenFactories;
  final Map<int, Widget> _screenCache = {};

  int get _tabCount => _activeScreenFactories.length;

  @override
  void initState() {
    super.initState();
    _activeScreenFactories = widget.screenFactories ?? _screenFactories;
    _pageController = PageController();
  }

  @override
  void dispose() {
    _tabDebounce?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final tabParam = GoRouterState.of(context).uri.queryParameters['tab'];
    final tab = int.tryParse(tabParam ?? '') ?? 0;
    if (tab >= 0 && tab < _tabCount && tab != _currentIndex) {
      _currentIndex = tab;
      if (_pageController.hasClients) {
        _pageController.jumpToPage(tab);
      }
    }
  }

  void _setTab(int i, {bool animate = true}) {
    if (i == _currentIndex || i < 0 || i >= _tabCount) return;
    setState(() => _currentIndex = i);
    final location = i == 0 ? '/' : '/?tab=$i';
    context.go(location);
    if (!_pageController.hasClients) return;
    if (animate) {
      _pageController.animateToPage(
        i,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    } else {
      _pageController.jumpToPage(i);
    }
  }

  void _onTabSelected(int i) {
    _tabDebounce?.cancel();
    _tabDebounce = Timer(const Duration(milliseconds: 80), () {
      if (!mounted) return;
      _setTab(i);
    });
  }

  void _onPageChanged(int i) {
    if (i == _currentIndex) return;
    setState(() => _currentIndex = i);
    context.go(i == 0 ? '/' : '/?tab=$i');
  }

  Widget _screenFor(int i) {
    return _screenCache.putIfAbsent(
      i,
      () => KeyedSubtree(
        key: PageStorageKey('tab_$i'),
        child: _activeScreenFactories[i]!(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final uiStyle = ref.watch(uiStyleProvider).style;

    // When a `ShellRoute` is above us it owns the whole bottom layer: it paints the
    // mini player once at the navigator level (so a push cannot stack two capsules)
    // *and* the nav capsule. Several routers mount this screen directly with no
    // shell at all, so it must also be able to stand alone.
    //
    // In both shapes exactly ONE nav bar and ONE player exist. Rendering the nav bar
    // unconditionally here was the mistake that doubled it (caught by a widget-tree
    // probe), because the shell was already supplying one.
    final host = TabHostScope.maybeOf(context);
    final ownsBottomLayer = host == null;

    final pageView = _buildPageView();

    if (!ownsBottomLayer) {
      // The shell draws everything below us.
      return Scaffold(extendBody: true, body: pageView);
    }

    final navBar = AppBottomNavBar(
      selectedIndex: _currentIndex,
      onDestinationSelected: _onTabSelected,
    );

    if (uiStyle == UiStyle.material) {
      return Scaffold(
        body: Column(
          children: [
            Expanded(child: pageView),
            const MiniPlayerBar(floating: true),
          ],
        ),
        bottomNavigationBar: navBar,
      );
    }

    return Scaffold(
      extendBody: true,
      body: MiuixBottomStack(
        style: UiStyle.miuix,
        navBar: navBar,
        // Nobody else is painting a player, so this stack must.
        showPlayer: true,
        child: pageView,
      ),
    );
  }

  Widget _buildPageView() {
    return PageView.builder(
      controller: _pageController,
      itemCount: _tabCount,
      onPageChanged: _onPageChanged,
      itemBuilder: (context, i) {
        return AnimatedBuilder(
          animation: _pageController,
          builder: (context, child) {
            var page = _currentIndex.toDouble();
            if (_pageController.hasClients &&
                _pageController.position.haveDimensions) {
              page = _pageController.page ?? page;
            }
            final delta = (page - i).abs().clamp(0.0, 1.0);
            final scale = 1.0 - (delta * 0.035);
            final translate = 18.0 * delta;
            return Transform.translate(
              offset: Offset(0, translate),
              child: Transform.scale(
                scale: scale,
                alignment: Alignment.center,
                child: child,
              ),
            );
          },
          child: TickerMode(
            enabled: i == _currentIndex,
            child: RepaintBoundary(child: _screenFor(i)),
          ),
        );
      },
    );
  }
}
