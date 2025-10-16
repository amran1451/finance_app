# Структура базы данных приложения

Ниже приведено описание основных таблиц SQLite, создаваемых приложением через `lib/data/db/migrations.dart`.

## Основные таблицы

### `accounts`
- `id INTEGER PRIMARY KEY`
- `name TEXT`
- `currency TEXT`
- `start_balance_minor INTEGER NOT NULL DEFAULT 0`
- `is_archived INTEGER NOT NULL DEFAULT 0`

Хранит список счетов пользователя с указанием валюты, стартового баланса и статуса архивации.

### `categories`
- `id INTEGER PRIMARY KEY`
- `type TEXT` с ограничением значений `income`, `expense`, `saving`
- `name TEXT`
- `is_group INTEGER NOT NULL DEFAULT 0`
- `parent_id INTEGER NULL`
- `archived INTEGER NOT NULL DEFAULT 0`

Описывает категории операций. Поддерживает иерархию через `parent_id` и группировку.

### `transactions`
Основная таблица движения средств. Содержит множество индексов, упрощающих выборки по дате, счёту, категории и другим атрибутам.

Ключевые столбцы:
- `id INTEGER PRIMARY KEY`
- `account_id INTEGER NOT NULL`
- `category_id INTEGER NOT NULL`
- `type TEXT` (`income`/`expense`/`saving`)
- `amount_minor INTEGER NOT NULL`
- `date TEXT NOT NULL`
- `time TEXT NULL`
- `note TEXT NULL`
- `tags TEXT NULL`
- `is_planned INTEGER NOT NULL DEFAULT 0`
- `included_in_period INTEGER NOT NULL DEFAULT 1`
- `period_id TEXT NULL`
- `payout_id INTEGER NULL`
- `planned_id INTEGER NULL`
- `plan_instance_id INTEGER NULL`
- `source TEXT NULL`
- `necessity_id INTEGER NULL`
- `necessity_label TEXT NULL`
- `reason_id INTEGER NULL`
- `reason_label TEXT NULL`
- `payout_period_id TEXT NULL`
- `criticality INTEGER NOT NULL DEFAULT 0`
- `updated_at TEXT NOT NULL DEFAULT (datetime('now'))`
- `deleted INTEGER NOT NULL DEFAULT 0`

### `payouts`
- `id INTEGER PRIMARY KEY`
- `type TEXT` (`advance`/`salary`)
- `date TEXT NOT NULL`
- `amount_minor INTEGER NOT NULL`
- `account_id INTEGER NOT NULL`
- `daily_limit_minor INTEGER NOT NULL DEFAULT 0`
- `daily_limit_from_today INTEGER NOT NULL DEFAULT 0`
- `assigned_period_id TEXT NULL`

### `settings`
Хранит настройки в формате ключ/значение.
- `key TEXT PRIMARY KEY`
- `value TEXT NOT NULL`

## Справочники и планирование

### `necessity_labels`
- `id INTEGER PRIMARY KEY AUTOINCREMENT`
- `name TEXT NOT NULL`
- `color TEXT NULL`
- `sort_order INTEGER NOT NULL`
- `archived INTEGER NOT NULL DEFAULT 0`

### `reason_labels`
- `id INTEGER PRIMARY KEY AUTOINCREMENT`
- `name TEXT NOT NULL`
- `color TEXT NULL`
- `sort_order INTEGER NOT NULL`
- `archived INTEGER NOT NULL DEFAULT 0`

### `planned_master`
- `id INTEGER PRIMARY KEY AUTOINCREMENT`
- `type TEXT` (`expense`/`income`/`saving`)
- `title TEXT NOT NULL`
- `default_amount_minor INTEGER NULL`
- `category_id INTEGER NULL`
- `note TEXT NULL`
- `archived INTEGER NOT NULL DEFAULT 0`
- `necessity_id INTEGER NULL`
- `created_at TEXT NOT NULL DEFAULT (datetime('now'))`
- `updated_at TEXT NOT NULL DEFAULT (datetime('now'))`

Используется для хранения шаблонов планируемых операций.

### `periods`
- `id INTEGER PRIMARY KEY`
- `year INTEGER NOT NULL`
- `month INTEGER NOT NULL`
- `half TEXT` (`H1`/`H2`)
- `start TEXT NOT NULL`
- `end_exclusive TEXT NOT NULL`
- `payout_id INTEGER NULL`
- `daily_limit_minor INTEGER NULL`
- `spent_minor INTEGER NULL`
- `planned_included_minor INTEGER NULL`
- `carryover_minor INTEGER NOT NULL DEFAULT 0`
- `closed INTEGER NOT NULL DEFAULT 0`
- `closed_at TEXT NULL`
- `start_anchor_payout_id INTEGER NULL`
- `assigned_period_id TEXT NULL`

Описывает расчётные периоды и их агрегированные показатели.

## Оценка и зоны роста

1. **Отсутствие внешних ключей.** Ссылочные поля (`account_id`, `category_id`, `payout_id` и т.д.) не защищены ограничениями `FOREIGN KEY`, из-за чего возможны «висячие» записи. Можно включить поддержку внешних ключей с `ON DELETE SET NULL/ CASCADE`.
2. **Типы дат как TEXT.** Даты и времена хранятся в текстовом формате. Для консистентности и упрощения сравнений можно конвертировать их в `INTEGER` (метки времени) или гарантировать ISO 8601.
3. **Дублирование текстовых меток.** Столбцы `necessity_label` и `reason_label` дублируют информацию из таблиц-справочников. Лучше использовать только идентификаторы, а отображение брать через JOIN.
4. **Теги в одном поле.** Поле `tags` в `transactions` хранит список тегов в виде строки. Рассмотреть создание отдельной таблицы `transaction_tags` для нормализации и ускорения поиска.
5. **Индексы и фильтры.** Многие индексы уже созданы, но можно добавить частичные индексы для часто используемых фильтров (например, по незакрытым периодам или активным категориям).
6. **Типы булевых колонок.** Поля признаков (`is_planned`, `archived`, `closed`) хранятся как `INTEGER`. Рассмотреть использование `CHECK (column IN (0,1))` для явной валидации.

Подробности можно найти в файле миграций: `lib/data/db/migrations.dart`.
