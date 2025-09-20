import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/planned_providers.dart';

Future<void> showPlannedAddForm(
  BuildContext context,
  WidgetRef ref, {
  required PlannedType type,
  String? initialTitle,
  double? initialAmount,
  String? editId,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    clipBehavior: Clip.antiAlias,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(40)),
    ),
    builder: (modalContext) {
      final bottomInset = MediaQuery.of(modalContext).viewInsets.bottom;
      return SafeArea(
        bottom: true,
        child: Padding(
          padding: EdgeInsets.only(bottom: 16 + bottomInset),
          child: _PlannedAddForm(
            type: type,
            ref: ref,
            rootContext: context,
            initialTitle: initialTitle,
            initialAmount: initialAmount,
            editId: editId,
          ),
        ),
      );
    },
  );
}

class _PlannedAddForm extends StatefulWidget {
  const _PlannedAddForm({
    required this.type,
    required this.ref,
    required this.rootContext,
    this.initialTitle,
    this.initialAmount,
    this.editId,
  });

  final PlannedType type;
  final WidgetRef ref;
  final BuildContext rootContext;
  final String? initialTitle;
  final double? initialAmount;
  final String? editId;

  @override
  State<_PlannedAddForm> createState() => _PlannedAddFormState();
}

class _PlannedAddFormState extends State<_PlannedAddForm> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _amountController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _nameController.text = widget.initialTitle ?? '';
    if (widget.initialAmount != null) {
      final amount = widget.initialAmount!;
      _amountController.text = amount == amount.roundToDouble()
          ? amount.toStringAsFixed(0)
          : amount.toString();
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
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
    );
  }

  void _submit() {
    if (_formKey.currentState?.validate() != true) {
      return;
    }

    final title = _nameController.text.trim();
    final amountText = _amountController.text.trim().replaceAll(',', '.');
    final amount = double.parse(amountText);

    final notifier = widget.ref.read(plannedProvider.notifier);
    if (widget.editId == null) {
      notifier.add(
        type: widget.type,
        title: title,
        amount: amount,
      );
    } else {
      notifier.update(
        widget.editId!,
        title: title,
        amount: amount,
      );
    }

    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(widget.rootContext);
    navigator.pop();
    messenger.showSnackBar(
      SnackBar(
        content: Text(widget.editId == null ? 'Добавлено' : 'Изменено'),
      ),
    );
  }

  String _titleForType(PlannedType type) {
    final base = switch (type) {
      PlannedType.income => 'доход',
      PlannedType.expense => 'расход',
      PlannedType.saving => 'сбережение',
    };
    return widget.editId == null
        ? 'Добавить $base'
        : 'Редактировать $base';
  }
}
