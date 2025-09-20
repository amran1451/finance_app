import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/app_providers.dart';

class NecessitySettingsStub extends ConsumerStatefulWidget {
  const NecessitySettingsStub({super.key});

  @override
  ConsumerState<NecessitySettingsStub> createState() => _NecessitySettingsStubState();
}

class _NecessitySettingsStubState extends ConsumerState<NecessitySettingsStub> {
  late final List<TextEditingController> _controllers;

  @override
  void initState() {
    super.initState();
    final labels = ref.read(necessityLabelsProvider);
    _controllers = [
      for (final label in labels) TextEditingController(text: label),
    ];
  }

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  void _updateLabel(int index, String value) {
    final current = [...ref.read(necessityLabelsProvider)];
    if (index >= current.length) {
      return;
    }
    current[index] = value;
    ref.read(necessityLabelsProvider.notifier).state = current;
  }

  @override
  Widget build(BuildContext context) {
    final labels = ref.watch(necessityLabelsProvider);
    for (var i = 0; i < labels.length && i < _controllers.length; i++) {
      final controller = _controllers[i];
      if (controller.text != labels[i]) {
        controller.value = controller.value.copyWith(
          text: labels[i],
          selection: TextSelection.collapsed(offset: labels[i].length),
        );
      }
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Критичность/Необходимость')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Text(
            'Переименуйте уровни критичности. Эти значения используются при добавлении операции.',
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  for (var i = 0; i < _controllers.length; i++) ...[
                    TextFormField(
                      controller: _controllers[i],
                      decoration: InputDecoration(
                        labelText: 'Уровень ${i + 1}',
                      ),
                      onChanged: (value) => _updateLabel(i, value),
                    ),
                    if (i != _controllers.length - 1) const SizedBox(height: 16),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
