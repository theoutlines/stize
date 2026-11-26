// Static, indexable pages for stops and lines (the Flutter app itself is a
// canvas and invisible to search engines). Run after `flutter build web`:
//
//   node app/tool/gen_seo_pages.mjs <gtfs-dir> <out-dir>
//
// Writes into <out-dir> (app/build/web):
//   /stanica/<slug>-<stop_id>/index.html   one per stop
//   /linija/<slug>/index.html              one per line
//   /stanice/index.html, /linije/index.html   hubs (internal links)
//   /sitemap.xml, /robots.txt
//
// Pages are plain HTML + inline CSS, no scripts and NO live requests: a crawler
// walking thousands of pages must never fan out to the live source. The
// "Dolasci uživo" button opens the app at /stop/<id>.
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";

const [gtfsDir, outDir] = process.argv.slice(2);
if (!gtfsDir || !outDir) {
  console.error("usage: gen_seo_pages.mjs <gtfs-dir> <out-dir>");
  process.exit(1);
}
const ORIGIN = "https://stize.app";
const read = (p) => JSON.parse(readFileSync(join(gtfsDir, p), "utf8"));

const stops = read("stops.json").stops;
const lineRows = read("lines.json").lines;
const feed = (() => {
  try {
    return read("feed_meta.json");
  } catch {
    return {};
  }
})();

const TYPE_SR = { bus: "autobus", tram: "tramvaj", trolleybus: "trolejbus" };
const TYPE_EN = { bus: "bus", tram: "tram", trolleybus: "trolleybus" };
const TYPE_COLOR = { bus: "#2278E6", tram: "#E4312F", trolleybus: "#EA7000" };

const esc = (s) =>
  String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
const slug = (s) =>
  String(s)
    .toLowerCase()
    .replace(/đ/g, "dj")
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "");
const hhmm = (m) => {
  const t = ((m % 1440) + 1440) % 1440;
  return `${String(Math.floor(t / 60)).padStart(2, "0")}:${String(t % 60).padStart(2, "0")}`;
};
const natural = (a, b) => {
  const na = parseInt(a, 10);
  const nb = parseInt(b, 10);
  if (!isNaN(na) && !isNaN(nb) && na !== nb) return na - nb;
  if (!isNaN(na) && isNaN(nb)) return -1;
  if (isNaN(na) && !isNaN(nb)) return 1;
  return a.localeCompare(b);
};

// ---- Indexes -----------------------------------------------------------------
const routeById = new Map(lineRows.map((r) => [r.route_id, r]));
const linesByName = new Map();
for (const r of lineRows) {
  if (!linesByName.has(r.line)) linesByName.set(r.line, []);
  linesByName.get(r.line).push(r);
}
const lineType = (line) => linesByName.get(line)?.[0]?.vehicle_type ?? "bus";
const stopUrl = (s) => `/stanica/${slug(s.name)}-${s.stop_id}/`;
const lineUrl = (line) => `/linija/${slug(line)}/`;

// Per stop: weekday first/last departure per route. Per route: stops in travel
// order (the first trip of the day reaches them in sequence).
const stopDeps = new Map();
const routeStops = new Map();
for (const s of stops) {
  let sched;
  try {
    sched = read(`schedule/${s.stop_id}.json`);
  } catch {
    continue;
  }
  const rows = [];
  for (const d of sched.deps ?? []) {
    const raw = d.svc?.RD?.length ? d.svc.RD : Object.values(d.svc ?? {}).find((v) => v.length) ?? [];
    if (!raw.length) continue;
    // The service day runs past midnight: a 00:30 trip belongs to the END of
    // the day, not its start (else "first" reads 00:30 and "last" 00:15).
    const times = raw.map((t) => (t < 180 ? t + 1440 : t));
    const first = Math.min(...times);
    const last = Math.max(...times);
    rows.push({ line: d.line, routeId: d.route_id, first, last, count: times.length });
    if (!routeStops.has(d.route_id)) routeStops.set(d.route_id, []);
    routeStops.get(d.route_id).push({ stop: s, first });
  }
  rows.sort((a, b) => natural(a.line, b.line));
  stopDeps.set(s.stop_id, rows);
}
for (const list of routeStops.values()) list.sort((a, b) => a.first - b.first);

