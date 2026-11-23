import 'package:flutter/material.dart';

import '../stize_tokens.dart';

/// Segmented control (design system: components/Segmented). A label above, a
/// `fill-06` track with 4px inset, the picked option on `ink` with `on-ink`
/// text, the rest `ink-60`. 40px options, `radius-button` track and
/// `radius-md` thumb. Label `label` style; option text 16/24 medium.
class StizeSegmented<T> extends StatelessWidget {
  const StizeSegmented({
    super.key,
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String label;
  final T value;
  final List<(T, String)> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = StizeColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: StizeType.label.copyWith(color: c.ink60)),
        const SizedBox(height: StizeSpace.space2),
        Container(
          padding: const EdgeInsets.all(StizeSpace.space1),
          decoration: BoxDecoration(
            color: c.fill06,
            borderRadius: BorderRadius.circular(StizeRadius.radiusButton),
          ),
          child: Row(
            children: [
              for (final (option, text) in options)
                Expanded(
                  child: Semantics(
                    button: true,
                    selected: option == value,
                    child: Material(
                      color: option == value ? c.ink : Colors.transparent,
                      borderRadius: BorderRadius.circular(StizeRadius.radiusMd),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () => onChanged(option),
                        child: SizedBox(
                          height: StizeSize.buttonSmallH,
                          child: Center(
                            child: Text(
                              text,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: StizeType.label.copyWith(
                                color: option == value ? c.onInk : c.ink60,
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
        ),
      ],
    );
  }
}
