import 'package:flutter/material.dart';

import '../../components/navigation.dart';
import '../../components/open_url.dart';
import '../../services/localization/l10n.dart';
import 'widgets/pixel_button.dart';
import 'license_page.dart';

class AboutPage extends StatefulWidget {
  const AboutPage({super.key});

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _bgCtrl;
  late final Animation<double> _bgScale;

  @override
  void initState() {
    super.initState();
    _bgCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    )..repeat(reverse: true);
    _bgScale = Tween<double>(
      begin: 1.0,
      end: 1.2,
    ).animate(CurvedAnimation(parent: _bgCtrl, curve: Curves.linear));
  }

  @override
  void dispose() {
    _bgCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final titleSize = (mq.size.width * 0.07).clamp(36.0, 60.0);

    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          context.l10n.aboutTitle,
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            shadows: [Shadow(color: Colors.black54, blurRadius: 4)],
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: context.l10n.settingsTitle,
            onPressed: () => openRoute(context, AppRoute.appSettings),
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          AnimatedBuilder(
            animation: _bgScale,
            builder: (_, child) =>
                Transform.scale(scale: _bgScale.value, child: child),
            child: Image.asset('assets/img/bg.jpg', fit: BoxFit.cover),
          ),
          Positioned(
            top: mq.padding.top + kToolbarHeight + 14,
            left: 14,
            right: 14,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Row(
                  mainAxisSize: MainAxisSize.max,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    PixelButton.nav(
                      label: 'Github',
                      onTap: () => openUrl(context, _navBtns[0].url),
                    ),
                    PixelButton.nav(
                      label: 'Discord',
                      onTap: () => openUrl(context, _navBtns[1].url),
                    ),
                    PixelButton.nav(
                      label: 'Telegram',
                      onTap: () => openUrl(context, _navBtns[2].url),
                    ),
                    PixelButton.nav(
                      label: context.l10n.aboutShopEu,
                      onTap: () => openUrl(context, _navBtns[3].url),
                    ),
                    PixelButton.nav(
                      label: context.l10n.aboutShopRu,
                      onTap: () => openUrl(context, _navBtns[4].url),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            top: mq.padding.top + kToolbarHeight + 90,
            left: 24,
            right: 20,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Unleashed',
                  style: TextStyle(
                    fontFamily: 'GravityBold8',
                    fontSize: titleSize,
                    color: const Color(0xFFEF4848),
                    height: 1.0,
                    shadows: const [
                      Shadow(color: Color(0x809D988E), offset: Offset(6, 4)),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'firmware',
                  style: TextStyle(
                    fontFamily: 'GravityBold8',
                    fontSize: titleSize,
                    color: Colors.white,
                    height: 1.0,
                    shadows: const [
                      Shadow(color: Color(0x809D988E), offset: Offset(6, 4)),
                    ],
                  ),
                ),
                const SizedBox(height: 28),
                RichText(
                  text: TextSpan(
                    children: [
                      TextSpan(
                        text: 'FOR ',
                        style: TextStyle(
                          fontFamily: 'Born2bSportyV2',
                          fontSize: titleSize * 0.38,
                          color: Colors.white,
                          height: 1.0,
                        ),
                      ),
                      TextSpan(
                        text: 'FLIPPER ZERO',
                        style: TextStyle(
                          fontFamily: 'Born2bSportyV2',
                          fontSize: titleSize * 0.38,
                          color: const Color(0xFFFF9700),
                          height: 1.0,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            bottom: 20,
            left: 14,
            right: 14,
            child: Wrap(
              runSpacing: 10,
              alignment: WrapAlignment.spaceBetween,
              children: [
                for (final b in _extraButtons(context.l10n))
                  PixelButton.nav(
                    label: b.label,
                    onTap: () => b.url.isEmpty
                        ? Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const AppLicensePage(),
                            ),
                          )
                        : openUrl(context, b.url),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Btn {
  const _Btn(this.label, this.url);
  final String label;
  final String url;
}

const _navBtns = <_Btn>[
  _Btn('Github', 'https://github.com/DarkFlippers/unleashed-firmware'),
  _Btn('Discord', 'https://discord.unleashedflip.com/'),
  _Btn('Telegram', 'https://t.me/unleashed_fw'),
  _Btn('Shop (EU)', 'https://www.tindie.com/stores/flipmodules/'),
  _Btn('Shop (RU)', 'https://flipper.market'),
];

List<_Btn> _extraButtons(L10n s) => <_Btn>[
  _Btn(s.aboutAppGithub, 'https://github.com/apfxtech/qUnleashed'),
  _Btn(
    s.aboutDonateFirmware,
    'https://github.com/DarkFlippers/unleashed-firmware/blob/dev/ReadMe.md#%EF%B8%8F-please-support-development-of-the-project',
  ),
  _Btn(s.aboutDonateApp, 'https://boosty.to/apfxtech/donate'),
  _Btn('Telegram RU', 'https://t.me/flipperzero_unofficial_ru'),
  _Btn('Telegram EN', 'https://t.me/flipperzero_unofficial'),
  _Btn(s.aboutUnleashedWeb, 'https://flipperunleashed.com/'),
  _Btn(s.aboutApertureFoxWeb, 'https://aperturefox.ru/'),
  _Btn(s.aboutDevBuilds, 'https://dev.unleashedflip.com'),
  _Btn(s.aboutWebUpdater, 'https://web.unleashedflip.com/'),
  _Btn('Flipper Lab', 'https://lab.flipper.net/'),
  _Btn(s.aboutLicense, ''),
];
