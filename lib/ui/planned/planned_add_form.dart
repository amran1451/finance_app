import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/planned_providers.dart';

Future<void> showPlannedAddForm(
  BuildContext context,
  WidgetRef ref, {
  required PlannedType type,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => _PlannedAddForm(
      type: type,
      ref: ref,
      rootContext: context,
    ),
  );
}

class _PlannedAddForm extends StatefulWidget {
  const _PlannedAddForm({
    required this.type,
    required this.ref,
    required this.rootContext,
  });

  final PlannedType type;
  final WidgetRef ref;
  final BuildContext rootContext;

  @override
  State<_PlannedAddForm> createState() => _PlannedAddFormState();
}

class _PlannedAddFormState extends State<_PlannedAddForm> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _amountController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                _titleForType(widget.type),
                style: Theme.of(context).textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Наименование',
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Введите наименование';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _amountController,
                decoration: const InputDecoration(
                  labelText: 'Сумма',
                ),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                validator: (value) {
                  final text = value?.trim();
                  if (text == null || text.isEmpty) {
                    return 'Введите сумму';
                  }
                  final normalized = text.replaceAll(',', '.');
                  final parsed = double.tryParse(normalized);
                  if (parsed == null || parsed <= 0) {
                    return 'Сумма должна быть больше 0';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Отмена'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: _submit,
                      child: const Text('Сохранить'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _submit() {
    if (_formKey.currentState?.validate() != true) {
      return;
    }

    final title = _nameController.text.trim();
    final amountText = _amountController.text.trim().replaceAll(',', '.');
    final amount = double.parse(amountText);

    widget.ref.read(plannedProvider.notifier).add(
          type: widget.type,
          title: title,
          amount: amount,
        );

    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(widget.rootContext);
    navigator.pop();
    messenger.showSnackBar(
      const SnackBar(content: Text('Добавлено')),
    );
  }

  String _titleForType(PlannedType type) {
    return switch (type) {
      PlannedType.income => 'Добавить доход',
      PlannedType.expense => 'Добавить расход',
      PlannedType.saving => 'Добавить сбережение',
    };
  }
}
