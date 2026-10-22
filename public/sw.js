// AACT HRMS service worker — makes the web app installable on Android and iPhone and opens it fast.
// It caches ONLY the app itself (index.html, /assets, /icons). It never caches API calls, so no
// employee data is ever stored on the phone by the service worker.
const CACHE = 'aact-hrms-shell-v1';
const API = /^\/(rest|auth|storage|functions|realtime)\/v1\//;

self.addEventListener('install', () => { self.skipWaiting(); });

self.addEventListener('activate', (event) => {
  event.waitUntil((async () => {
    for (const key of await caches.keys()) if (key !== CACHE) await caches.delete(key);
    await self.clients.claim();
  })());
});

self.addEventListener('fetch', (event) => {
  const req = event.request;
  if (req.method !== 'GET') return;
  const url = new URL(req.url);
  if (url.origin !== self.location.origin || API.test(url.pathname)) return;

  if (req.mode === 'navigate') {
    // network first: always the newest version when online; the cached page only when offline
    event.respondWith(fetch(req).then((res) => {
      if (res.ok) { const copy = res.clone(); caches.open(CACHE).then((c) => c.put('/index.html', copy)); }
      return res;
    }).catch(() => caches.match('/index.html').then((hit) => hit || Response.error())));
    return;
  }
  if (url.pathname.startsWith('/assets/') || url.pathname.startsWith('/icons/')) {
    // file names in /assets change with every release, so a cached copy is always correct
    event.respondWith(caches.match(req).then((hit) => hit || fetch(req).then((res) => {
      if (res.ok) { const copy = res.clone(); caches.open(CACHE).then((c) => c.put(req, copy)); }
      return res;
    })));
  }
});
