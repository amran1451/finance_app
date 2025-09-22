import 'package:flutter/material.dart';

import '../../app.dart';

typedef AddAnotherTap = void Function(BuildContext context);

void showAddAnotherSnackGlobal({
  required int seconds,
  required AddAnotherTap onTap,
}) {
  final sm = scaffoldMessengerKey.currentState;
  if (sm == null) return;
  sm.clearSnackBars();
  sm.showSnackBar(
    SnackBar(
      behavior: SnackBarBehavior.floating,
      duration: Duration(seconds: seconds),
      margin: const EdgeInsets.all(16),
      content: _AddAnotherContent(seconds: seconds, onTap: onTap),
      backgroundColor: null,
    ),
  );
}

class _AddAnotherContent extends StatefulWidget {
  const _AddAnotherContent({
    required this.seconds,
    required this.onTap,
  });

  final int seconds;
  final AddAnotherTap onTap;

  @override
  State<_AddAnotherContent> createState() => _AddAnotherContentState();
}

class _AddAnotherContentState extends State<_AddAnotherContent>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: Duration(seconds: widget.seconds),
  )..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: () {
        ScaffoldMessenger.maybeOf(context)?.hideCurrentSnackBar();
        widget.onTap(context);
      },
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text('Добавить ещё'),
          SizedBox(
            width: 28,
            height: 28,
            child: AnimatedBuilder(
              animation: _c,
              builder: (_, __) {
                final left = (widget.seconds * (1 - _c.value)).ceil();
                return Stack(
                  alignment: Alignment.center,
                  children: [
                    CircularProgressIndicator(
                      value: 1 - _c.value,
                      strokeWidth: 3,
                    ),
                    Text(
                      '$left',
                      style: TextStyle(color: colorScheme.onSurface),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
