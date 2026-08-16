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

 return SingleChildScrollView(
 scrollDirection: Axis.horizontal,
 child: Container(
 height: 36,
 alignment: Alignment.center,
 child: Row(
 mainAxisSize: MainAxisSize.min,
 children: indexes.map((index) {
 final selected = selectedIndex == index;
 final indicatorColor =
 _indicatorColors[index % _indicatorColors.length];
 final label = labels[index];
 final shortLabel = _shortLabel(label);

 return Tooltip(
 message: label,
 preferBelow: false,
 child: Padding(
 padding: EdgeInsets.only(right: 6),
 child: Material(
 color: Colors.transparent,
 child: InkWell(
 onTap: () => onSelected(index),
 borderRadius: BorderRadius.circular(20),
 child: AnimatedContainer(
 duration: const Duration(milliseconds: 200),
 curve: Curves.easeOutQuad,
 padding: EdgeInsets.symmetric(
 horizontal: selected ? 12 : 8,
 vertical: 6,
 ),
 decoration: BoxDecoration(
 color: selected
 ? indicatorColor
 : indicatorColor.withOpacity(0.08),
 borderRadius: BorderRadius.circular(20),
 ),
 child: Row(
 mainAxisSize: MainAxisSize.min,
 children: [
 Icon(
 icons[index],
 size: 16,
 color: selected
 ? Colors.white
 : indicatorColor.withOpacity(0.6),
 ),
 if (selected) ...[
 SizedBox(width: 5),
 Text(
 shortLabel,
 style: TextStyle(
 fontSize: 12,
 color: Colors.white,
 fontWeight: FontWeight.w600,
 ),
 ),
 ],
 ],
 ),
 ),
 ),
 ),
 ),
 );
 }).toList(),
 ),
 ),
 );
 }

 /// Shorten the label to keep the pill compact.
 /// Uses the full label for single/short words,
 /// takes the first word for longer multi-word labels.
 String _shortLabel(String label) {
 final words = label.split(' ');
 if (words.length <= 2) return label;
 return words.first;
 }
}
