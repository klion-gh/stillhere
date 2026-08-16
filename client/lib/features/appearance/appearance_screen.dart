import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/appearance.dart';
import '../../core/theme.dart';
import '../../widgets/animated_background.dart';
import '../../widgets/gradient_avatar.dart';

class AppearanceScreen extends ConsumerWidget {
  const AppearanceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appearance = ref.watch(appearanceProvider);
    final controller = ref.read(appearanceProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('Оформление')),
      extendBodyBehindAppBar: true,
      body: NightBackdrop(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            children: [
              const _SectionTitle('Палитра'),
              const SizedBox(height: 14),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 200,
                  childAspectRatio: 1.55,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                ),
                itemCount: AppPalette.all.length,
                itemBuilder: (context, index) {
                  final palette = AppPalette.all[index];
                  return _PaletteCard(
                    palette: palette,
                    selected: palette.id == appearance.paletteId,
                    onTap: () => controller.setPalette(palette.id),
                  );
                },
              ),
              const SizedBox(height: 32),
              const _SectionTitle('Фон'),
              const SizedBox(height: 14),
              ...AppBackgroundOption.all.map(
                (option) => _BackgroundTile(
                  option: option,
                  selected: option.id == appearance.backgroundId,
                  onTap: () => controller.setBackground(option.id),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;

  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.8,
        color: AppColors.textMuted,
      ),
    );
  }
}

class _PaletteCard extends StatelessWidget {
  final AppPalette palette;
  final bool selected;
  final VoidCallback onTap;

  const _PaletteCard({required this.palette, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            // Preview the palette itself, not the active theme, so each card
            // shows what you'd actually be switching to.
            color: palette.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected ? palette.primary : palette.surfaceOutline,
              width: selected ? 2 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _Swatch(color: palette.primary),
                  const SizedBox(width: 6),
                  _Swatch(color: palette.accent),
                  const SizedBox(width: 6),
                  _Swatch(color: palette.surfaceHigh),
                  const Spacer(),
                  if (selected)
                    Icon(Icons.check_circle_rounded, size: 19, color: palette.primary),
                ],
              ),
              const Spacer(),
              Text(
                palette.name,
                style: TextStyle(
                  color: palette.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Container(
                height: 6,
                decoration: BoxDecoration(
                  gradient: palette.brandGradient,
                  borderRadius: BorderRadius.circular(100),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  final Color color;

  const _Swatch({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 16,
      height: 16,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

class _BackgroundTile extends StatelessWidget {
  final AppBackgroundOption option;
  final bool selected;
  final VoidCallback onTap;

  const _BackgroundTile({required this.option, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: selected ? AppColors.primary : AppColors.surfaceOutline,
                width: selected ? 2 : 1,
              ),
            ),
            child: Row(
              children: [
                // A live miniature of the effect, so the names aren't guesswork.
                ClipRRect(
                  borderRadius: const BorderRadius.horizontal(left: Radius.circular(17)),
                  child: SizedBox(
                    width: 96,
                    height: 68,
                    child: AnimatedBackdrop(
                      background: option.id,
                      child: const SizedBox.expand(),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        option.name,
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 15.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        option.description,
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 14),
                  child: Icon(
                    selected ? Icons.check_circle_rounded : Icons.circle_outlined,
                    color: selected ? AppColors.primary : AppColors.textMuted,
                    size: 21,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
