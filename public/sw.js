/* Push notifications: keep this file dependency-free so the browser can install it directly. */
self.addEventListener('push', event => {
  let payload = {};
  try { payload = event.data ? event.data.json() : {}; }
  catch { payload = { body: event.data?.text() || '' }; }
  const target = new URL(payload.url || '/', self.location.origin).href;
  event.waitUntil(self.registration.showNotification(payload.title || '팀워크 로그', {
    body: payload.body || '새 출퇴근 기록이 등록됐어요.',
    icon: '/icon.svg',
    badge: '/icon.svg',
    tag: payload.tag || 'attendance',
    renotify: true,
    data: { url: target }
  }));
});

self.addEventListener('notificationclick', event => {
  event.notification.close();
  const target = new URL(event.notification.data?.url || '/', self.location.origin).href;
  event.waitUntil((async () => {
    const windows = await self.clients.matchAll({ type: 'window', includeUncontrolled: true });
    for (const client of windows) {
      if (new URL(client.url).origin === self.location.origin) {
        await client.focus();
        if ('navigate' in client && client.url !== target) await client.navigate(target);
        return;
      }
    }
    await self.clients.openWindow(target);
  })());
});
