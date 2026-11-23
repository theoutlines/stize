"""WebKit (Safari's engine, GTK port) harness for the Stize web app."""
import os, sys, time, subprocess
os.environ['LANG']='en_US.UTF-8'; os.environ['LANGUAGE']='en_US'; os.environ['LC_ALL']='en_US.UTF-8'
from selenium import webdriver
from selenium.webdriver.webkitgtk.options import Options
from selenium.webdriver.webkitgtk.service import Service

IPHONE_UA = ('Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 '
             '(KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1')

def start(w=390, h=844, mobile=True):
    if not os.environ.get('DISPLAY'):
        subprocess.Popen(['Xvfb', ':99', '-screen', '0', '1600x1200x24'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        os.environ['DISPLAY'] = ':99'; time.sleep(1)
    o = Options()
    o.binary_location = '/usr/lib/x86_64-linux-gnu/webkitgtk-6.0/MiniBrowser' if os.path.exists('/usr/lib/x86_64-linux-gnu/webkitgtk-6.0/MiniBrowser') else None
    if o.binary_location is None:
        import glob
        c = glob.glob('/usr/lib/*/webkit*/MiniBrowser')
        o.binary_location = c[0] if c else None
    o.add_argument('--automation')
    if mobile:
        o.add_argument(f'--user-agent={IPHONE_UA}')
    d = webdriver.WebKitGTK(options=o, service=Service('/usr/bin/WebKitWebDriver'))
    d.set_window_rect(0, 0, w, h)
    return d


def fit(d, w, h):
    """Make the page viewport exactly w x h."""
    for _ in range(3):
        iw, ih = d.execute_script('return [innerWidth, innerHeight]')
        r = d.get_window_rect()
        d.set_window_rect(0, 0, r['width'] + (w - iw), r['height'] + (h - ih))
        time.sleep(0.5)
    return d.execute_script('return [innerWidth, innerHeight]')


JS_PTR = r"""
window.__stz = window.__stz || {id: 1};
window.__ptr = function(type, x, y, id) {
  const t = document.elementFromPoint(x, y) || document.querySelector('flt-glass-pane') || document.body;
  const o = {bubbles: true, cancelable: true, composed: true, clientX: x, clientY: y, screenX: x, screenY: y,
             pointerId: id, pointerType: 'touch', isPrimary: true, button: 0, buttons: type === 'pointerup' ? 0 : 1,
             width: 10, height: 10, pressure: type === 'pointerup' ? 0 : 0.5};
  t.dispatchEvent(new PointerEvent(type, o));
};
"""


def tap(d, x, y):
    d.execute_script(JS_PTR + "const i=++__stz.id;__ptr('pointerdown',arguments[0],arguments[1],i);__ptr('pointerup',arguments[0],arguments[1],i);", x, y)
    time.sleep(0.6)


def drag(d, x0, y0, x1, y1, steps=20, ms=16, hold=False):
    d.execute_script(JS_PTR + """
      const [x0,y0,x1,y1,n,ms,hold]=arguments; const i=++__stz.id; const done=arguments[arguments.length-1];
      __ptr('pointerdown',x0,y0,i); let k=0;
      const f=()=>{k++; const x=x0+(x1-x0)*k/n, y=y0+(y1-y0)*k/n; __ptr('pointermove',x,y,i);
        if(k<n) setTimeout(f,ms); else { if(!hold) __ptr('pointerup',x,y,i); done(); } };
      setTimeout(f,ms);""" .replace('const done', 'const done') , x0, y0, x1, y1, steps, ms, hold) if False else \
    d.execute_async_script(JS_PTR + """
      const [x0,y0,x1,y1,n,ms,hold,done]=arguments; const i=++__stz.id;
      __ptr('pointerdown',x0,y0,i); let k=0;
      const f=()=>{k++; const x=x0+(x1-x0)*k/n, y=y0+(y1-y0)*k/n; __ptr('pointermove',x,y,i);
        if(k<n) setTimeout(f,ms); else { if(!hold) __ptr('pointerup',x,y,i); done(1); } };
      setTimeout(f,ms);""", x0, y0, x1, y1, steps, ms, hold)
    time.sleep(0.8)


def semantics(d):
    """Turn on Flutter's accessibility tree and return [(label, x, y, w, h)]."""
    d.execute_script("const p=document.querySelector('flt-semantics-placeholder'); if(p) p.click();")
    time.sleep(1)
    return d.execute_script("""return [...document.querySelectorAll('flt-semantics')].map(e=>{const r=e.getBoundingClientRect();
      return [(e.getAttribute('aria-label')||e.textContent||'').trim().slice(0,60), Math.round(r.x+r.width/2), Math.round(r.y+r.height/2), Math.round(r.width), Math.round(r.height), e.getAttribute('role')||'']}).filter(a=>a[0])""")


def find(d, label, exact=False):
    for l, x, y, w, h, role in semantics(d):
        if (l == label) if exact else (label.lower() in l.lower()):
            # Big groups: aim near their top edge, not the middle.
            return (x, y - h // 2 + 22) if h > 80 else (x, y)
    return None


def sheet_top(d):
    from PIL import Image
    W, H = d.execute_script('return [innerWidth, innerHeight]')
    d.save_screenshot('/tmp/_cl.png'); im = Image.open('/tmp/_cl.png').convert('RGB')
    bg = im.getpixel((6, H - 6))
    near = lambda p: sum(abs(a - b) for a, b in zip(p, bg)) < 10
    for y in range(int(H * 0.1), H - 40):
        if all(near(im.getpixel((xx, y + k))) for k in range(0, 30, 3) for xx in (6, int(W * 0.72), W - 6)):
            return y
    return None


def close_level(d):
    """Tap the round X of the open level (54px under the sheet top, right edge)."""
    W, H = d.execute_script('return [innerWidth, innerHeight]')
    t = sheet_top(d)
    if t is None: return None
    tap(d, W - 34, t + 54); time.sleep(1.2); return (W - 34, t + 54)


def click(d, x, y):
    """A real (mouse) click through WebDriver."""
    from selenium.webdriver.common.action_chains import ActionChains
    from selenium.webdriver.common.by import By
    body = d.find_element(By.TAG_NAME, 'body')
    r = d.execute_script('const r=document.body.getBoundingClientRect();return [r.width,r.height]')
    ActionChains(d).move_to_element_with_offset(body, int(x - r[0] / 2), int(y - r[1] / 2)).click().perform()
    time.sleep(0.8)
