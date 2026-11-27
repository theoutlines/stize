// Builds the Stiže POI sprite: a white Maki glyph (CC0) on a category-coloured disc,
// light + dark themes, @1x + @2x. Output goes to app/web/map/ (served by Pages) and, given a
// second path, single badges for the app's search results.
import fs from 'node:fs';
import path from 'node:path';
import sharp from 'sharp';

const out = process.argv[2];
const maki = 'node_modules/@mapbox/maki/icons';

// Category colours: one hue per kind of place. Transit hues (tram red, bus blue,
// trolleybus orange) are reserved for lines, so no category uses red, blue or orange.
const GROUPS = {
  culture: { light: '#A24DB3', dark: '#8E45A0', classes: ['museum', 'theatre', 'art_gallery', 'cinema', 'library', 'attraction', 'monument', 'castle', 'music'] },
  worship: { light: '#7C6E61', dark: '#6C6055', classes: ['place_of_worship', 'religious_christian', 'religious_jewish', 'religious_muslim'] },
  health:  { light: '#D04670', dark: '#B53F63', classes: ['hospital', 'pharmacy', 'doctors', 'dentist'] },
  study:   { light: '#8C7A4E', dark: '#7A6A45', classes: ['college', 'school'] },
  civic:   { light: '#5E6B85', dark: '#55607A', classes: ['town_hall', 'embassy', 'police', 'post', 'information'] },
  shop:    { light: '#2D8B87', dark: '#287A77', classes: ['shop', 'grocery', 'clothing_store', 'commercial', 'bakery', 'florist', 'gift'] },
  food:    { light: '#B8901F', dark: '#A0801E', classes: ['restaurant', 'cafe', 'bar', 'fast_food', 'beer', 'ice_cream'] },
  lodging: { light: '#5A5FCF', dark: '#5054B5', classes: ['lodging'] },
  park:    { light: '#3F8F4E', dark: '#3A7D47', classes: ['park', 'garden', 'playground', 'zoo', 'stadium'] },
  rail:    { light: '#4C5568', dark: '#5A6479', classes: ['railway'] }
};
const MAKI = { doctors: 'doctor', railway: 'rail' };

function iconSvg(cls, fill, ring, px) {
  const file = path.join(maki, (MAKI[cls] || cls.replace(/_/g, '-')) + '.svg');
  const src = fs.readFileSync(file, 'utf8');
  const vb = (src.match(/viewBox="([^"]+)"/) || [, '0 0 15 15'])[1].split(/\s+/).map(Number);
  const inner = src.replace(/^[\s\S]*?<svg[^>]*>/, '').replace(/<\/svg>\s*$/, '')
    .replace(/fill="[^"]*"/g, '').replace(/<path/g, '<path fill="#FFFFFF"');
  const S = 20, G = 11; // 1x box and glyph size
  const k = G / vb[2];
  return `<svg xmlns="http://www.w3.org/2000/svg" width="${px}" height="${px}" viewBox="0 0 ${S} ${S}">
<circle cx="10" cy="10" r="9" fill="${fill}" stroke="${ring}" stroke-width="1"/>
<g transform="translate(${(S - G) / 2} ${(S - G) / 2}) scale(${k})">${inner}</g></svg>`;
}

for (const theme of ['light', 'dark']) {
  for (const ratio of [1, 2]) {
    const px = 20 * ratio;
    const items = Object.values(GROUPS).flatMap(g => g.classes.map(c => [c, g[theme]]));
    const cols = 8, rows = Math.ceil(items.length / cols);
    const index = {}, comps = [];
    for (let i = 0; i < items.length; i++) {
      const [cls, fill] = items[i];
      const ring = theme === 'dark' ? '#14171D' : '#FFFFFF';
      const buf = await sharp(Buffer.from(iconSvg(cls, fill, ring, px))).png().toBuffer();
      const x = (i % cols) * px, y = Math.floor(i / cols) * px;
      comps.push({ input: buf, left: x, top: y });
      index['poi-' + cls] = { x, y, width: px, height: px, pixelRatio: ratio };
    }
    const name = `poi-${theme}${ratio === 2 ? '@2x' : ''}`;
    await sharp({ create: { width: cols * px, height: rows * px, channels: 4, background: { r: 0, g: 0, b: 0, alpha: 0 } } })
      .composite(comps).png().toFile(path.join(out, name + '.png'));
    fs.writeFileSync(path.join(out, name + '.json'), JSON.stringify(index));
  }
}
// The same badges one by one for the app's search results (a street or a place
// found by search shows the badge it has on the map). 60 px, drawn at 20-28 dp.
// `address` is search-only: a street or house number has no map POI badge.
const appDir = process.argv[3];
if (appDir) {
  const ADDRESS = { light: '#6E7480', dark: '#5C626D' };
  for (const theme of ['light', 'dark']) {
    const dir = path.join(appDir, theme);
    fs.mkdirSync(dir, { recursive: true });
    const ring = theme === 'dark' ? '#14171D' : '#FFFFFF';
    const items = [
      ...Object.values(GROUPS).flatMap(g => g.classes.map(c => [c, g[theme], c])),
      ['address', ADDRESS[theme], 'marker'],
    ];
    for (const [cls, fill, glyph] of items) {
      MAKI[cls] = MAKI[cls] || (glyph !== cls ? glyph : undefined);
      await sharp(Buffer.from(iconSvg(cls, fill, ring, 60))).png().toFile(path.join(dir, cls + '.png'));
    }
  }
}
console.log('sprites written to', out, appDir ? `and ${appDir}` : '');
