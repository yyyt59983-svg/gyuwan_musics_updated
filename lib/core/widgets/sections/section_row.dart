import 'package:flutter/material.dart';
import 'package:gyawun/core/widgets/tiles/section_row_tile.dart';

class SectionRow extends StatelessWidget {
  const SectionRow({super.key,required this.items});
  final List items;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
        // height: context.isWideScreen ? 270 : 216,
        height: 216,
        child: ListView.separated(
          addAutomaticKeepAlives: false,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          scrollDirection: Axis.horizontal,
          itemCount: items.length,
          separatorBuilder: (context, index) => const SizedBox(width: 4),
          itemBuilder: (context, index) {
            final item = items[index];

            return SectionRowTile(item: item);
          },
        ),
      );
  }
}