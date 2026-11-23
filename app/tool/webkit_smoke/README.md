# WebKit mobile smoke

Scripted checks of the web build in WebKit (Safari's engine, GTK port) with an
iPhone user agent and touch pointer events. It catches layout and gesture bugs
that `flutter test` cannot see (keyboard focus, sheets after closing a level,
theme switching, card swipe). It does not replace a look on a real iPhone.

Setup (Ubuntu): `apt-get install webkit2gtk-driver xvfb` and
`pip install selenium pillow`.

Run against a local build served on :8765 (or any URL):

    python3 tool/webkit_smoke/mobile.py http://localhost:8765/

Screenshots and `results.json` land in `$OUT` (default `/tmp/webkit_smoke`).