// ---- Page shell --------------------------------------------------------------
const CSS = `:root{color-scheme:dark light;--bg:#151515;--card:#1F1F1F;--ink:#fff;--mute:rgba(255,255,255,.6);--fill:rgba(255,255,255,.08)}
@media (prefers-color-scheme:light){:root{--bg:#F4F4F2;--card:#fff;--ink:#151515;--mute:rgba(21,21,21,.66);--fill:rgba(21,21,21,.08)}}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--ink);font:16px/24px system-ui,-apple-system,"Segoe UI",Roboto,sans-serif}
main{max-width:720px;margin:0 auto;padding:20px 16px 48px}a{color:inherit}
.brand{display:inline-block;font-weight:600;text-decoration:none;margin-bottom:20px}
h1{font-size:28px;line-height:34px;letter-spacing:-.02em;margin:0 0 4px;font-weight:600}
h2{font-size:18px;line-height:24px;margin:28px 0 10px;font-weight:600}
p{margin:0 0 12px}.mute{color:var(--mute);font-size:14px;line-height:20px}
.cta{display:flex;align-items:center;justify-content:center;height:52px;border-radius:26px;background:var(--ink);color:var(--bg);text-decoration:none;font-weight:600;margin:16px 0 4px}
.chips{display:flex;flex-wrap:wrap;gap:6px;margin:0;padding:0;list-style:none}
.chip{display:inline-flex;align-items:center;justify-content:center;min-width:44px;height:36px;padding:0 12px;border-radius:18px;color:#fff;text-decoration:none;font-weight:600}
.rows{list-style:none;margin:0;padding:0;display:flex;flex-direction:column;gap:4px}
.row{display:flex;gap:12px;align-items:center;justify-content:space-between;padding:10px 14px;border-radius:14px;background:var(--card);text-decoration:none}
.row b{font-weight:600}.row .t{color:var(--mute);font-size:14px;white-space:nowrap}
.badge{display:inline-block;min-width:36px;text-align:center;padding:2px 8px;border-radius:8px;color:#fff;font-weight:600;margin-right:8px}
ol.rows{counter-reset:n}ol.rows .row::before{counter-increment:n;content:counter(n);color:var(--mute);font-size:13px;min-width:20px}
ol.rows .row{justify-content:flex-start}footer{margin-top:36px}`;

function page({ path, title, description, body, jsonLd }) {
  return `<!doctype html>
<html lang="sr-Latn">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<title>${esc(title)}</title>
<meta name="description" content="${esc(description)}">
<link rel="canonical" href="${ORIGIN}${path}">
<meta property="og:title" content="${esc(title)}">
<meta property="og:description" content="${esc(description)}">
<meta property="og:url" content="${ORIGIN}${path}">
<meta property="og:type" content="website">
<link rel="icon" type="image/svg+xml" href="/favicon.svg">
<link rel="icon" type="image/png" sizes="32x32" href="/favicon.png">
<style>${CSS}</style>
${jsonLd ? `<script type="application/ld+json">${JSON.stringify(jsonLd).replace(/</g, "\\u003c")}</script>` : ""}
</head>
<body>
<main>
<a class="brand" href="/">Stiže</a>
${body}
<footer class="mute">
<p><a href="/linije/">Sve linije</a> · <a href="/stanice/">Sve stanice</a> · <a href="/">Mapa uživo</a></p>
<p>Red vožnje: otvoreni podaci Grada Beograda (data.gov.rs)${feed.feed_start_date ? `, verzija od ${esc(feed.feed_start_date)}` : ""}. Nezvanična aplikacija. Timetable: City of Belgrade open data.</p>
</footer>
</main>
</body>
</html>
`;
}

