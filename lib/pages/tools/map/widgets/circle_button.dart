part of '../page.dart';

class _CircleButton extends StatelessWidget {
  const _CircleButton({
    required this.colors,
    required this.icon,
    required this.onTap,
  });

  final QAppColors colors;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 42,
      height: 42,
      child: Material(
        color: colors.card,
        shape: const CircleBorder(),
        elevation: 3,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          customBorder: const CircleBorder(),
          radius: 24,
          onTap: onTap,
          child: Center(child: Icon(icon, color: colors.accent, size: 22)),
        ),
      ),
    );
  }
}
