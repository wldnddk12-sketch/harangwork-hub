/* 하랑 업무 허브 — 핸드폰 알림 받기 */
self.addEventListener("install",()=>self.skipWaiting());
self.addEventListener("activate",e=>e.waitUntil(self.clients.claim()));
self.addEventListener("push",e=>{let d={};try{d=e.data?e.data.json():{};}catch(_){d={body:e.data?e.data.text():""};}
  e.waitUntil(self.registration.showNotification(d.title||"하랑 업무 허브",{body:d.body||"",icon:"icon-192.png",badge:"icon-192.png",tag:d.tag||undefined,renotify:!!d.tag,data:{tab:d.tab||""}}));});
self.addEventListener("notificationclick",e=>{e.notification.close();const tab=(e.notification.data&&e.notification.data.tab)||"";const url=self.registration.scope+(tab?"?tab="+encodeURIComponent(tab):"");
  e.waitUntil(self.clients.matchAll({type:"window",includeUncontrolled:true}).then(cs=>{for(const c of cs){if("focus" in c){c.postMessage({tab});return c.focus();}}return self.clients.openWindow(url);}));});
