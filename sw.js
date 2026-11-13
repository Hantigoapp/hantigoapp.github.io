const CACHE="hantigo-v114";
// Everything the app needs to open and work with no internet (sign-in, lists, reports, PDF/Excel).
const FILES=["./","index.html","admin.html","privacy.html","manifest.json","icon.svg","icon-192.png","icon-512.png",
  "vendor/supabase.js","vendor/591.supabase.js","vendor/jspdf.umd.min.js","vendor/exceljs.min.js","vendor/hg-arabic.ttf","vendor/hg-arabic-bold.ttf"];
self.addEventListener("install",e=>{e.waitUntil(caches.open(CACHE).then(c=>Promise.all(FILES.map(f=>c.add(new Request(f,{cache:"reload"})).catch(()=>{})))));self.skipWaiting()});
self.addEventListener("activate",e=>{e.waitUntil(caches.keys().then(ks=>Promise.all(ks.filter(k=>k!==CACHE).map(k=>caches.delete(k)))));self.clients.claim()});
// Network first for this site's own files (so updates arrive at once); with no or very slow internet the saved copy opens.
// Account data from the server is never cached here: the app keeps it on the phone itself and syncs it safely.
// Web Push arrives even when every HantiGo tab is closed. Never put account data in the payload.
self.addEventListener("push",e=>{
  let data={title:"HantiGo",body:"Waxaad haysaa xusuusin cusub."};
  try{if(e.data){const incoming=e.data.json();data={...data,...incoming}}}catch{}
  e.waitUntil(self.registration.showNotification(data.title||"HantiGo",{
    body:String(data.body||"Xusuusin cusub"),
    icon:"icon-192.png",badge:"icon-192.png",
    tag:String(data.tag||"hantigo-push"),
    data:{url:data.url||"./"}
  }));
});
self.addEventListener("notificationclick",e=>{
  e.notification.close();
  const requested=new URL(e.notification.data?.url||"./",self.location.origin);
  const target=requested.origin===self.location.origin?requested.href:self.registration.scope;
  e.waitUntil(self.clients.matchAll({type:"window",includeUncontrolled:true}).then(list=>{
    for(const client of list){if(new URL(client.url).origin===self.location.origin){client.navigate(target);return client.focus()}}
    return self.clients.openWindow(target);
  }));
});
self.addEventListener("fetch",e=>{
  const u=new URL(e.request.url);
  if(e.request.method!=="GET"||u.origin!==location.origin)return;
  const nav=e.request.mode==="navigate";
  e.respondWith((async()=>{
    const c=await caches.open(CACHE);
    const saved=await c.match(e.request,{ignoreSearch:nav})||(nav&&/\/(index\.html)?$/.test(u.pathname)?(await c.match("./")||await c.match("index.html")):null);
    const net=fetch(u.href,{cache:"no-cache"}).then(r=>{if(r.ok)c.put(e.request,r.clone());return r});
    if(!saved)return net;
    // slow connection: show the saved copy after 4 seconds; the newer one is saved for next time
    return Promise.race([net.catch(()=>saved),new Promise(r=>setTimeout(()=>r(saved),4000))]);
  })());
});
