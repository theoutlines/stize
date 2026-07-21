// Cloudflare Pages advanced-mode worker: password-gate every *preview* URL
// (all *.pages.dev deployments — staging and per-branch feature previews) with
// HTTP Basic Auth, while leaving PRODUCTION (the custom domain) fully public.
//
// The credential isn't stored here in the clear — only the SHA-256 of the
// password is embedded, so the repo/bundle never contains the actual password
// (it can't be reversed from the hash). The username and plaintext password are
// kept in the team's password manager. This self-contained check works
// identically on production and preview deployments (no env-var scoping to fuss
// with), and production is never gated because its hostname isn't a *.pages.dev.
const PREVIEW_USER = "stigla";
const PREVIEW_PASS_SHA256 =
  "47cd6e9cc7ccc0f6ec914cb8694518280cdb259787cba42b0069030361f01c10";

async function sha256Hex(input) {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(input));
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

// Redirect-only hosts: the app is served on the new canonical apex (stize.app),
// and any hit to these 301-redirects there with path + query preserved (so deep
// links like /stop/:id and ?params survive). They stay Pages custom domains but
// never serve the app:
//   - stigla.theoutlines.xyz — the legacy production host;
//   - www.stize.app          — the www subdomain (apex is canonical).
const REDIRECT_HOSTS = new Set(["stigla.theoutlines.xyz", "www.stize.app"]);

export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    if (REDIRECT_HOSTS.has(url.hostname)) {
      return Response.redirect("https://stize.app" + url.pathname + url.search, 301);
    }

    const isPreview = url.hostname.endsWith(".pages.dev");

    if (isPreview) {
      const header = request.headers.get("Authorization") || "";
      let ok = false;
      if (header.startsWith("Basic ")) {
        const decoded = atob(header.slice(6));
        const i = decoded.indexOf(":");
        const user = decoded.slice(0, i);
        const pass = decoded.slice(i + 1);
        ok = user === PREVIEW_USER && (await sha256Hex(pass)) === PREVIEW_PASS_SHA256;
      }
      if (!ok) {
        return new Response("Authentication required.", {
          status: 401,
          headers: {
            "WWW-Authenticate": 'Basic realm="Stiže preview", charset="UTF-8"',
          },
        });
      }
    }

    return env.ASSETS.fetch(request);
  },
};
