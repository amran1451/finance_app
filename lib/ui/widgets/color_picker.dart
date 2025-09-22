import 'package:flutter/material.dart';

typedef OnColorPicked = void Function(Color? color);

Future<void> showColorPickerSheet(
  BuildContext context, {
  Color? initial,
  required OnColorPicked onPicked,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => _ColorPickerSheet(initial: initial, onPicked: onPicked),
  );
}

class _ColorPickerSheet extends StatefulWidget {
  final Color? initial;
  final OnColorPicked onPicked;
  const _ColorPickerSheet({required this.initial, required this.onPicked});

  @override
  State<_ColorPickerSheet> createState() => _ColorPickerSheetState();
}

class _ColorPickerSheetState extends State<_ColorPickerSheet> {
  late Color? _selected = widget.initial;

  static final List<Color> _palette = [
    ...Colors.primaries.map((c) => c.shade500),
    ...Colors.primaries.map((c) => c.shade700),
  ];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 12,
        bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36,
            height: 4,
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: cs.outlineVariant,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Row(
            children: [
              CircleAvatar(
                backgroundColor: _selected ?? cs.surfaceVariant,
                radius: 14,
                child: _selected == null
                    ? Icon(
                        Icons.block,
                        size: 16,
                        color: cs.onSurfaceVariant,
                      )
                    : null,
              ),
              const SizedBox(width: 8),
              Text(
                'Выберите цвет',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const Spacer(),
              TextButton(
                onPressed: () {
                  widget.onPicked(_selected);
                  Navigator.of(context).pop();
                },
                child: const Text('Готово'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Кнопка "Без цвета"
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.block),
              label: const Text('Без цвета'),
              onPressed: () => setState(() => _selected = null),
            ),
          ),
          const SizedBox(height: 8),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _palette.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 8,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
            ),
            itemBuilder: (_, i) {
              final c = _palette[i];
              final sel = _selected?.value == c.value;
              return InkWell(
                onTap: () => setState(() => _selected = c),
                borderRadius: BorderRadius.circular(18),
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: sel
                        ? [BoxShadow(color: c.withOpacity(0.5), blurRadius: 8)]
                        : null,
                  ),
                  child: CircleAvatar(
                    backgroundColor: c,
                    radius: 18,
                    child: sel
                        ? const Icon(Icons.check, color: Colors.white)
                        : null,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
