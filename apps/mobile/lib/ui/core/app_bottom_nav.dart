import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:math' as math;

import 'app_theme.dart';

class AppBottomNav extends StatelessWidget {
  const AppBottomNav({
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.destinations,
    this.trailingActions = const [],
    super.key,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final List<NavigationDestination> destinations;
  final List<Widget> trailingActions;

  @override
  Widget build(BuildContext context) {
    const barHeight = 68.0;
    const indicatorHeight = 52.0;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      child: Row(
        children: [
          Expanded(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(40),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x99000000),
                    blurRadius: 28,
                    offset: Offset(0, 10),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(40),
                child: SizedBox(
                  height: barHeight,
                  child: Material(
                    color: appWhite,
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        if (destinations.isEmpty) {
                          return const SizedBox.shrink();
                        }
                        final itemWidth =
                            constraints.maxWidth / destinations.length;
                        final indicatorWidth = math.min(72.0, itemWidth - 12);
                        final safeIndex = selectedIndex
                            .clamp(0, destinations.length - 1)
                            .toInt();

                        return Stack(
                          children: [
                            AnimatedPositioned(
                              duration: reduceMotion
                                  ? Duration.zero
                                  : const Duration(milliseconds: 220),
                              curve: Curves.easeInOutCubic,
                              left:
                                  (itemWidth * safeIndex) +
                                  ((itemWidth - indicatorWidth) / 2),
                              top: (barHeight - indicatorHeight) / 2,
                              width: indicatorWidth,
                              height: indicatorHeight,
                              child: IgnorePointer(
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: appLime,
                                    borderRadius: BorderRadius.circular(32),
                                  ),
                                ),
                              ),
                            ),
                            Row(
                              children: [
                                for (
                                  var index = 0;
                                  index < destinations.length;
                                  index++
                                )
                                  Expanded(
                                    child: Semantics(
                                      button: true,
                                      selected: index == safeIndex,
                                      label: destinations[index].label,
                                      child: ExcludeSemantics(
                                        child: InkWell(
                                          onTap: () {
                                            if (index != safeIndex) {
                                              HapticFeedback.selectionClick();
                                            }
                                            onDestinationSelected(index);
                                          },
                                          splashColor: appBlack.withValues(
                                            alpha: .08,
                                          ),
                                          highlightColor: appBlack.withValues(
                                            alpha: .04,
                                          ),
                                          focusColor: appBlack.withValues(
                                            alpha: .12,
                                          ),
                                          child: Tooltip(
                                            message: destinations[index].label,
                                            child: Center(
                                              child: IconTheme(
                                                // Dark icons retain contrast on both the white bar and turquoise indicator.
                                                data: IconThemeData(
                                                  color: appBlack,
                                                  size: 26,
                                                ),
                                                child: AnimatedSwitcher(
                                                  duration: reduceMotion
                                                      ? Duration.zero
                                                      : const Duration(
                                                          milliseconds: 180,
                                                        ),
                                                  child: KeyedSubtree(
                                                    key: ValueKey(
                                                      'nav-$index-${index == safeIndex}',
                                                    ),
                                                    child: index == safeIndex
                                                        ? destinations[index]
                                                                  .selectedIcon ??
                                                              destinations[index]
                                                                  .icon
                                                        : destinations[index]
                                                              .icon,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
          for (final action in trailingActions) ...[
            const SizedBox(width: 10),
            action,
          ],
        ],
      ),
    );
  }
}
