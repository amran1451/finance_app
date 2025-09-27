import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/payout.dart';
import '../../state/app_providers.dart';
import '../../state/budget_providers.dart';
import '../../state/db_refresh.dart';
import 'backups_settings_screen.dart';
import 'categories_manage_screen.dart';
import 'necessity_settings_screen.dart';
import 'reasons_settings_screen.dart';
import '../home/daily_limit_sheet.dart';
import '../payouts/payout_edit_sheet.dart';
import '../../utils/formatting.dart';
import '../../utils/ref_postframe.dart';
import '../../routing/app_router.dart';

class SettingsPlaceholder extends ConsumerStatefulWidget {
  const SettingsPlaceholder({super.key});

  @override
  ConsumerState<SettingsPlaceholder> createState() => _SettingsPlaceholderState();
}

class _SettingsPlaceholderState extends ConsumerState<SettingsPlaceholder> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Настройки')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: const [
          ThemeCallout(),
          SizedBox(height: 12),
          PayoutsSettingsSection(),
          SizedBox(height: 12),
          _OtherSettingsCard(),
        ],
      ),
    );
  }

  Future<void> _restoreDefaultCategories(BuildContext context) async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) {
            return AlertDialog(
              title: const Text('Восстановить базовые категории?'),
              content: const Text(
                'Недостающие предустановленные категории будут добавлены. '
                'Ваши собственные категории останутся без изменений.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Отмена'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: const Text('Восстановить'),
                ),
              ],
            );
          },
        ) ??
        false;

    if (!confirmed || !mounted) {
      return;
    }

    final repository = ref.read(categoriesRepositoryProvider);

    try {
      await repository.restoreDefaults();
      bumpDbTick(ref);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Базовые категории восстановлены')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось восстановить: $error')),
      );
    }
  }
}

class _OtherSettingsCard extends ConsumerWidget {
  const _OtherSettingsCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            title: const Text('Резервные копии'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const BackupsSettingsScreen(),
                ),
              );
            },
          ),
          const Divider(height: 0),
          ListTile(
            title: const Text('Настройки категорий'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const CategoriesManageScreen(),
                ),
              );
            },
            onLongPress: () {
              final state =
                  context.findAncestorStateOfType<_SettingsPlaceholderState>();
              state?._restoreDefaultCategories(context);
            },
          ),
          const Divider(height: 0),
          ListTile(
            title: const Text('Критичность/Необходимость'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const NecessitySettingsScreen(),
                ),
              );
            },
          ),
          const Divider(height: 0),
          ListTile(
            title: const Text('Причины расходов'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const ReasonsSettingsScreen(),
                ),
              );
            },
          ),
          const Divider(height: 0),
          ListTile(
            title: const Text('Общий план'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.pushNamed(RouteNames.plannedLibrary),
          ),
        ],
      ),
    );
  }
}

