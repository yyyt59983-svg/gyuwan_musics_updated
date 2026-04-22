import 'dart:math';

import 'package:expandable_page_view/expandable_page_view.dart';
import 'package:flutter/material.dart';
import 'package:gyawun/core/widgets/tiles/section_list_tile.dart';

class SectionMultiColumn extends StatefulWidget {
  const SectionMultiColumn({super.key, required this.items, this.maxItem});

  final List items;
  final int? maxItem;

  @override
  State<SectionMultiColumn> createState() => _SectionMultiColumnState();
}

class _SectionMultiColumnState extends State<SectionMultiColumn> {
  late PageController controller;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    controller = PageController(
      viewportFraction:
          min(450, MediaQuery.sizeOf(context).width - 50) / MediaQuery.sizeOf(context).width,
    );
  }

  @override
  Widget build(BuildContext context) {
    final num = widget.maxItem ?? (widget.items.length <= 5 ? widget.items.length : 4);
    var pages = widget.items.length ~/ num;
    pages = (pages * num) < widget.items.length ? pages + 1 : pages;
    return ExpandablePageView.builder(
        controller: controller,
        padEnds: false,
        itemCount: pages,
        itemBuilder: (context, index) {
          int start = index * num;
          int end = start + num;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Column(
              children: widget.items.sublist(start, min(end, widget.items.length)).indexed.map((
                entry,
              ) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 1, horizontal: 4),
                  child: SectionListTile(
                    item: entry.$2,
                    isFirst: entry.$1 == 0,
                    isLast: entry.$1 == (num - 1) || entry.$2 == widget.items.last,
                  ),
                );
              }).toList(),
            ),
          );
        },
      );
    
  }
}