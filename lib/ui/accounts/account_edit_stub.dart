import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/account.dart';
import '../../state/app_providers.dart';
import '../../state/db_refresh.dart';
import 'account_form_result.dart';

class AccountEditStub extends ConsumerStatefulWidget {
  const AccountEditStub({super.key, this.accountId});

  final int? accountId;

  @override
  ConsumerState<AccountEditStub> createState() => _AccountEditStubState();
}

class _AccountEditStubState extends ConsumerState<AccountEditStub> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _balanceController = TextEditingController();
  static const List<String> _currencyOptions = ['RUB', 'USD', 'EUR'];

  late Future<Account?> _accountFuture;
  bool _invalidAccountId = false;
  String? _currency;
  bool _isArchived = false;
  bool _initialized = false;
  bool _isSubmitting = false;
  bool _isDeleting = false;

  @override
  void initState() {
    super.initState();
    final accountId = widget.accountId;
    if (accountId == null) {
      _invalidAccountId = true;
      _accountFuture = Future.value(null);
      return;
    }
    _accountFuture = ref.read(accountsRepoProvider).getById(accountId);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _balanceController.dispose();
    super.dispose();
  }

  List<String> _availableCurrencies(String? current) {
    final options = List<String>.from(_currencyOptions);
    if (current != null && current.isNotEmpty && !options.contains(current)) {
      options.add(current);
    }
    return options;
  }

  void _applyAccount(Account account) {
    if (_initialized) {
      return;
    }
    _initialized = true;
    _nameController.text = account.name;
    _balanceController.text = (account.startBalanceMinor / 100).toStringAsFixed(2);
    _currency = account.currency.isEmpty ? _currencyOptions.first : account.currency;
    _isArchived = account.isArchived;
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

  int _parseBalanceMinor(String value) {
    final normalized = value.replaceAll(',', '.').replaceAll(' ', '');
    final parsed = double.tryParse(normalized) ?? 0;
    return (parsed * 100).round();
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _updateAccount(Account account) async {
    final form = _formKey.currentState;
    if (form == null || !form.validate()) {
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    final repository = ref.read(accountsRepoProvider);
    final updated = account.copyWith(
      name: _nameController.text.trim(),
      currency: _currency ?? _currencyOptions.first,
      startBalanceMinor: _parseBalanceMinor(_balanceController.text),
      isArchived: _isArchived,
    );

    try {
      await repository.update(updated);
      bumpDbTick(ref);
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(AccountFormResult.updated);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isSubmitting = false;
      });
      _showSnackBar('Не удалось сохранить изменения: $error');
    }
  }

  Future<void> _deleteAccount(Account account) async {
    final confirmation = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Удалить счёт?'),
          content: Text('Действительно удалить счёт "${account.name}"?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Отмена'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Удалить'),
            ),
          ],
        );
      },
    );

    if (confirmation != true) {
      return;
    }

    if (account.id == null) {
      _showSnackBar('Нельзя удалить счёт без идентификатора');
      return;
    }

    setState(() {
      _isDeleting = true;
    });

    final repository = ref.read(accountsRepoProvider);
    try {
      await repository.delete(account.id!);
      bumpDbTick(ref);
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(AccountFormResult.deleted);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isDeleting = false;
      });
      _showSnackBar('Не удалось удалить счёт: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Редактирование счёта'),
      ),
      body: SafeArea(
        child: FutureBuilder<Account?>(
          future: _accountFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text('Не удалось загрузить счёт: ${snapshot.error}'),
                ),
              );
            }
            final account = snapshot.data;
            if (account == null) {
              if (_invalidAccountId) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('Некорректный идентификатор счёта'),
                  ),
                );
              }
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('Счёт не найден'),
                ),
              );
            }
            _applyAccount(account);

            final currencies = _availableCurrencies(_currency);
            _currency ??= currencies.first;

            return Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  TextFormField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      labelText: 'Название',
                    ),
                    enabled: !_isSubmitting && !_isDeleting,
                    validator: _validateName,
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    value: _currency ?? currencies.first,
                    items: currencies
                        .map(
                          (currency) => DropdownMenuItem(
                            value: currency,
                            child: Text(currency),
                          ),
                        )
                        .toList(),
                    onChanged: (_isSubmitting || _isDeleting)
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
                    ),
                    enabled: !_isSubmitting && !_isDeleting,
                    validator: _validateBalance,
                  ),
                  const SizedBox(height: 16),
                  CheckboxListTile(
                    title: const Text('Архивировать'),
                    value: _isArchived,
                    onChanged: (_isSubmitting || _isDeleting)
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
                          onPressed: (_isSubmitting || _isDeleting)
                              ? null
                              : () => Navigator.of(context).pop(),
                          child: const Text('Отмена'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: (_isSubmitting || _isDeleting)
                              ? null
                              : () => _updateAccount(account),
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
                  const SizedBox(height: 16),
                  TextButton.icon(
                    onPressed: (_isSubmitting || _isDeleting)
                        ? null
                        : () => _deleteAccount(account),
                    icon: _isDeleting
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.delete_outline),
                    label: const Text('Удалить счёт'),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
