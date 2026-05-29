import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../search/presentation/screens/search_screen.dart';
import '../../../library/presentation/screens/library_screen.dart';
import '../../../discovery/presentation/screens/discovery_screen.dart';
import '../../../download/presentation/screens/download_page.dart';
import '../../../player/presentation/widgets/mini_player_bar.dart';

class HomeScreen extends StatefulWidget {
  final Widget? child;
  final Map<int, Widget Function()>? screenFactories;

  const HomeScreen({super.key, this.child, this.screenFactories});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
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
    return Scaffold(
      body: Column(
        children: [
          Expanded(
            child: PageView.builder(
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
            ),
          ),
          const MiniPlayerBar(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: _onTabSelected,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.search), label: '搜索'),
          NavigationDestination(icon: Icon(Icons.explore), label: '发现'),
          NavigationDestination(icon: Icon(Icons.library_music), label: '音乐库'),
          NavigationDestination(icon: Icon(Icons.download), label: '下载'),
        ],
      ),
    );
  }
}
