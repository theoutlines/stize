# Фикс: тап по донат-баннеру в футере меню (мобильный веб)

**Дата:** 2026-07-24
**Ветка:** `fix/donate-banner-tap`
**Файлы правки:** `app/lib/presentation/widgets/app_drawer.dart`, `.github/FUNDING.yml`
**Тип:** клиентский фикс (бэкенд не затронут) + продуктовое решение (донат → Buy Me a Coffee)
**Статус:** правка сделана, тесты зелёные; merge/прод-деплой/KV — см. раздел «Деплой».

## Симптом

Мобильный веб, `stize.app`. Тап по донат-баннеру («Support Stiže ♥») в футере
бокового меню:

- ink-анимация нажатия проигрывается (значит Flutter пойнтер-даун получил),
- но ссылка Sponsors **не открывается**,
- вместо этого клик **проваливается сквозь баннер/меню в карту** под ним и
  открывает остановку.

## Диагноз

Проверял обе выдвинутые гипотезы.

### Гипотеза (1) — отсутствие `PointerInterceptor`. ✅ Это корень.

Дровер — обычный Flutter `Drawer` в корневом `Scaffold`
(`root_screen.dart`), а тело этого же `Scaffold` — `IndexedStack` с картой
MapLibre. На вебе карта — это **platform-view** (реальная DOM-нода), а контент
дровера рисуется Flutter на канвасе и **своих DOM-нод под каждый виджет не
имеет**. Поэтому нативный DOM-клик по баннеру проходит «сквозь» нарисованный
дровер и достаётся DOM-ноде карты под ним → карта выбирает остановку.

Это ровно та гоча, что описана в `docs/ARCHITECTURE.md`:

> Sheets/overlays over the web map need a pointer barrier. … a draggable sheet or
> overlay placed over it must be wrapped in `PointerInterceptor`, or scroll/drag
> gestures leak through to the map underneath.

Все прочие оверлеи над картой в проекте уже обёрнуты в `PointerInterceptor`
(`nearby_sheet.dart`, `stop_sheet.dart`, `context_shell.dart`, search-card и
кнопки в `home_map_screen.dart`). **Контент дровера — единственный оверлей без
этой обёртки.** Отсюда и баг.

### Гипотеза (2) — потеря user-gesture у `url_launcher` из-за async-зазора. ⚠️ Как отдельная причина не подтвердилась.

В коде баннера вызов синхронный, async-зазора перед `launchUrl` нет:

```dart
onTap: () => launchUrl(Uri.parse(donateUrl), mode: LaunchMode.externalApplication),
```

(`drawer_footer.dart:38`). То есть `await`-разрыва, который «съедает»
user-activation, здесь нет. Но **симптом «ссылка молча не открывается» всё равно
объясняется тем же корнем (1):** без pointer-барьера нативное user-activation
достаётся platform-view карты, а не Flutter, поэтому `window.open` внутри
`launchUrl` браузер тихо блокирует как popup. Иными словами, один и тот же корень
даёт оба симптома, и обёртка в `PointerInterceptor` чинит оба сразу — она отдаёт
Flutter настоящий DOM-жест (реальную DOM-ноду `HtmlElementView`, которая ловит
клик), поэтому и остановка под баннером больше не выбирается, и `launchUrl`
срабатывает внутри валидного жеста.

Вывод по (2): менять код `launchUrl` не требуется. Механизм «async-зазор» —
реальный класс багов в Flutter web, но к этому баннеру он не относится (вызов уже
синхронный).

### «Share feedback» и остальные пункты футера

Страдают **тем же механизмом** (тот же незакрытый барьером дровер), просто менее
заметно: они открывают модальный sheet или полноэкранный роут, который сразу
прикрывает случайно выбранную под ними остановку. Т.е. у них тоже был скрытый
«проваливающийся» клик по карте — та же правка закрывает и их. Отдельно:

- **Share feedback** → `showFeedbackSheet` (модальный лист) — сам лист поверх
  карты уже не наш дровер; но тап по самому пункту в дровере теперь не течёт.
- **Licenses / Privacy** → пуш нового роута — аналогично.
- Ссылка **GitHub issues** внутри feedback-листа (`launchUrl`) — тот же класс,
  но лист открывается поверх карты и, будучи не-дровером, ведёт себя как
  отдельный оверлей; в рамках этого фикса трогать не потребовалось.

## Правка

