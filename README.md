# HantiGo

Waxaa sameeyay **Asad Moallim**.

App lagu maamulo lacagta qofka: dakhliga (soo gal), kharashka (ka bax), lacagta akoontiga (EVC Plus, Bangi, Kaash), buffer/kayd, kharashyada joogtada ah iyo kuwa maalinlaha.

## Sida loo daabaco (GitHub Pages, bilaash)

1. Repo-ga gal **Settings → Pages**.
2. "Source" ka dooro **Deploy from a branch**, branch-na dooro **main** iyo **/(root)**, kadibna **Save**.
3. 1–2 daqiiqo kadib app-ku wuxuu ka shaqaynayaa:
   `https://hantigoapp.github.io/`

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

## Akoonnada iyo subscription-ka ($10 / bishii)

- Macmiil kasta wuxuu ku galaa email + furaha sirta. Akoon cusub wuxuu helaa **7 maalmood oo bilaash ah**.
- Marka muddadu dhammaato, wuxuu arkaa bogga lacag-bixinta: EVC Plus `*712*613735086*10#`, wuxuuna geliyaa lambarka uu ka soo diray.
- Maamulaha (asad.moallim@gmail.com) wuxuu galaa `admin.html`, wuxuuna riixaa **"Bixiyay +30 maalmood"** marka lacagta EVC la helo.
- Xogta waxay ku kaydsan tahay Supabase (`supabase/schema.sql`), nuqul ayaana ku jira taleefanka si uu internet la'aan u shaqeeyo.

### Dejinta Supabase (hal mar)
1. Supabase → **SQL Editor** → New query → ku dheji `supabase/schema.sql` → **Run**.
2. **Authentication → URL Configuration** → Site URL: `https://hantigoapp.github.io/` (Redirect URLs-na ku dar isla xiriirka).

## Android app

The GitHub Action "Android app" runs on every push to `main`. It publishes `HantiGo.apk` to the
`tijaabo` release (download: https://github.com/Hantigoapp/hantigoapp.github.io/releases/download/tijaabo/HantiGo.apk).
When the four `HANTIGO_*` signing secrets are set, that APK is the signed release build (accepted by
Samsung Galaxy Store, Huawei AppGallery and Uptodown) and a signed `.aab` for Google Play is attached
to the run as the `HantiGo-play-store-aab` artifact.
