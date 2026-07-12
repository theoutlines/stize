# Отчёт: staging-бэкенд без общего слота — Worker versions + preview URLs

Дата: 2026-07-12 · Ветка: `fix/staging-versions` · Промпт:
`docs/prompts/prompt_staging_worker_versions.md`

## Что сделано

Устранена коллизия общего staging-воркера: ветки больше не деплоят в общий
`stigla-api-staging.theoutlines.xyz` и не перетирают друг друга. Теперь каждая
ветка получает изолированную пару **«preview-версия воркера + Pages-превью»**.

### 1. Предпосылки проверены (был [STOP & ASK])

- `wrangler versions upload --env staging` работает; **секреты и биндинги
  наследуются от воркера** — в выводе видны `STIGLA_KV`, оба staging-D1
  (`stigla-ideas-staging`, `stigla-analytics-staging`), `ASSETS`,
  `ENVIRONMENT=staging`.
- Аккаунт имеет workers.dev-субдомен `theoutlines`.
- **Проблема:** у воркера `stigla-backend-staging` были выключены Preview URLs
  (`previews_enabled: false`) — поэтому `versions upload` не печатал preview-URL.
  Остановился, согласовал с владельцем.
- **Решение (по согласованию):** включил Preview URLs (`previews_enabled: true`),
  основной workers.dev-маршрут оставил выключенным (`enabled: false`), чтобы
  активный деплой на `stigla-api-staging.theoutlines.xyz` не изменился.
  После этого `versions upload` печатает
  `Version Preview URL: https://<prefix>-stigla-backend-staging.theoutlines.workers.dev`.

### 2. Команда для сессий — `npm run staging:version`

`backend/scripts/staging-version.mjs` (обёртка над `wrangler versions upload
--env staging`): выкатывает код текущей ветки как версию, парсит человекочитаемый
вывод wrangler и печатает отдельной строкой `PREVIEW_URL=https://...`, чтобы
следующий шаг (сборка фронта) мог его подхватить:

```sh
PREVIEW_URL=$(npm run --silent staging:version | sed -n 's/^PREVIEW_URL=//p')
```

Если Preview URLs выключат обратно — скрипт не найдёт URL и выйдет с ошибкой и
подсказкой, где включить.

### 3. Связка с Pages-превью

Порядок задокументирован в `docs/staging.md`: собрать web-бандл с
`--dart-define=API_BASE_URL=$PREVIEW_URL` (+`ENVIRONMENT=staging`) и выкатить
`wrangler pages deploy build/web --project-name=stigla --branch=preview-<имя>`.
**CORS править не пришлось** — на воркере уже `cors({ origin: "*" })`
(`backend/src/index.ts:45`), origin Pages-превью проходит.

### 4. Документация

- `docs/staging.md`: новый раздел «A branch = its own preview pair», что общее
  (D1, KV, SWR-кэш `caches.default`) и что изолировано (код версии); правило про
  общий стейт (ветка, меняющая схему D1 / семантику KV-флагов → [STOP & ASK] или
  своя копия базы; смена формата кэш-пейлоада = как смена схемы); публичность
  preview-URL (защиты нет, не выкатывать чувствительные эндпоинты); cron на
  preview-версиях не срабатывает.
- `docs/WORKFLOW.md`: добавлен раздел «Staging: ветка = своя пара превью» и пункт
  в «Правила гигиены» (запрет `wrangler deploy` со staging-конфигом из ветки) —
  по приложенному патчу.

### 5. Проверка вживую (по фактам, не по ощущениям)

- Выкачена версия этой ветки: `80b731a0-stigla-backend-staging.theoutlines.workers.dev`.
- Собран и выкачен Pages-превью:
  **https://preview-staging-versions.stigla.pages.dev**. В `build/web/main.dart.js`
  зашит именно preview-URL версии (проверено grep).
- **Активный staging-деплой не изменился:** до и после трёх моих `versions upload`
  живой трафик по-прежнему обслуживает версия `b9084bb7` от 12:32:06
  (это код ветки `feature/coverage-map` — не моей).
- **Объективный маркер, различающий две версии** — флаги в `/api/v1/config`:
  - активный деплой (`stigla-api-staging.theoutlines.xyz`):
    `analytics_collect, analytics_show, coverage_map_show`;
  - моя preview-версия (`80b731a0-…workers.dev`):
    `analytics_collect, analytics_show` (без `coverage_map_show`).
  Панель `preview-staging-versions.stigla.pages.dev` ходит именно во вторую.

### Тесты

`npx tsc --noEmit` — чисто; `npm test` — 44/44 зелёные.

## Ограничения (важно помнить)

- **D1, KV и SWR-кэш общие для всех версий воркера.** Ветка, меняющая схему D1
  или семантику KV-флагов, обязана остановиться и согласовать это отдельно.
- **Preview-URL публичны** (`*.workers.dev`, без пароля). Хэш-префикс — не
  секьюрити-граница. Не выкатывать на preview-версии эндпоинты с чувствительными
  данными «потому что это staging».
- **Cron на preview-версиях не выполняется** — только на активном деплое.

## Не трогалось

Прод-воркер, прод-релиз (WORKFLOW «Релиз»), схема D1/KV. Отдельные именованные
воркеры на ветку не заводились (осознанно отвергнуто в промпте).

## Осталось владельцу

- **Merge в main — по явной команде** (я не мерджил).
- После merge — обновить слепок `WORKFLOW.md` в знаниях Project (как отмечено в
  патче).

---

## Как проверить (без терминала)

Всё, что требовало команд (включение Preview URLs, выкатка версии, сборка и
деплой превью), уже сделано. Тебе — открыть пару ссылок и сверить.

1. **Панель ветки жива и ходит в свою версию воркера.**
   Открой **https://preview-staging-versions.stigla.pages.dev** (Basic Auth —
   логин/пароль превью из менеджера паролей). Должен быть виден янтарный бейдж
   **STAGING**, приложение работает.

2. **Убедиться, что она ходит именно в preview-версию, а не в общий слот.**
   Открой две ссылки в браузере и сравни поле `flags`:
   - общий слот →
     `https://stigla-api-staging.theoutlines.xyz/api/v1/config`
     — во `flags` есть `coverage_map_show`;
   - preview-версия этой ветки →
     `https://80b731a0-stigla-backend-staging.theoutlines.workers.dev/api/v1/config`
     — во `flags` `coverage_map_show` **нет**.
   Панель ветки собрана против второй ссылки — значит, во флагах панели
   `coverage_map_show` тоже быть не должно.

3. **Убедиться, что общий staging-слот не тронут.**
   `https://stigla-api-staging.theoutlines.xyz/api/v1/config` по-прежнему
   отвечает и содержит `coverage_map_show` — то есть на нём живёт чужая версия
   (`feature/coverage-map`), которую моя работа не перезаписала. Это и есть
   главный результат: моя ветка выкатила свою версию, а живой staging остался
   как был.

> Если на карте в панели пусто — это только про ключ MapTiler (origin
> `preview-staging-versions.stigla.pages.dev` надо добавить в разрешённые в
> дашборде MapTiler); к бэкенду и версиям отношения не имеет.
