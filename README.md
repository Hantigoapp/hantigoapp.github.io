# HantiGo

App lagu maamulo lacagta qofka: dakhliga (soo gal), kharashka (ka bax), lacagta akoontiga (EVC Plus, Bangi, Kaash), buffer/kayd, kharashyada joogtada ah iyo kuwa maalinlaha.

## Sida loo daabaco (GitHub Pages, bilaash)

1. Repo-ga gal **Settings → Pages**.
2. "Source" ka dooro **Deploy from a branch**, branch-na dooro **main** iyo **/(root)**, kadibna **Save**.
3. 1–2 daqiiqo kadib app-ku wuxuu ka shaqaynayaa:
   `https://asadmoallim-hash.github.io/HantiGo/`

Fiiro gaar ah: GitHub Pages wuxuu u baahan yahay repo **public** ah haddii akoonkaagu bilaash yahay.

## Sida taleefanka loogu rakibo

- **Android (Chrome):** fur xiriirka → menu-ka ⋮ → "Add to Home screen / Install app".
- **iPhone (Safari):** fur xiriirka → badhanka Share → "Add to Home Screen".

## Faylasha

| Fayl | Shaqada |
|---|---|
| `index.html` | App-ka oo dhan |
| `manifest.json` | Magaca, midabka iyo astaanta marka taleefanka lagu rakibo |
| `sw.js` | Wuxuu app-ka ka dhigaa mid internet la'aan shaqeeya |
| `icon.svg`, `icon-192.png`, `icon-512.png` | Astaanta app-ka |

Xogta qofka waxay ku kaydsan tahay taleefankiisa (localStorage). Login iyo subscription toos ah waxay u baahan yihiin server, waana tallaabada xigta.