const written = [];
function write(path, html) {
  const dir = join(outDir, path);
  mkdirSync(dir, { recursive: true });
  writeFileSync(join(dir, "index.html"), html);
  written.push(path);
}
const chip = (line) =>
  `<li><a class="chip" style="background:${TYPE_COLOR[lineType(line)]}" href="${lineUrl(line)}">${esc(line)}</a></li>`;

// ---- Stop pages --------------------------------------------------------------
for (const s of stops) {
  const lines = [...(s.lines ?? [])].sort(natural);
  const deps = stopDeps.get(s.stop_id) ?? [];
  const types = (s.types ?? []).map((t) => TYPE_SR[t]).filter(Boolean);
  const lineList = lines.slice(0, 12).join(", ") + (lines.length > 12 ? "…" : "");
  const title = `${s.name}: dolasci uživo i red vožnje${lines.length ? ` (${lines.slice(0, 6).join(", ")}${lines.length > 6 ? "…" : ""})` : ""} | Stiže`;
  const description = `Stanica ${s.name}, Beograd: dolasci uživo i red vožnje${lineList ? ` za linije ${lineList}` : ""}. Live arrivals and timetable for ${s.name} stop in Belgrade.`;
  const depRows = deps
    .map((d) => {
      const r = routeById.get(d.routeId);
      const dest = r?.destination && slug(r.destination) !== slug(s.name) ? `→ ${esc(r.destination)}` : "poslednja stanica";
      return `<li><a class="row" href="${lineUrl(d.line)}"><span><span class="badge" style="background:${TYPE_COLOR[lineType(d.line)]}">${esc(d.line)}</span>${dest}</span><span class="t">${hhmm(d.first)}–${hhmm(d.last)}</span></a></li>`;
    })
    .join("\n");
  const body = `<h1>${esc(s.name)}</h1>
<p class="mute">Stanica javnog prevoza u Beogradu${types.length ? ` (${types.join(", ")})` : ""} · Public transport stop in Belgrade</p>
<a class="cta" href="/stop/${encodeURIComponent(s.stop_id)}">Dolasci uživo · Live arrivals</a>
<p class="mute">Otvara mapu sa vozilima koja upravo dolaze na ovu stanicu.</p>
${lines.length ? `<h2>Linije na ovoj stanici</h2>\n<ul class="chips">${lines.map(chip).join("")}</ul>` : ""}
${depRows ? `<h2>Red vožnje radnim danom: prvi i poslednji polazak</h2>\n<ul class="rows">\n${depRows}\n</ul>` : ""}`;
  write(stopUrl(s), page({
    path: stopUrl(s),
    title,
    description,
    body,
    jsonLd: {
      "@context": "https://schema.org",
      "@type": s.types?.includes("tram") && s.types.length === 1 ? "TramStation" : "BusStop",
      name: s.name,
      url: ORIGIN + stopUrl(s),
      geo: { "@type": "GeoCoordinates", latitude: s.lat, longitude: s.lon },
      address: { "@type": "PostalAddress", addressLocality: "Beograd", addressCountry: "RS" },
    },
  }));
}

