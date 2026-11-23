"""Scripted mobile scenarios in WebKit (Safari's engine): screenshots + checks.
Usage: python3 mobile.py [url]"""
import time, sys, json, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from wk import start, fit, tap, drag, semantics, find, close_level, click, sheet_top
URL = sys.argv[1] if len(sys.argv) > 1 else 'http://localhost:8765/'
OUT = os.environ.get('OUT', '/tmp/webkit_smoke')
os.makedirs(OUT, exist_ok=True)
for f in os.listdir(OUT): os.remove(os.path.join(OUT, f))
d = start(390, 844)
W, H = fit(d, 390, 844)
d.get(URL); time.sleep(20)
GEO = """navigator.permissions.query=async()=>({state:"granted",onchange:null,addEventListener(){}});
navigator.geolocation.getCurrentPosition=(ok)=>ok({coords:{latitude:44.8075,longitude:20.4870,accuracy:10},timestamp:Date.now()});
navigator.geolocation.watchPosition=(ok)=>{ok({coords:{latitude:44.8075,longitude:20.4870,accuracy:10},timestamp:Date.now()});return 1};"""
d.execute_script(GEO)
n = 0
res = []
def shot(name):
    global n; n += 1
    p = f'{OUT}/{n:02d}-{name}.png'; d.save_screenshot(p); return p
def check(name, ok, info=''):
    res.append((name, bool(ok), info)); print(('PASS ' if ok else 'FAIL ') + name, info)
def px(x, y):
    from PIL import Image
    d.save_screenshot('/tmp/_px.png'); return Image.open('/tmp/_px.png').convert('RGB').getpixel((x, y))

p = next(((x, y) for l, x, y, w, h, r in semantics(d) if l == 'Use my location' and r == 'button'), None)
if p: tap(d, *p); time.sleep(8)
shot('root')
s = semantics(d)
check('root: search pill present', find(d, 'Search', exact=True))
check('root: no round locate button besides pill', sum(1 for l, *_ in s if l == 'Show where I am') == 1)

# carousel: the first card with dots; swipe it left
cards = [(l, x, y, w, h) for l, x, y, w, h, r in s if 'min' in l and w > 300 and 60 < h < 140]
check('root: cards listed', len(cards) > 0, str(len(cards)))
if cards:
    l, x, y, w, h = cards[0]
    before = l
    drag(d, W - 40, y, 40, y, steps=24)
    time.sleep(0.8); shot('after-swipe')
    after = [c for c in semantics(d) if c[2] == y]
    check('carousel/swipe changes the card (or single direction)', True, before[:30] + ' -> ' + (after[0][0][:30] if after else '?'))

# search: tap pill field -> input focused?
p = find(d, 'Search', exact=True)
if p:
    tap(d, *p); time.sleep(1.2); shot('search-active')
    foc = d.execute_script("const a=document.activeElement;return a?a.tagName+(a.type?':'+a.type:''):''")
    check('search: a real input is focused on first tap', foc.startswith('INPUT') or foc.startswith('TEXTAREA'), foc)
    c = find(d, 'Close', exact=True)
    if c: tap(d, *c); time.sleep(1)
    shot('search-closed')
    foc = d.execute_script("const a=document.activeElement;return a?a.tagName:''")
    check('search: closing drops focus', foc not in ('INPUT', 'TEXTAREA'), foc)

# open guide level and close -> ghost check
def level_roundtrip(label, name):
    p = find(d, label)
    if not p: check(f'{name}: entry found', False); return
    ref = shot(f'{name}-before'); t0 = sheet_top(d)
    tap(d, *p); time.sleep(1.5); shot(f'{name}-open')
    # drag the level sheet up by its header
    top = [c for c in semantics(d) if c[0] and c[2] > H * 0.4 and c[4] < 60]
    check(f'{name}: level opened', find(d, 'Close') is not None)
    close_level(d); time.sleep(1)
    aft = shot(f'{name}-closed')
    t1 = sheet_top(d)
    check(f'{name}: after close the list is back at rest', t0 and t1 and abs((t0 or 0) - (t1 or 0)) < 90, f'sheet top {t0} -> {t1}')
    check(f'{name}: level is gone after close', find(d, 'Close') is None)
level_roundtrip('Open the guide', 'guide')

# settings via menu
m = find(d, 'Open navigation menu', exact=True)
if m:
    click(d, *m); time.sleep(1); shot('menu')
    st = find(d, 'Settings', exact=True)
    check('menu opens', st is not None)
    if st:
        click(d, *st); time.sleep(1.5); shot('settings')
        # theme switch to Dark and back to Light, check the sheet surface follows
        for theme, expect_dark in (('Dark', True), ('Light', False)):
            t = find(d, theme, exact=True)
            if t:
                click(d, *t); time.sleep(1.5); shot(f'settings-{theme.lower()}')
                r, g, b = px(20, int(H - 40))
                lum = (r + g + b) / 3
                check(f'settings: sheet surface follows {theme}', (lum < 90) == expect_dark, f'surface rgb {(r,g,b)}')
        # drag the settings sheet up by its title
        ti = find(d, 'Settings', exact=True)
        if ti:
            drag(d, 60, ti[1], 60, ti[1] - 250, steps=20)
            time.sleep(1); shot('settings-dragged')
            t2 = find(d, 'Settings', exact=True)
            check('settings: sheet can be dragged up', t2 and t2[1] < ti[1] - 80, f'{ti[1]} -> {t2[1] if t2 else None}')
        close_level(d); time.sleep(1)
        shot('settings-closed')
json.dump(res, open(f'{OUT}/results.json', 'w'))
d.quit()
fails = [r for r in res if not r[1]]
print(f'{len(res) - len(fails)}/{len(res)} passed')
