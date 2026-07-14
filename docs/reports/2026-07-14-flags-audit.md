# Аудит фиче-флагов — инвентаризация и сверка прод/staging/код (2026-07-14)

Ветка: `fix/flags-audit` · Задача: `docs/prompts/prompt_flags_audit.md`.
**Состояние флагов не менялось** — только чтение и сводка. Предложения по правкам —
отдельной секцией, под команду владельца.

## Метод
- Список флагов — из `backend/src/lib/featureFlags.ts` (`FEATURE_FLAGS`).
- Дефолт — `defaultFor(env)`: **staging → ON, прод → OFF** для всех (env-aware).
  Явное значение в KV всегда перебивает дефолт.
- Фактические значения — прочитаны из **прод-KV** (`9908…288`) и **staging-KV**
  (`ea24…3e5`) через `wrangler kv key get --remote`; списки ключей — `kv key list`.
- Клиент читает флаги через геттеры `AppConfig` (`app/lib/domain/models/app_config.dart`)
  и провайдеры (`providers.dart`); backend — через `getFlag()`.

## Сводная таблица

| Флаг | Что гейтит | Код-дефолт (prod/stg) | Прод-KV | Staging-KV | Ожидаемо (прод) | Статус |
|---|---|---|---|---|---|---|
| `analytics_collect` | Фоновый сбор наблюдений (backend) | OFF / ON | **1** | — (→ON) | ON | ✅ |
| `analytics_show` | Черновые экраны аналитики (client) | OFF / ON | — (→OFF) | — (→ON) | OFF | ✅ |
| `nearby_list` | Панель «Рядом» (client) | OFF / ON | **1** | — (→ON) | ON | ✅ |
| `nearby_sort_board` | Сортировка «Рядом» по времени-до-посадки (backend) | OFF / ON | **1** | — (→ON) | ON | ✅ |
| `coverage_map_show` | Вкладка карты покрытия (client) | OFF / ON | — (→OFF) | — (→ON) | OFF | ✅ |
| `coverage_on_main_map` | Heatmap покрытия на осн. карте (client) | OFF / ON | — (→OFF) | — (→ON) | OFF | ✅ |
| `timed_trajectory` | План движения ТС по времени (backend+client) | OFF / ON | **1** | — (→ON) | ON | ✅ |
| `symbol_layer` | GPU-символьный слой ТС (client) | OFF / ON | **1** | — (→ON) | ON | ✅ |
| `live_position_only` | На карте только ТС с реальным GPS (client) | OFF / ON | **1** | — (→ON) | ON | ✅ |
| `vehicle_direction_shape` | Сшивка ТС по фактическому направлению (client) | OFF / ON | **1** | — (→ON) | ON | ✅ |
| `schedule_fallback` | Расписание в списке прибытий (backend+client) | OFF / ON | **1** | — (→ON) | ON | ✅ |
| `schedule_map` | Scheduled-объекты на карте (backend) | OFF / ON | **1** | — (→ON) | ON | ✅ |

Конфиг-параметр:

| Ключ | Что | Код-дефолт | Прод-KV | Staging-KV | Статус |
|---|---|---|---|---|---|
| `config:nearby_schedule_stops` | Сколько ближайших остановок «Рядом» несут расписание | 5 (clamp 0..8) | **5** | — (→5) | ✅ совпадает |

«—» = ключа в KV нет, действует код-дефолт (в скобках — эффективное значение).

## Вывод: прод здоров, рассинхронов нет

- **Все готовые фичи ON в проде**, все сырые/эксперименты OFF — ровно как ожидается
  по продуктовой логике и по «известному контексту» задачи. Ни одного сырого флага,
  торчащего ON в проде; ни одной готовой фичи, скрытой в проде.
- **Staging: все 12 флагов ON** (KV пуст → `defaultFor(staging)=ON`), конфиг = дефолт 5.
  Расхождение staging(ON) vs прод(OFF) по `analytics_show` / `coverage_*` — **by
  design** (staging прогоняет все in-dev фичи), это не рассинхрон.
