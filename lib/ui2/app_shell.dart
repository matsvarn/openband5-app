import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../openband/theme.dart';
import 'theme.dart' show C;
import 'grammar.dart' show Pressable;

enum ShellDomain {
  home('Übersicht', LucideIcons.house, C.domHome),
  health('Gesundheit', LucideIcons.heart, C.domHealth),
  workout('Training', LucideIcons.dumbbell, C.domMove),
  wellness('Journal', LucideIcons.notebookPen, C.domMind);

  const ShellDomain(this.label, this.icon, this.accent);
  final String label;
  final IconData icon;
  final Color accent;
}

class AppShell extends StatefulWidget {
  final Widget Function(BuildContext, ShellDomain) builder;
  final ShellDomain initial;
  final ValueChanged<ShellDomain>? onSelect;
  final Widget? banner;
  const AppShell({
    super.key,
    required this.builder,
    this.initial = ShellDomain.home,
    this.onSelect,
    this.banner,
  });
  @override
  State<AppShell> createState() => AppShellState();
}

class AppShellState extends State<AppShell> {
  late ShellDomain _current = widget.initial;
  late final Set<ShellDomain> _built = {widget.initial};
  final _keys = {
    for (final d in ShellDomain.values) d: GlobalKey<NavigatorState>(),
  };
  late final _observers = {
    for (final d in ShellDomain.values) d: _TabObserver(_routeChanged),
  };
  void _routeChanged() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
  }

  void select(ShellDomain domain) {
    setState(() {
      _current = domain;
      _built.add(domain);
    });
    widget.onSelect?.call(domain);
  }

  void open(ShellDomain domain, Widget screen) {
    select(domain);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _keys[domain]!.currentState?.push(
        MaterialPageRoute<void>(builder: (_) => screen),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    final atRoot = _observers[_current]!.depth <= 1;
    return PopScope(
      canPop: atRoot,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _keys[_current]!.currentState?.maybePop();
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: p.dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
        child: Scaffold(
          backgroundColor: p.canvas,
          body: SafeArea(
            bottom: false,
            child: Column(
              children: [
                Expanded(
                  child: IndexedStack(
                    index: _current.index,
                    children: [
                      for (final domain in ShellDomain.values)
                        if (_built.contains(domain))
                          Navigator(
                            key: _keys[domain],
                            observers: [_observers[domain]!],
                            onGenerateRoute: (_) => MaterialPageRoute<void>(
                              builder: (c) => widget.builder(c, domain),
                            ),
                          )
                        else
                          const SizedBox.shrink(),
                    ],
                  ),
                ),
                if (widget.banner != null && atRoot) widget.banner!,
              ],
            ),
          ),
          bottomNavigationBar: !atRoot
              ? null
              : Container(
                  decoration: BoxDecoration(
                    color: p.card,
                    border: Border(top: BorderSide(color: p.line)),
                  ),
                  child: SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(10, 4, 10, 0),
                      child: Row(
                        children: [
                          for (final domain in ShellDomain.values)
                            Expanded(child: _tab(context, domain)),
                        ],
                      ),
                    ),
                  ),
                ),
        ),
      ),
    );
  }

  Widget _tab(BuildContext context, ShellDomain domain) {
    final p = OB.of(context);
    final color = domain == _current ? p.action : p.muted;
    return Semantics(
      excludeSemantics: true,
      onTap: () => select(domain),
      selected: domain == _current,
      button: true,
      label: domain.label,
      child: Pressable(
        onTap: () => select(domain),
        child: ExcludeSemantics(
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(domain.icon, size: 22, color: color),
                const SizedBox(height: 4),
                Text(
                  domain.label,
                  style: p.text(12, weight: FontWeight.w500, color: color),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TabObserver extends NavigatorObserver {
  final VoidCallback changed;
  int depth = 0;
  _TabObserver(this.changed);
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    depth++;
    changed();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    depth--;
    changed();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    depth--;
    changed();
  }
}
