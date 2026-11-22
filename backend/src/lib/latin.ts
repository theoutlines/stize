// Serbian Cyrillic -> Latin (gajica). The app UI is in Latin script; upstream
// texts (route-change announcements, OSM addresses) often come in Cyrillic.
const MAP: Record<string, string> = {
  А: "A", Б: "B", В: "V", Г: "G", Д: "D", Ђ: "Đ", Е: "E", Ж: "Ž", З: "Z", И: "I",
  Ј: "J", К: "K", Л: "L", Љ: "Lj", М: "M", Н: "N", Њ: "Nj", О: "O", П: "P", Р: "R",
  С: "S", Т: "T", Ћ: "Ć", У: "U", Ф: "F", Х: "H", Ц: "C", Ч: "Č", Џ: "Dž", Ш: "Š",
  а: "a", б: "b", в: "v", г: "g", д: "d", ђ: "đ", е: "e", ж: "ž", з: "z", и: "i",
  ј: "j", к: "k", л: "l", љ: "lj", м: "m", н: "n", њ: "nj", о: "o", п: "p", р: "r",
  с: "s", т: "t", ћ: "ć", у: "u", ф: "f", х: "h", ц: "c", ч: "č", џ: "dž", ш: "š",
};

export function toLatin(text: string): string {
  let out = "";
  for (let i = 0; i < text.length; i++) {
    const ch = text[i];
    const m = MAP[ch];
    if (m === undefined) {
      out += ch;
      continue;
    }
    // Digraph capitals: "LJUBLJANA" stays all caps, "Ljubljana" stays title case.
    if (m.length === 2 && ch === ch.toUpperCase()) {
      const next = text[i + 1];
      const nextUpper = next !== undefined && next !== next.toLowerCase();
      out += nextUpper ? m.toUpperCase() : m;
    } else {
      out += m;
    }
  }
  return out;
}
