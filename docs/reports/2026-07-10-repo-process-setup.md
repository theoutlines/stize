# Отчёт: процесс в CLAUDE.md + приведение репозитория в порядок

Дата: 2026-07-10. Задача: `docs/prompts/` (prompt_repo_process_setup).

## 🔐 Секреты и чувствительное (вверху — как просили)

**Утечек секретов НЕТ. Ротировать нечего.** Полный скан истории git:
- Файлы секретов (`backend/.dev.vars`, `app/dart_defines.json`, `.env`) **никогда
  не коммитились** (0 коммитов, затрагивающих их).
- MapTiler-ключ, Cloudflare/Anthropic токены, `ADMIN_TOKEN`, URL/параметры
  источника — **в истории не найдены**. (`gitleaks` в системе нет; скан сделан
  адресным `git log -p -S` + грепами по паттернам токенов.)
- `.env.example` содержит только пустые плейсхолдеры. ✅

**Чувствительное (не секреты) — решение за владельцем:**
1. **Имя класса источника** `BgnaplataTransitProvider`
   (`backend/src/lib/transitProvider.ts`, `arrivals.ts`) выдаёт идентичность
   источника GPS-данных. URL/параметры при этом НЕ в коде (только в
   gitignored `.dev.vars`). Вынос слоя доступа к источнику в приватный
   модуль/подмодуль — **оценка: ~0.5–1 день** (интерфейс уже абстрактный;
   переехать реализация-провайдер + фикстуры тестов в приватный git-submodule
   или npm-пакет). Не реализовывал.
2. **Инфра-ID в `backend/wrangler.toml`** (KV id, 4× D1 `database_id`) —
   закоммичены. Это **идентификаторы ресурсов, не креды** (без Cloudflare-auth
   бесполезны), их коммит — стандартная практика wrangler. Риск низкий; при
   желании можно вынести в необязательный конфиг. Оставил как есть.

Чистку истории git (`filter-repo`) не делал — не требовалось и требует явной
команды.

## Что починено (по пунктам 2.1–2.5)

**2.1 Состояние git** — `git status` чист (незакоммиченного нет).
Все feature-ветки были **полностью влиты** в `main`. Смерженные удалены:
`feature/preview-auth`, `feature/staging-env`, `feature/analytics-audit`.
`main` собирается и релизопригоден (backend: 41 тест + `tsc` зелёные;
web-сборка проходит — проверено этой сессией). Работы «только в рабочей папке
без ветки» не было.

**2.2 Структура docs/** — созданы `docs/prompts/` и `docs/reports/` (`docs/` уже
был). Добавлены `docs/BACKLOG.md` (единый источник приоритетов) и
`docs/prompts/README.md`. Все существующие `.md` уже лежали правильно
(`feature-flags.md`, `staging.md` в `docs/`; README — по своим папкам). Битых
ссылок нет. `fleet_models.json` ещё не существует (задача Fleet-ID); каталог
`assets/data/` заведём при её старте. Промпты прошлых задач лежат вне репозитория
(на машине владельца) — **их перенос в публичный `docs/prompts/` — решение
владельца** (см. вопрос ниже).

**2.3 Worktrees** — настроены:
- `../stigla-transport-analytics` → ветка `feature/transport-analytics` (уже
  существовала, подключена, не пересоздавалась). Она **влита и отстаёт** от main
  на коммиты аудита — если продолжать работу, сперва `git merge main`.
- `../stigla-fleet-id` → новая ветка `feature/fleet-id` (пустая, под следующую
  задачу).
Артефакты сборки (`build/`, `.dart_tool/`, `node_modules/`) — **по папкам, не
пересекаются** (worktree'ы делят `.git`, но не рабочие каталоги). Gitignored
конфиги (`app/dart_defines.json`, `backend/.dev.vars`) скопированы в оба
worktree локально, чтобы сборка работала. Перед сборкой в worktree — свои
`flutter pub get` / `npm install`.

**2.4 Фиче-флаги** — механизм есть в `main` (`backend/src/lib/featureFlags.ts`).
Недоделанное реально выключено: на проде `analytics_show=false` (экраны
аналитики скрыты), `analytics_collect=true` (сбор идёт в фоне). Флаги
независимы, показ переключается без пересборки.

**2.5 Open-source гигиена** — см. блок «Секреты» выше. `.env.example` +
`.gitignore` корректны. **LICENSE добавлен — AGPL-3.0** (канонический текст, по
решению владельца: защищает от закрытых форков-сервисов). Прошлые промпты решено
**не** переносить в публичный `docs/prompts/` (могут содержать инфра-детали) —
каталог оставлен для будущих чистых постановок.

## Итоговая структура

```
Projects/
├── stigla/                        (main)
│   ├── CLAUDE.md                  ← + раздел «Процесс»
│   ├── CONTRIBUTING.md  README.md
│   ├── docs/
│   │   ├── BACKLOG.md             ← новый (единый источник приоритетов)
│   │   ├── feature-flags.md  staging.md
│   │   ├── prompts/README.md      ← новый
│   │   └── reports/2026-07-10-repo-process-setup.md  ← этот отчёт
│   ├── app/  backend/
├── stigla-transport-analytics/    (feature/transport-analytics)
└── stigla-fleet-id/               (feature/fleet-id, пустая)
```

## 🧾 Шпаргалка владельца (копипастой)

```sh
# Начать новую задачу (ветка + отдельная папка):
git worktree add ../stigla-<имя> -b feature/<имя>
cd ../stigla-<имя>   # работаешь здесь; deps: flutter pub get / npm install

# Посмотреть, что где:
git worktree list           # все папки-ветки
git status                  # изменения в текущей
git branch                  # список веток

# Влить готовое в main (из папки main):
cd ~/Projects/stigla && git checkout main && git pull
git merge feature/<имя> && git push

# Катнуть релиз из main:
cd backend && npm run deploy                                   # worker
cd ../app && flutter build web --release --dart-define-from-file=dart_defines.json
npx wrangler pages deploy build/web --project-name=stigla --branch=main

# Прибрать за смерженной веткой:
git worktree remove ../stigla-<имя>
git branch -d feature/<имя>
```
