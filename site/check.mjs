// Checks the site in public/ without a network or a dependency (Node 20+):
//
//   node site/check.mjs
//
// - every internal link, image, stylesheet, icon and srcset resolves to a file in
//   public/, and every #fragment to an id on the target page;
// - every page has a lang, a title, one h1, unique ids, and alt, width and height
//   on each image; every page but 404.html has a description and a canonical URL
//   that is listed in sitemap.xml;
// - every JSON-LD block parses, and the home page has the SoftwareApplication and
//   the comparison page the FAQPage whose questions match the visible ones;
// - _redirects lines are well formed, and the design tokens are an exact copy of
//   docs/design/system/project/assets/Handoff/xp-tokens.css.
import { readFileSync, readdirSync, statSync, existsSync } from 'node:fs';
import { join, relative, dirname, resolve, posix } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const pub = join(here, 'public');
const origin = 'https://xpath.abdurahman.ly';
const problems = [];
const fail = (file, message) => problems.push(`${file}: ${message}`);

const walk = (dir) => readdirSync(dir).flatMap((name) => {
  const path = join(dir, name);
  return statSync(path).isDirectory() ? walk(path) : [path];
});
const files = walk(pub);
const pages = files.filter((f) => f.endsWith('.html'));
const html = new Map(pages.map((f) => [f, readFileSync(f, 'utf8')]));

const attrs = (tag) => {
  const out = {};
  for (const m of tag.matchAll(/([a-zA-Z:-]+)(?:="([^"]*)")?/g)) out[m[1].toLowerCase()] = m[2] ?? '';
  return out;
};
const tags = (text, name) => [...text.matchAll(new RegExp(`<${name}\\b[^>]*>`, 'gi'))].map((m) => attrs(m[0]));
const ids = (text) => [...text.matchAll(/\sid="([^"]+)"/g)].map((m) => m[1]);
const strip = (s) => s.replace(/<[^>]+>/g, '').replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&amp;/g, '&').replace(/\s+/g, ' ').trim();

