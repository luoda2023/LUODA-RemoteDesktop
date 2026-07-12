import 'package:flutter/material.dart';

class PeerTabStrip extends StatelessWidget {
  const PeerTabStrip({
    super.key,
    required this.selectedIndex,
    required this.labels,
    required this.icons,
    required this.onSelected,
    this.visibleIndexes,
  });

  final int selectedIndex;
  final List<String> labels;
  final List<IconData> icons;
  final ValueChanged<int> onSelected;
  final List<int>? visibleIndexes;

  static const _indicatorColors = [
    Color(0xFF4A90D9),
    Color(0xFFE74C3C),
    Color(0xFF2E9D58),
    Color(0xFFD98208),
    Color(0xFF8E4DA8),
    Color(0xFF148D83),
  ];

  @override
  Widget build(BuildContext context) {
    final indexes = visibleIndexes ?? List.generate(icons.length, (i) => i);
    final tabTheme = Theme.of(context).tabBarTheme;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: indexes.map((index) {
          final selected = selectedIndex == index;
          final indicatorColor =
              _indicatorColors[index % _indicatorColors.length];
          final unselectedColor = (tabTheme.unselectedLabelColor ?? Colors.grey)
              .withOpacity(0.65);
          return Tooltip(
            message: labels[index],
            preferBelow: false,
            child: InkWell(
              onTap: () => onSelected(index),
              child: Container(
                width: 42,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      width: selected ? 3 : 0,
                      color: selected ? indicatorColor : Colors.transparent,
                    ),
                  ),
                ),
                child: Icon(
                  icons[index],
                  size: 20,
                  color: selected ? indicatorColor : unselectedColor,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
