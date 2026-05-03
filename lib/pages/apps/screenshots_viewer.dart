import 'package:flutter/material.dart';

import 'widgets/flipper_image.dart';

class ScreenshotsViewer extends StatefulWidget {
  const ScreenshotsViewer({
    super.key,
    required this.screenshots,
    required this.initialIndex,
    this.title,
  });

  final List<String> screenshots;
  final int initialIndex;
  final String? title;

  static Future<void> open(
    BuildContext context, {
    required List<String> screenshots,
    required int initialIndex,
    String? title,
  }) {
    return Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => ScreenshotsViewer(
          screenshots: screenshots,
          initialIndex: initialIndex,
          title: title,
        ),
      ),
    );
  }

  @override
  State<ScreenshotsViewer> createState() => _ScreenshotsViewerState();
}

class _ScreenshotsViewerState extends State<ScreenshotsViewer> {
  late final PageController _page = PageController(initialPage: widget.initialIndex);
  late int _index = widget.initialIndex;

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          '${widget.title ?? ''} ${_index + 1}/${widget.screenshots.length}'.trim(),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: PageView.builder(
              controller: _page,
              itemCount: widget.screenshots.length,
              onPageChanged: (i) => setState(() => _index = i),
              itemBuilder: (context, i) {
                return InteractiveViewer(
                  child: Center(
                    child: AspectRatio(
                      aspectRatio: 256 / 128,
                      child: FlipperRemoteImage(url: widget.screenshots[i]),
                    ),
                  ),
                );
              },
            ),
          ),
          SizedBox(
            height: 64,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.all(8),
              itemCount: widget.screenshots.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                final selected = i == _index;
                return GestureDetector(
                  onTap: () => _page.animateToPage(
                    i,
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOut,
                  ),
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: selected ? Colors.white : Colors.white24,
                        width: selected ? 2 : 1,
                      ),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    padding: const EdgeInsets.all(2),
                    child: AspectRatio(
                      aspectRatio: 256 / 128,
                      child: FlipperRemoteImage(url: widget.screenshots[i]),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