// The file a site path serves, as Workers static assets would (auto-trailing-slash).
const target = (path) => {
  const clean = decodeURIComponent(path.split(/[?#]/)[0]);
  const candidates = clean.endsWith('/')
    ? [join(pub, clean, 'index.html')]
    : [join(pub, clean), join(pub, `${clean}.html`), join(pub, clean, 'index.html')];
  return candidates.find((c) => existsSync(c) && statSync(c).isFile());
};

const redirects = new Set();
for (const [n, line] of readFileSync(join(pub, '_redirects'), 'utf8').split('\n').entries()) {
  if (!line.trim() || line.startsWith('#')) continue;
  const [from, to, code, extra] = line.trim().split(/\s+/);
  if (!from?.startsWith('/') || !to || extra || (code && !['301', '302', '303', '307', '308', '200'].includes(code))) {
    fail('_redirects', `line ${n + 1} is not "/from destination [code]"`);
  }
  redirects.add(from);
}

const sitemap = readFileSync(join(pub, 'sitemap.xml'), 'utf8');
const listed = [...sitemap.matchAll(/<loc>([^<]+)<\/loc>/g)].map((m) => m[1]);

for (const [file, text] of html) {
  const name = relative(pub, file);
  const sitePath = `/${name.replace(/index\.html$/, '')}`;

  if (!/<html lang="en">/.test(text)) fail(name, 'no <html lang="en">');
  if (!/<title>[^<]{10,}<\/title>/.test(text)) fail(name, 'no title');
  if ((text.match(/<h1\b/g) ?? []).length !== 1) fail(name, 'needs exactly one h1');
  const seen = new Set();
  for (const id of ids(text)) {
    if (seen.has(id)) fail(name, `id "${id}" is used twice`);
    seen.add(id);
  }
  for (const img of tags(text, 'img')) {
    if (!('alt' in img) || !img.width || !img.height) fail(name, `<img src="${img.src}"> needs alt, width and height`);
  }
  if (name !== '404.html') {
    const canonical = tags(text, 'link').find((l) => l.rel === 'canonical')?.href;
    if (canonical !== `${origin}${sitePath}`) fail(name, `canonical should be ${origin}${sitePath}, is ${canonical}`);
    if (!listed.includes(canonical)) fail(name, `${canonical} is not in sitemap.xml`);
    if (!tags(text, 'meta').some((m) => m.name === 'description' && m.content.length > 50)) fail(name, 'no description');
    for (const prop of ['og:title', 'og:description', 'og:image', 'og:url']) {
      if (!tags(text, 'meta').some((m) => m.property === prop && m.content)) fail(name, `no ${prop}`);
    }
  }

  // Links and assets.
  const refs = [
    ...tags(text, 'a').map((a) => a.href),
    ...tags(text, 'link').map((l) => l.href),
    ...tags(text, 'img').map((i) => i.src),
    ...tags(text, 'source').flatMap((s) => (s.srcset ?? '').split(',').map((p) => p.trim().split(/\s+/)[0])),
  ].filter(Boolean);
  for (const ref of refs) {
    if (/^(https?:|mailto:)/.test(ref)) {
      if (ref.startsWith(origin)) refs.push(ref.slice(origin.length) || '/');
      continue;
    }
    const absolute = ref.startsWith('#') ? `${sitePath}${ref}` : posix.resolve(posix.dirname(`/${name}`), ref) + (ref.endsWith('/') ? '/' : '');
    const [path, fragment] = absolute.split('#');
    if (redirects.has(path)) continue;
    const served = target(path);
    if (!served) {
      fail(name, `${ref} does not resolve to a file`);
    } else if (fragment && served.endsWith('.html') && !ids(html.get(served) ?? '').includes(fragment)) {
      fail(name, `${ref}: no id "${fragment}" on ${relative(pub, served)}`);
    }
  }

  // JSON-LD.
  const blocks = [...text.matchAll(/<script type="application\/ld\+json">([\s\S]*?)<\/script>/g)].map((m) => m[1]);
  const graph = [];
  for (const block of blocks) {
    try {
      const data = JSON.parse(block);
      if (data['@context'] !== 'https://schema.org') fail(name, 'JSON-LD without @context https://schema.org');
      graph.push(...(data['@graph'] ?? [data]));
    } catch (error) {
      fail(name, `JSON-LD does not parse: ${error.message}`);
    }
  }
  if (name === 'index.html') {
    const app = graph.find((n) => n['@type'] === 'SoftwareApplication');
    if (!app) fail(name, 'no SoftwareApplication JSON-LD');
    else {
      for (const key of ['name', 'applicationCategory', 'operatingSystem', 'offers', 'license', 'softwareVersion', 'downloadUrl', 'sameAs']) {
        if (!app[key]) fail(name, `SoftwareApplication has no ${key}`);
      }
      if (app.offers?.price !== '0') fail(name, 'SoftwareApplication offers.price should be "0"');
    }
  }
  if (name === 'vs/codemagic/index.html') {
    const faq = graph.find((n) => n['@type'] === 'FAQPage');
    if (!faq) fail(name, 'no FAQPage JSON-LD');
    else {
      const visible = [...text.matchAll(/<div><h3>([\s\S]*?)<\/h3><p>([\s\S]*?)<\/p><\/div>/g)].map((m) => [strip(m[1]), strip(m[2])]);
      const marked = faq.mainEntity.map((q) => [q.name, q.acceptedAnswer.text]);
      if (JSON.stringify(visible) !== JSON.stringify(marked)) fail(name, 'FAQPage JSON-LD differs from the visible FAQ');
    }
  }
}

for (const loc of listed) {
  if (!loc.startsWith(origin) || !target(loc.slice(origin.length))) fail('sitemap.xml', `${loc} is not a page`);
}

const tokens = resolve(here, '..', 'docs/design/system/project/assets/Handoff/xp-tokens.css');
if (readFileSync(tokens, 'utf8') !== readFileSync(join(pub, 'assets/xp-tokens.css'), 'utf8')) {
  fail('assets/xp-tokens.css', 'differs from docs/design/system/project/assets/Handoff/xp-tokens.css; copy it again');
}

if (problems.length) {
  console.error(problems.join('\n'));
  console.error(`\n${problems.length} problem(s).`);
  process.exit(1);
}
console.log(`OK: ${pages.length} pages, ${files.length} files.`);