- **Осиротевших KV-ключей нет**: каждый `flag:*` в проде маппится на код-флаг.
  Killswitch не выставлен (сервис отвечает). Прочие прод-ключи (`geocode:*` — кэш
  поиска, `route_alerts_v1` — кэш алертов) не флаги, вне scope.

## Рассинхроны и подозрительные
**Критичных нет.** Мелкое:

1. **`scheduleFallbackEnabledProvider` — мёртвый клиентский провайдер (dead code, НЕ
   мёртвый флаг).** `providers.dart:90` определён, но нигде не `watch`-ается: клиент
   читает флаг напрямую геттером `.scheduleFallback` (`home_map_screen.dart:1305`),
   а эмиссию scheduled-объектов гейтит backend. Провайдер — рудимент. Флаг
   `schedule_fallback` полностью живой. → кандидат на удаление кода (не KV).
2. **Прод полагается на неявный дефолт для 3 OFF-флагов** (`analytics_show`,
   `coverage_map_show`, `coverage_on_main_map`): их нет в KV, работает `defaultFor`.
   Значение верное (OFF), но намерение не задокументировано в `kv key list`.

## Мёртвые флаги
**Нет.** Все 12 флагов что-то гейтят (backend `getFlag` и/или client-геттер/провайдер).

## Флаги, используемые в коде, но не объявленные
**Нет.** Все чтения (`getFlag(...)` и `flag('...')`) попадают в `FEATURE_FLAGS`.

## Недостающие в KV (действует дефолт — дефолт верный?)
- **Прод:** `analytics_show`, `coverage_map_show`, `coverage_on_main_map` → дефолт
  **OFF** ✅ (так и надо — сырое/дремлющее).
- **Staging:** все 12 флагов + `config:nearby_schedule_stops` отсутствуют → дефолты
  (все ON, cap 5) ✅ (так и надо — staging прогоняет всё).

## Предлагаю изменить (НЕ выполнено — под команду владельца)
Приоритет: сначала «сырое в проде» — таких **нет**. Остальное — гигиена, не срочно:

1. **[код, low] Удалить мёртвый провайдер `scheduleFallbackEnabledProvider`**
   (`providers.dart:90`). Отдельной уборочной задачей; на состояние флагов не влияет.
2. **[KV, опц.] Явно проставить в прод `flag:analytics_show=0`,
   `flag:coverage_map_show=0`, `flag:coverage_on_main_map=0`.** Плюс: `kv key list`
   документирует намерение (OFF), а не «нет ключа = дефолт». Минус: +3 ключа, эффект
   не меняется. На усмотрение — можно и оставить как есть.
3. **[KV, trivial] Прибрать мусорные `geocode:*` записи** (`geocode:фффффффф`,
   `geocode:шл`, `geocode:ффффффффbatutova` и пустые запросы) — это кэш поиска, не
   флаги; чисто гигиена namespace.

Ничего срочного: состояние флагов корректно.

## Как проверить (владельцу, без терминала)
Смотреть нечего «в приложении» — это инвентаризация. Чтобы убедиться:

1. Открой прод-конфиг: **https://stigla-api.theoutlines.xyz/api/v1/config** — сверь
   с колонкой «Прод-KV» в таблице выше: ON у 9 (`analytics_collect`, `symbol_layer`,
   `timed_trajectory`, `live_position_only`, `vehicle_direction_shape`,
   `schedule_fallback`, `schedule_map`, `nearby_list`, `nearby_sort_board`), OFF у 3
   (`analytics_show`, `coverage_map_show`, `coverage_on_main_map`).
2. Staging-конфиг: **https://stigla-api-staging.theoutlines.xyz/api/v1/config** —
   там все 12 ON (staging прогоняет всё). Это норма.
3. **Что решить:** нужны ли три гигиенических правки из «Предлагаю изменить» (мёртвый
   провайдер / явные OFF-ключи в проде / чистка geocode-кэша). Все три
   необязательны — прод-состояние флагов уже корректно. Скажи, какие делать —
   выполню отдельно (правки KV/кода — по твоей команде).
