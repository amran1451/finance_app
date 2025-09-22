import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

extension RefPostFrame on WidgetRef {
  void postFrame(void Function() fn) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (context.mounted) fn();
    });
  }
}
