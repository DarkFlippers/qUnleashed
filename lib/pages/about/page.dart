import 'dart:ui';

import 'package:flutter/material.dart';

import '../../theme.dart';
import '../../widgets/open_url.dart';
import 'license_page.dart';

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});
  static const _licenseColor = Color(0xFF2F7DA8);
  static const _links = <_AboutLink>[
    _AboutLink(
      icon: Icons.code,
      color: Color(0xFF56616D),
      title: 'Firmware GitHub',
      subtitle: 'DarkFlippers/unleashed-firmware',
      url: 'https://github.com/DarkFlippers/unleashed-firmware',
    ),
    _AboutLink(
      icon: Icons.code,
      color: Color(0xFF56616D),
      title: 'App GitHub',
      subtitle: 'apfxtech/qUnleashed',
      url: 'https://github.com/apfxtech/qUnleashed',
    ),
    _AboutLink(
      icon: Icons.send,
      color: Color(0xFF2E83A8),
      title: 'Telegram Community (EN)',
      subtitle: '@flipperzero_unofficial',
      url: 'https://t.me/flipperzero_unofficial',
    ),
    _AboutLink(
      icon: Icons.send,
      color: Color(0xFF2E83A8),
      title: 'Telegram Community (RU)',
      subtitle: '@flipperzero_unofficial_ru',
      url: 'https://t.me/flipperzero_unofficial_ru',
    ),
    _AboutLink(
      icon: Icons.forum,
      color: Color(0xFF5865A8),
      title: 'Discord Community',
      subtitle: 'discord.gg',
      url: 'https://discord.com/invite/HmY4xSw7Zt',
    ),
    _AboutLink(
      icon: Icons.storefront,
      color: Color(0xFFB86F16),
      title: 'Store (EN)',
      subtitle: 'Tindie — flipmodules',
      url: 'https://www.tindie.com/stores/flipmodules/',
    ),
    _AboutLink(
      icon: Icons.storefront,
      color: Color(0xFFB86F16),
      title: 'Store (RU)',
      subtitle: 'flipper.market',
      url: 'https://flipper.market/',
    ),
    _AboutLink(
      icon: Icons.favorite,
      color: Color(0xFFB95D58),
      title: 'Support firmware authors',
      subtitle: 'DarkFlippers',
      url: 'https://github.com/DarkFlippers/unleashed-firmware/blob/dev/ReadMe.md#%EF%B8%8F-please-support-development-of-the-project',
    ),
    // _AboutLink(
    //   icon: Icons.favorite,
    //   color: Color(0xFFB95D58),
    //   title: 'Support app author',
    //   subtitle: 'boosty.to/apfxtech',
    //   url: 'https://boosty.to/apfxtech', - не работает
    // ),
    _AboutLink(
      icon: Icons.public,
      color: Color(0xFF9A5F94),
      title: 'Unleashed website',
      subtitle: 'flipperunleashed.com',
      url: 'https://flipperunleashed.com/',
    ),
    _AboutLink(
      icon: Icons.public,
      color: Color(0xFF9A5F94),
      title: ' ApertureFox website',
      subtitle: 'aperturefox.ru',
      url: 'https://aperturefox.ru/',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final overlay = colors.isDark
        ? Colors.black.withValues(alpha: 0.22)
        : Colors.black.withValues(alpha: 0.10);
    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.white,
        title: const Text(
          'About',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            shadows: [Shadow(color: Colors.black54, blurRadius: 4)],
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset('assets/bg-big.jpg', fit: BoxFit.cover),
          ColoredBox(color: overlay),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                final columns = width >= 1100
                    ? 4
                    : width >= 760
                        ? 3
                        : width >= 520
                            ? 2
                            : 1;
                final licenseTile = _LicenseTile(
                  color: _licenseColor,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const AppLicensePage()),
                  ),
                );
                final linkTiles = [
                  for (final link in _links)
                    _LinkTile(
                      link: link,
                      onTap: () => openUrl(context, link.url),
                    ),
                ];
                if (columns == 1) {
                  return ListView(
                    padding: const EdgeInsets.fromLTRB(14, 8, 14, 24),
                    children: [
                      licenseTile,
                      const SizedBox(height: 8),
                      for (final tile in linkTiles) ...[
                        tile,
                        const SizedBox(height: 8),
                      ],
                    ],
                  );
                }
                return SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(14, 8, 14, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      licenseTile,
                      const SizedBox(height: 10),
                      GridView.count(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        crossAxisCount: columns,
                        mainAxisSpacing: 10,
                        crossAxisSpacing: 10,
                        childAspectRatio: 3.6,
                        children: linkTiles,
                      ),
                    ],
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

class _LinkTile extends StatelessWidget {
  const _LinkTile({required this.link, required this.onTap});

  final _AboutLink link;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _GlassCard(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: link.color,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(link.icon, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      link.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      link.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const Padding(
                padding: EdgeInsets.only(left: 6),
                child: Icon(Icons.open_in_new, color: Colors.white70, size: 18),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LicenseTile extends StatelessWidget {
  const _LicenseTile({required this.onTap, required this.color});

  final VoidCallback onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return _GlassCard(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.description_outlined,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'License',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'GNU General Public License v3',
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.white70),
            ],
          ),
        ),
      ),
    );
  }
}

class _GlassCard extends StatelessWidget {
  const _GlassCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
          ),
          child: Material(
            color: Colors.transparent,
            child: child,
          ),
        ),
      ),
    );
  }
}

class _AboutLink {
  const _AboutLink({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.url,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final String url;
}
