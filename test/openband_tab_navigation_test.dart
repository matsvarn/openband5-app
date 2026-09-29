import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/app.dart' show releaseDomainForRoute;
import 'package:openstrap_edge/notify/tap_router.dart';
import 'package:openstrap_edge/openband/journal_controls.dart';
import 'package:openstrap_edge/openband/release_scope.dart';
import 'package:openstrap_edge/openband/tab_bar.dart';
import 'package:openstrap_edge/openband/theme.dart';
import 'package:openstrap_edge/ui2/app_shell.dart';

Widget _shell(
  GlobalKey<AppShellState> key, {
  GlobalKey<NavigatorState>? rootNavigatorKey,
}) => MaterialApp(
  navigatorKey: rootNavigatorKey,
  theme: openBandTheme(Brightness.light),
  home: AppShell(
    key: key,
    releaseStyle: true,
    domains: kOpenBandReleaseDomains,
    builder: (context, domain) => Scaffold(
      body: Column(
        key: ValueKey('tab-root-layout-${domain.name}'),
        children: [
          Text('Root ${domain.name}'),
          TextButton(
            onPressed: () => pushInTab(
              context,
              MaterialPageRoute<void>(
                builder: (_) => Scaffold(
                  appBar: AppBar(title: Text('Detail ${domain.name}')),
                  body: ListView(
                    children: [
                      Text('Content ${domain.name}'),
                      const SizedBox(height: 1000),
                      TextButton(
                        onPressed: () {},
                        child: Text('Last ${domain.name} action'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            child: Text('Open ${domain.name} detail'),
          ),
          TextButton(
            onPressed: () => pushFullScreen(
              context,
              MaterialPageRoute<void>(
                builder: (_) => const Scaffold(body: Text('Full-screen flow')),
              ),
            ),
            child: const Text('Open full-screen flow'),
          ),
          TextButton(
            onPressed: () =>
                showOpenBandJournalInfo(context, title: 'Root sheet'),
            child: const Text('Open sheet'),
          ),
        ],
      ),
    ),
  ),
);

Future<void> _tapTab(WidgetTester tester, ShellDomain domain) async {
  await tester.tap(find.byKey(ValueKey('ob-tab-${domain.name}')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('tab details retain separate stacks across switches', (
    tester,
  ) async {
    await tester.pumpWidget(_shell(GlobalKey<AppShellState>()));
    await tester.tap(find.text('Open home detail'));
    await tester.pumpAndSettle();
    expect(find.text('Detail home'), findsOneWidget);
    expect(find.byType(OBTabBar), findsOneWidget);

    await _tapTab(tester, ShellDomain.sleep);
    await tester.tap(find.text('Open sleep detail'));
    await tester.pumpAndSettle();
    await _tapTab(tester, ShellDomain.home);
    expect(find.text('Detail home'), findsOneWidget);
    await _tapTab(tester, ShellDomain.sleep);
    expect(find.text('Detail sleep'), findsOneWidget);
  });

  testWidgets('tapping the selected tab returns to its root', (tester) async {
    await tester.pumpWidget(_shell(GlobalKey<AppShellState>()));
    await tester.tap(find.text('Open home detail'));
    await tester.pumpAndSettle();
    await _tapTab(tester, ShellDomain.home);
    expect(find.text('Root home'), findsOneWidget);
    expect(find.text('Detail home'), findsNothing);
    expect(find.byType(OBTabBar), findsOneWidget);
  });

  testWidgets('last detail action can scroll above the floating bar', (
    tester,
  ) async {
    await tester.pumpWidget(_shell(GlobalKey<AppShellState>()));
    await tester.tap(find.text('Open home detail'));
    await tester.pumpAndSettle();
    final lastAction = find.text('Last home action');
    await tester.scrollUntilVisible(
      lastAction,
      400,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();
    expect(
      tester.getRect(lastAction).bottom,
      lessThan(tester.getRect(find.byType(OBTabBar)).top),
    );
  });

  testWidgets('covered tab root keeps its inset during detail pop animation', (
    tester,
  ) async {
    await tester.pumpWidget(_shell(GlobalKey<AppShellState>()));
    await tester.tap(find.text('Open home detail'));
    await tester.pumpAndSettle();
    final root = find.byKey(
      const ValueKey('tab-root-layout-home'),
      skipOffstage: false,
    );
    final beforePop = tester.getSize(root);

    await tester.tap(find.byType(BackButton));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    expect(find.text('Detail home'), findsOneWidget);
    expect(tester.getSize(root), beforePop);

    await tester.pumpAndSettle();
    expect(tester.getSize(root).height, greaterThan(beforePop.height));
  });

  testWidgets('kept notification detail opens inside its owning tab', (
    tester,
  ) async {
    final key = GlobalKey<AppShellState>();
    await tester.pumpWidget(_shell(key));
    await _tapTab(tester, ShellDomain.sleep);
    final target = resolveTapRoute(kRouteProfile);
    final domain = releaseDomainForRoute(target.screen!, reduced: true);
    key.currentState!.open(domain, const Scaffold(body: Text('Band detail')));
    await tester.pumpAndSettle();
    expect(domain, ShellDomain.home);
    expect(find.text('Band detail'), findsOneWidget);
    expect(find.byType(OBTabBar), findsOneWidget);
    expect(
      tester.widget<OBTabBar>(find.byType(OBTabBar)).selected,
      ShellDomain.home,
    );
    await _tapTab(tester, ShellDomain.sleep);
    await _tapTab(tester, ShellDomain.home);
    expect(find.text('Band detail'), findsOneWidget);
  });

  testWidgets('notification on the selected tab preserves its prior detail', (
    tester,
  ) async {
    final key = GlobalKey<AppShellState>();
    await tester.pumpWidget(_shell(key));
    await tester.tap(find.text('Open home detail'));
    await tester.pumpAndSettle();
    key.currentState!.open(
      ShellDomain.home,
      const Scaffold(body: Text('Notification detail')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Notification detail'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Detail home'), findsOneWidget);
    expect(find.byType(OBTabBar), findsOneWidget);
  });

  testWidgets('full-screen flow covers the tab bar', (tester) async {
    await tester.pumpWidget(_shell(GlobalKey<AppShellState>()));
    await tester.tap(find.text('Open full-screen flow'));
    await tester.pumpAndSettle();
    expect(find.text('Full-screen flow'), findsOneWidget);
    expect(find.byType(OBTabBar), findsNothing);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(OBTabBar), findsOneWidget);
  });

  testWidgets('a sheet from a tab uses the root navigator', (tester) async {
    final rootKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      _shell(GlobalKey<AppShellState>(), rootNavigatorKey: rootKey),
    );
    await tester.tap(find.text('Open sheet'));
    await tester.pumpAndSettle();
    expect(find.text('Root sheet'), findsOneWidget);
    expect(rootKey.currentState!.canPop(), isTrue);
    await rootKey.currentState!.maybePop();
    await tester.pumpAndSettle();
    expect(rootKey.currentState!.canPop(), isFalse);
  });

  testWidgets('system back pops the inner detail before the shell', (
    tester,
  ) async {
    await tester.pumpWidget(_shell(GlobalKey<AppShellState>()));
    await tester.tap(find.text('Open home detail'));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Root home'), findsOneWidget);
    expect(find.byType(OBTabBar), findsOneWidget);

    await tester.tap(find.text('Open home detail'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('Root home'), findsOneWidget);
  });
}