class ThemeCallout extends ConsumerWidget {
  const ThemeCallout({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    void setMode(ThemeMode target) {
      if (target == mode) {
        return;
      }
      ref.read(themeModeProvider.notifier).state = target;
    }

    const items = <({ThemeMode mode, IconData icon, String label})>[
      (mode: ThemeMode.system, icon: Icons.settings_brightness, label: 'Системная'),
      (mode: ThemeMode.light, icon: Icons.light_mode, label: 'Светлая'),
      (mode: ThemeMode.dark, icon: Icons.dark_mode, label: 'Тёмная'),
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Тема', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                final showLabels = constraints.maxWidth >= 360;
                final minWidth = showLabels ? 96.0 : 48.0;
                final padding = showLabels
                    ? const EdgeInsets.symmetric(horizontal: 12, vertical: 6)
                    : const EdgeInsets.symmetric(horizontal: 8, vertical: 6);

                return ToggleButtons(
                  isSelected: [for (final item in items) item.mode == mode],
                  onPressed: (index) => setMode(items[index].mode),
                  constraints: BoxConstraints(minHeight: 36, minWidth: minWidth),
                  borderRadius: BorderRadius.circular(12),
                  children: [
                    for (final item in items)
                      Tooltip(
                        triggerMode: TooltipTriggerMode.longPress,
                        message: item.label,
                        child: Padding(
                          padding: padding,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(item.icon, size: 18),
                              if (showLabels) ...[
                                const SizedBox(width: 6),
                                ConstrainedBox(
                                  constraints: const BoxConstraints(maxWidth: 100),
                                  child: Text(
                                    item.label,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class PayoutsSettingsSection extends ConsumerWidget {
  const PayoutsSettingsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final payoutsAsync = ref.watch(payoutsHistoryProvider);
    final accountsAsync = ref.watch(accountsDbProvider);
    final accountNames = accountsAsync.maybeWhen(
      data: (accounts) => {
        for (final account in accounts)
          if (account.id != null) account.id!: account.name,
      },
      orElse: () => const <int, String>{},
    );

    Future<void> addPayout() async {
      final tickBefore = ref.read(dbTickProvider);
      await showPayoutForSelectedPeriod(context);
      if (!context.mounted) {
        return;
      }
      final tickAfter = ref.read(dbTickProvider);
      if (tickAfter == tickBefore) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Выплата добавлена')),
      );
      final dailyLimitValue = ref
          .read(dailyLimitProvider)
          .maybeWhen(data: (value) => value ?? 0, orElse: () => 0);
      if (dailyLimitValue == 0) {
        final localContext = context;
        ref.postFrame(() {
          if (!localContext.mounted) {
            return;
          }
          ScaffoldMessenger.of(localContext).showSnackBar(
            SnackBar(
              content: const Text('Назначьте дневной лимит'),
              action: SnackBarAction(
                label: 'Задать',
                onPressed: () {
                  showEditDailyLimitSheet(localContext, ref).then((saved) {
                    if (!localContext.mounted || !saved) {
                      return;
                    }
                    ScaffoldMessenger.of(localContext).showSnackBar(
                      const SnackBar(content: Text('Лимит сохранён')),
                    );
                  });
                },
              ),
            ),
          );
        });
      }
    }

    Future<void> onMenuAction(String action, Payout payout) async {
      switch (action) {
        case 'edit':
          {
            final tickBefore = ref.read(dbTickProvider);
            await showPayoutEditSheet(
              context,
              initial: payout,
            );
            if (!context.mounted) {
              return;
            }
            final tickAfter = ref.read(dbTickProvider);
            if (tickAfter == tickBefore) {
              return;
            }
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Изменения применены')),
            );
            break;
          }
        case 'delete':
          {
            final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (dialogContext) {
                    return AlertDialog(
                      title: const Text('Удалить выплату?'),
                      content: const Text('Это действие нельзя отменить.'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(dialogContext).pop(false),
                          child: const Text('Отмена'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.of(dialogContext).pop(true),
                          child: const Text('Удалить'),
                        ),
                      ],
                    );
                  },
                ) ??
                false;
            if (!confirmed) {
              return;
            }
            final id = payout.id;
            if (id == null) {
              return;
            }
            await ref.read(payoutsRepoProvider).delete(id);
            bumpDbTick(ref);
            if (!context.mounted) {
              return;
            }
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Выплата удалена')),
            );
            break;
          }
        default:
          break;
      }
    }

    Future<void> showTileMenu(BuildContext tileContext, Payout payout) async {
      final renderBox = tileContext.findRenderObject() as RenderBox?;
      final overlay = Overlay.of(tileContext).context.findRenderObject() as RenderBox;
      if (renderBox == null) {
        return;
      }
      final position = RelativeRect.fromRect(
        Rect.fromLTWH(
          renderBox.localToGlobal(Offset.zero, ancestor: overlay).dx,
          renderBox.localToGlobal(Offset.zero, ancestor: overlay).dy,
          renderBox.size.width,
          renderBox.size.height,
        ),
        Offset.zero & overlay.size,
      );
      final selection = await showMenu<String>(
        context: tileContext,
        position: position,
        items: const [
          PopupMenuItem(value: 'edit', child: Text('Редактировать')),
          PopupMenuItem(value: 'delete', child: Text('Удалить')),
        ],
      );
      if (selection != null) {
        await onMenuAction(selection, payout);
      }
    }

    Widget buildHistory(List<Payout> payouts) {
      if (payouts.isEmpty) {
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Text('Пока нет сохранённых выплат'),
        );
      }
      return ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemBuilder: (context, index) {
          final payout = payouts[index];
          final accountName = payout.accountId != null
              ? accountNames[payout.accountId!] ?? 'Без счёта'
              : 'Без счёта';
          final dateLabel = formatDayMonth(payout.date);
          return Builder(
            builder: (tileContext) {
              return ListTile(
                dense: true,
                visualDensity: VisualDensity.compact,
                leading: Icon(
                  payout.type == PayoutType.advance
                      ? Icons.payments_outlined
                      : Icons.attach_money_outlined,
                ),
                title: Text(formatCurrencyMinor(payout.amountMinor)),
                subtitle: Text(
                  '$dateLabel • $accountName • ${payoutTypeLabel(payout.type)}',
                ),
                trailing: PopupMenuButton<String>(
                  tooltip: 'Действия',
                  onSelected: (value) => onMenuAction(value, payout),
                  itemBuilder: (context) => const [
                    PopupMenuItem(value: 'edit', child: Text('Редактировать')),
                    PopupMenuItem(value: 'delete', child: Text('Удалить')),
                  ],
                ),
                onLongPress: () => showTileMenu(tileContext, payout),
              );
            },
          );
        },
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemCount: payouts.length,
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('Выплаты', style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                FilledButton.icon(
                  icon: const Icon(Icons.add),
                  label: const Text('Добавить выплату'),
                  onPressed: addPayout,
                ),
              ],
            ),
            const SizedBox(height: 12),
            payoutsAsync.when(
              data: buildHistory,
              loading: () => const LinearProgressIndicator(minHeight: 2),
              error: (error, _) => Text('Не удалось загрузить выплаты: $error'),
            ),
          ],
        ),
      ),
    );
  }
}
