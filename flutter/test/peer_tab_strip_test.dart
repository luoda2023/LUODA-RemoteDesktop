import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luoda_flutter/common/widgets/peer_tab_strip.dart';

void main() {
  testWidgets('shows and switches all six desktop peer tabs', (tester) async {
    var selectedIndex = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            return Scaffold(
              body: PeerTabStrip(
                selectedIndex: selectedIndex,
                labels: const [
                  'Recent sessions',
                  'Favorites',
                  'Discovered',
                  'Address book',
                  'Accessible devices',
                  'VIP features',
                ],
                icons: const [
                  Icons.history_rounded,
                  Icons.star_rounded,
                  Icons.radar_rounded,
                  Icons.contacts_rounded,
                  Icons.devices_rounded,
                  Icons.workspace_premium_rounded,
                ],
                onSelected: (index) => setState(() => selectedIndex = index),
              ),
            );
          },
        ),
      ),
    );

    expect(find.byType(Icon), findsNWidgets(6));
    for (final label in const [
      'Recent sessions',
      'Favorites',
      'Discovered',
      'Address book',
      'Accessible devices',
      'VIP features',
    ]) {
      expect(find.byTooltip(label), findsOneWidget);
    }

    await tester.tap(find.byTooltip('Accessible devices'));
    await tester.pump();
    expect(selectedIndex, 4);
  });
}