// ---- Line pages --------------------------------------------------------------
const lineNames = [...linesByName.keys()].sort(natural);
for (const line of lineNames) {
  const dirs = linesByName.get(line);
  const type = dirs[0].vehicle_type;
  const ends = `${dirs[0].origin} – ${dirs[0].destination}`;
  const title = `Linija ${line}: ${ends}, red vožnje i vozila uživo | Stiže`;
  const description = `${TYPE_SR[type] ?? "Linija"} ${line} u Beogradu (${ends}): stanice, red vožnje i vozila uživo na mapi. Belgrade ${TYPE_EN[type] ?? "line"} ${line}: stops, timetable and live vehicles.`;
  const sections = dirs
    .map((r) => {
      const list = routeStops.get(r.route_id) ?? [];
      if (!list.length) return "";
      const first = list[0].first;
      return `<h2>${esc(r.origin)} → ${esc(r.destination)}</h2>
<p class="mute">Prvi polazak radnim danom oko ${hhmm(first)} · ${list.length} stanica</p>
<ol class="rows">
${list.map(({ stop }) => `<li><a class="row" href="${stopUrl(stop)}"><b>${esc(stop.name)}</b></a></li>`).join("\n")}
</ol>`;
    })
    .join("\n");
  const body = `<h1><span class="badge" style="background:${TYPE_COLOR[type]}">${esc(line)}</span>${esc(ends)}</h1>
<p class="mute">${esc(TYPE_SR[type] ?? "linija")} · Beograd · Belgrade ${esc(TYPE_EN[type] ?? "line")} ${esc(line)}</p>
<a class="cta" href="/">Vozila uživo na mapi · Live map</a>
${sections}`;
  write(lineUrl(line), page({ path: lineUrl(line), title, description, body }));
}

// ---- Hubs --------------------------------------------------------------------
write("/linije/", page({
  path: "/linije/",
  title: "Sve linije javnog prevoza u Beogradu: autobus, tramvaj, trolejbus | Stiže",
  description: "Spisak svih linija gradskog prevoza u Beogradu sa stanicama i redom vožnje. All Belgrade public transport lines.",
  body: `<h1>Linije javnog prevoza u Beogradu</h1>
<p class="mute">${lineNames.length} linija · All Belgrade bus, tram and trolleybus lines</p>
${["tram", "trolleybus", "bus"].map((t) => {
    const ls = lineNames.filter((l) => lineType(l) === t);
    return ls.length ? `<h2>${TYPE_SR[t][0].toUpperCase() + TYPE_SR[t].slice(1)}</h2>\n<ul class="chips">${ls.map(chip).join("")}</ul>` : "";
  }).join("\n")}`,
}));

const byLetter = new Map();
for (const s of [...stops].sort((a, b) => a.name.localeCompare(b.name, "sr-Latn"))) {
  const k = (s.name.trim()[0] ?? "#").toUpperCase();
  if (!byLetter.has(k)) byLetter.set(k, []);
  byLetter.get(k).push(s);
}
write("/stanice/", page({
  path: "/stanice/",
  title: "Sve stanice javnog prevoza u Beogradu | Stiže",
  description: "Spisak svih stanica gradskog prevoza u Beogradu sa dolascima uživo i redom vožnje. All Belgrade public transport stops.",
  body: `<h1>Stanice javnog prevoza u Beogradu</h1>
<p class="mute">${stops.length} stanica · All Belgrade stops. Isto ime često nose dve stanice, po jedna za svaki smer.</p>
${[...byLetter].map(([k, list]) => `<h2>${esc(k)}</h2>\n<ul class="rows">${list.map((s) => `<li><a class="row" href="${stopUrl(s)}"><b>${esc(s.name)}</b><span class="t">${esc([...(s.lines ?? [])].sort(natural).slice(0, 5).join(", "))}</span></a></li>`).join("")}</ul>`).join("\n")}`,
}));

// ---- Sitemap + robots ----------------------------------------------------------
const lastmod = new Date().toISOString().slice(0, 10);
writeFileSync(
  join(outDir, "sitemap.xml"),
  `<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n` +
    ["/", ...written].map((p) => `<url><loc>${ORIGIN}${p}</loc><lastmod>${lastmod}</lastmod></url>`).join("\n") +
    `\n</urlset>\n`,
);
writeFileSync(join(outDir, "robots.txt"), `User-agent: *\nAllow: /\n\nSitemap: ${ORIGIN}/sitemap.xml\n`);
console.log(`seo pages: ${written.length} (stops ${stops.length}, lines ${lineNames.length})`);