Один барьер на весь контент дровера — минимально и единообразно с остальными
оверлеями:

```dart
return Drawer(
  child: PointerInterceptor(   // ← добавлено; no-op вне веба
    child: SafeArea(
      child: Column( ... ),
    ),
  ),
);
```

Плюс импорт `package:pointer_interceptor/pointer_interceptor.dart`.
`PointerInterceptor` на мобильных/десктоп-таргетах — no-op, так что нативные
сборки не затронуты. Жесты Flutter (тап по пунктам, drag-to-close дровера) внутри
барьера работают как прежде — так же, как во всех уже обёрнутых листах.

## Проверка

### Автотесты (прогнаны, зелёные)

```bash
cd app
flutter analyze lib/presentation/widgets/app_drawer.dart   # No issues found
flutter test test/app_drawer_test.dart test/drawer_footer_test.dart   # All tests passed (7)
```

Тест `support banner appears and opens the URL when donate_url is set` уже
покрывает вызов `launchUrl` через мок — остаётся зелёным.

### Живая проверка на мобильном вьюпорте (выполнена ✅)

`dart_defines.json` (с `MAPTILER_KEY`) скопирован из главного worktree
(`../stigla/app/`, gitignored). Собран web-бандл против прод-API (там
`config:donate_url` = `https://github.com/sponsors/theoutlines`), поднят локально
и прогнан на мобильном вьюпорте 375×812.

Изолированное превью также задеплоено:
**`https://preview-fix-donate-tap.stigla.pages.dev`** (Basic Auth, как все
`*.pages.dev`) — для ручной перепроверки владельцем реальным тачем.

```bash
cd app
cp ../../stigla/app/dart_defines.json ./dart_defines.json   # gitignored, ключ владельца
flutter build web --release --dart-define-from-file=dart_defines.json
npx wrangler pages deploy build/web --project-name=stigla --branch=preview-fix-donate-tap
```

**Результаты на мобильном вьюпорте (375×812):**

1. **Тап по донат-баннеру** «Support Stiže ♥» →
   - ✅ вызывается `window.open("https://github.com/sponsors/theoutlines")`
     (ссылка Sponsors открывается — `onTap → launchUrl` срабатывает);
   - ✅ дровер остаётся открыт, **никакая остановка под баннером не выделяется**.
2. **Тап по «Share feedback»** → ✅ открывается лист обратной связи («Write to
   me»), без утечки в карту.
3. **Структурное подтверждение барьера.** При открытом дровере в DOM появляется
   `flt-platform-view` `304×812` от левого края (`pv-9`) — это и есть
   добавленный `PointerInterceptor`, накрывающий весь дровер (баннер + все пункты
   футера) поверх canvas карты (`pv-0`, `375×812`). До фикса этого слоя не было —
   сырые клики уходили в карту (что и подтвердилось: синтетические клики по
   голой карте открывали лист остановки).

> Оговорка по методике: Flutter web (CanvasKit) не принимает синтетические
> mouse-события браузер-инструмента как жесты — драйв шёл через включённую
> семантику Flutter (реальные DOM-ноды кнопок). Симптом «клик уходит в
> остановку» на голой карте воспроизвёлся отдельно; после фикса перехватчик
> `pv-9` его поглощает. Владельцу достаточно реального тача на превью-URL.

> Если карта на `*.pages.dev` пустая — добавить origin превью в allowed origins
> ключа MapTiler (локально ключ отработал и на `127.0.0.1`).

## Смена донат-провайдера: GitHub Sponsors → Buy Me a Coffee

Продуктовое решение (2026-07-24): донат переезжает на Buy Me a Coffee.

1. **Строка баннера** — правки не потребовала: заголовок уже нейтральный
   («Support Stiže ♥» / RU «Поддержать Stiže ♥» / SR «Podrži Stiže ♥»),
   `donate_url` подставляется из KV, «GitHub Sponsors» в тексте не упоминался.
   Подстрока «Free and ad-free…» не тронута.
2. **`.github/FUNDING.yml`** — добавлена строка `buy_me_a_coffee: ivanpolushin`
   (`github: theoutlines` оставлен). Кнопка Sponsor в шапке репозитория покажет
   обе опции.
3. **KV `config:donate_url`** = `https://buymeacoffee.com/ivanpolushin` — прод и
   staging (см. «Деплой»).

## Деплой

Порядок исполнения (по команде владельца «go», 2026-07-24):

_(заполняется по ходу)_
