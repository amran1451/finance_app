import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/account.dart';
import '../../state/app_providers.dart';
import '../../state/db_refresh.dart';
import 'account_form_result.dart';

class AccountCreateStub extends ConsumerStatefulWidget {
  const AccountCreateStub({super.key});

  @override
  ConsumerState<AccountCreateStub> createState() => _AccountCreateStubState();
}

class _AccountCreateStubState extends ConsumerState<AccountCreateStub> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _balanceController = TextEditingController(text: '0');
  static const List<String> _currencyOptions = ['RUB', 'USD', 'EUR'];

  String _currency = _currencyOptions.first;
  bool _isArchived = false;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _nameController.dispose();
    _balanceController.dispose();
    super.dispose();
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _submit() async {
    final form = _formKey.currentState;
    if (form == null || !form.validate()) {
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    final repository = ref.read(accountsRepoProvider);
    final startBalanceMinor = _parseBalanceMinor(_balanceController.text);

    try {
      await repository.create(
        Account(
          name: _nameController.text.trim(),
          currency: _currency,
          startBalanceMinor: startBalanceMinor,
          isArchived: _isArchived,
        ),
      );
      bumpDbTick(ref);
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(AccountFormResult.created);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isSubmitting = false;
      });
      _showErrorSnackBar('Не удалось сохранить счёт: $error');
    }
  }

  int _parseBalanceMinor(String value) {
    final normalized = value.replaceAll(',', '.').replaceAll(' ', '');
    final parsed = double.tryParse(normalized) ?? 0;
    return (parsed * 100).round();
  }

  String? _validateName(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Укажите название';
    }
    return null;
  }

  String? _validateBalance(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Введите сумму';
    }
    final normalized = value.replaceAll(',', '.').replaceAll(' ', '');
    final parsed = double.tryParse(normalized);
    if (parsed == null) {
      return 'Неверный формат числа';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Новый счёт')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Название',
                  hintText: 'Например, Основной',
                ),
                enabled: !_isSubmitting,
                validator: _validateName,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: _currency,
                items: _currencyOptions
                    .map(
                      (currency) => DropdownMenuItem(
                        value: currency,
                        child: Text(currency),
                      ),
                    )
                    .toList(),
                onChanged: _isSubmitting
                    ? null
                    : (value) {
                        if (value != null) {
                          setState(() {
                            _currency = value;
                          });
                        }
                      },
                decoration: const InputDecoration(
                  labelText: 'Валюта',
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _balanceController,
                keyboardType: const TextInputType.numberWithOptions(
                  signed: true,
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Начальный баланс',
                  hintText: '0.00',
                ),
                enabled: !_isSubmitting,
                validator: _validateBalance,
              ),
              const SizedBox(height: 16),
              CheckboxListTile(
                title: const Text('Архивировать'),
                value: _isArchived,
                onChanged: _isSubmitting
                    ? null
                    : (value) {
                        setState(() {
                          _isArchived = value ?? false;
                        });
                      },
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _isSubmitting
                          ? null
                          : () => Navigator.of(context).pop(),
                      child: const Text('Отмена'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _isSubmitting ? null : _submit,
                      child: _isSubmitting
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Сохранить'),
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
}
