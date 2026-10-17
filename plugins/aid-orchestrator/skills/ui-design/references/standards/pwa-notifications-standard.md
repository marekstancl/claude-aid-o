---
sidebar_position: 14
title: Oznámení v PWA aplikacích
description: "Kdy má aplikace uživatele vyrušit, jak se oznámení doručí spolehlivě i na iPhone a proč push nikdy nesmí být jediná cesta k informaci."
status: published
owner: "Platform"
created: 2026-08-15
updated: 2026-08-16
verified_at: 2026-08-16
---

# Oznámení v PWA aplikacích

> **Referenční implementace: WAN (LISA).** Postaveno plánem P093 (srpen 2026).
> Provozní pohled — co komu chodí, jak se to měří, jak se vyměňují klíče a co
> dělat, když nic nechodí — je na stránce
> [Oznámení do telefonu](../../wan/oznameni.md). Nový projekt kopíruje odtud
> a čte přitom oddíl [Zkušenosti z první
> implementace](#zkušenosti-z-první-implementace) níž: tenhle standard vznikl
> **dřív než kód**, takže se o něj implementace na několika místech otloukla
> a ta místa jsou opravená.

Oznámení je jediný kanál, kterým aplikace dosáhne na uživatele, který se
zrovna nedívá. Zároveň je to kanál, u kterého se **nefunkčnost pozná nejhůř
ze všech**: nedoručené oznámení nevyhodí chybu, nespadne test a nikdo si
nestěžuje — prostě se nic nestane a všichni si myslí, že se nic stát nemělo.

Proto tenhle standard řeší z devadesáti procent spolehlivost a jen z desíti
samotné odeslání. Odeslat push je půl dne práce. Postavit oznámení, kterým
uživatel po půl roce pořád věří, je něco jiného.

**Platí pro** každou eco aplikaci, která chce uživatele upozornit na událost,
u které uživatel není. Netýká se in-app hlášek, odznaků a tečkovaných
počítadel — ty nikam nedoručují a stojí mimo tenhle dokument.

## Platí to pro PWA, ne pro nativní aplikaci

Tenhle standard popisuje **Web Push v progresivní webové aplikaci** — tedy web,
který si uživatel přidá na plochu. Všechny eco aplikace jsou dnes tohohle typu.

Kdyby někdy vznikla **nativní** aplikace (z obchodu App Store nebo Google Play),
polovina pravidel níž se změní. Není to kosmetický rozdíl, proto tabulka:

| Věc | PWA (platí tenhle standard) | Nativní aplikace |
|---|---|---|
| Kudy zpráva teče | Web Push + klíče VAPID, přes push službu prohlížeče | Přímo APNs (Apple) nebo FCM (Google), s certifikátem/klíčem vydavatele |
| Co identifikuje zařízení | odběr vázaný na prohlížeč, může se sám otočit | token zařízení; **taky se mění** a obnovu musí aplikace obsloužit, ale systém na to má doloženou cestu, která funguje i na iOS |
| iPhone | **Web Push funguje jen v aplikaci přidané na plochu**; v běžné kartě prohlížeče nechodí oznámení (zbytek aplikace funguje normálně) | funguje po instalaci, žádná ruční podmínka |
| Obnova po výměně | na iOS jen srovnáním při přihlášení (bod 4) | systém dodá novou hodnotu spolehlivě, na obou platformách |
| Tlačítka v oznámení | Android ano, Safari ne | ano, na obou |
| Naplánovat oznámení bez serveru | nejde | jde (lokální oznámení) |
| Odznáček s číslem na ikoně | omezeně | ano |
| Vydání změny | nasazení webu, hned | přes obchod, kontrola i dny |

**Co zůstává stejné bez ohledu na typ aplikace** — a je to většina toho, na čem
záleží: oznámení je jen upozornění a musí mít trvalý protějšek (bod 1); výběr
událostí (bod 2); zápis do odchozí schránky v téže transakci (bod 3); obsah
zprávy je veřejný a proklik prochází kontrolou oprávnění (bod 6); povolení se
žádá na gesto (bod 7); tiché hodiny a vypnutelnost (bod 8); měření (bod 9).

Kdo bude tenhle standard číst pro nativní aplikaci: body 1-3 a 6-9 platí beze
změny, body 4, 5, 10 a 11 se přepisují podle tabulky výš.

## What (co je pravidlo)

### 1. Oznámení je upozornění, ne kanál

Každé oznámení musí mít **trvalý protějšek v aplikaci** — seznam, frontu,
kartu, cokoli, kde tatáž informace zůstane, i když se push nedoručí. Doručení
Web Pushe **není zaručené** a nikdy nebude: telefon v úsporném režimu,
odebrané povolení, smazaná ikona z plochy, vyprázdněná mezipaměť prohlížeče.

Test, jestli je aplikace v pořádku: *když vypnu doručování úplně, ztratí
uživatel informaci, nebo jen rychlost?* Pokud ztratí informaci, je návrh
špatně.

### 2. Kandidát musí projít čtyřmi podmínkami naráz

Pouze událost, která splní **všechny čtyři**, smí vyrušit:

| Podmínka | Když neplatí |
|---|---|
| **Asynchronní vůči adresátovi** — stane se, když se nedívá | Uživatel u toho stojí → stačí in-app hláška |
| **Jeden konkrétní adresát**, dohledatelný v databázi | „Někdo z týmu" = oznámení, které nikdo neřeší |
| **Jedna jasná akce**, na kterou proklik vede | Informace bez akce patří do souhrnu |
| **Vzácná** — jednotky za týden na uživatele | Šum. Uživatel oznámení vypne a tím zabije i ta užitečná |

**Stav není událost.** „Máte 47 končících smluv" je stav a notifikovat ho
denně je definice šumu. Stavy patří do **periodického souhrnu** (e-mail,
jednou týdně), ne do pushe.

**Provozní alerty nejsou uživatelská oznámení.** Vyčerpaný rozpočet, spadlá
služba, zamčený účet, odmítnutá příchozí zpráva — to jde na
alert bota `@eco_system_alerts_bot` (viz eco-system CLAUDE.md, sekce
„Telegram alert kanál"), ne do mobilu koncového uživatele.

### 3. Zápis události jde do odchozí schránky, ve stejné transakci

Oznámení se **nikdy neodesílá přímo z requestu**. Do tabulky odchozí schránky
se zapíše ve **stejné transakci** jako změna stavu, která ho vyvolala;
odesílá až samostatný běh.

Bez toho vznikají dvě chyby, které se hledají hrozně:

- změna stavu se uloží a odeslání selže → adresát se to nedozví **nikdy**,
  protože událost už neexistuje;
- odeslání projde a transakce se odrolluje → oznámení o něčem, co se nestalo.

Odesílač musí být **idempotentní** — klíč (typ události, adresát, předmět),
aby opakovaný pokus neposlal totéž dvakrát.

### 4. Odběry se spravují, jinak tiše odumřou

Odběr je vázaný na **uživatele a zařízení**, ne na uživatele — jeden člověk má
běžně telefon i počítač. Povinné minimum:

- odpověď `404` nebo `410` od push služby = odběr **smazat**, ne opakovat;
- **při přihlášení a při obnovení uložené relace ověřit, že odběr v prohlížeči
  odpovídá tomu, co má server, a při rozdílu se přihlásit znovu.** Tohle je
  hlavní a povinná cesta;
- `pushsubscriptionchange` v service workeru je **doplněk, ne náhrada**, a
  smí dělat jen to, co jde bez přihlášení.

**Proč není `pushsubscriptionchange` hlavní cestou** (opraveno 15. 8. 2026
podle první implementace — původní znění ho předepisovalo jako povinný):
Safari na iOS ho **neimplementuje vůbec**, takže na hlavní cílové platformě
by obnova neexistovala. A i tam, kde existuje, se z něj nedá zavolat
autentizované API — token bývá ve web storage, kam service worker nevidí,
a událost se navíc spouští bez otevřené stránky, takže není koho se zeptat.
Kdo obnovu postaví na téhle události, postaví ji jen pro Android.

Bez toho se po pár měsících dojde do stavu, kdy server odesílá do prázdna
a tváří se to jako úspěch.

### 5. Obsluha `push` musí VŽDY něco zobrazit

Prohlížeče na základě Push API vyžadují viditelnou reakci. Chrome po několika
tiše zpracovaných pushích **odběr zruší**. Žádné „tenhle si necháme jen na
aktualizaci stavu v pozadí".

### 6. Obsah oznámení je veřejný — patří do něj typ a odkaz, nic víc

Oznámení se zobrazuje na **odemčené i zamčené obrazovce**, komukoli, kdo se
na telefon podívá. Do textu proto nesmí jméno klienta, důvod vrácení, předmět
e-mailu, částka ani nic jiného, co je uvnitř aplikace za přihlášením.

Správný tvar: *„Dávka se vrátila k doplnění"* + odkaz. Ne: *„Novák Jan —
chybí strana 2 plné moci"*.

Z toho plyne i druhá půlka pravidla: **proklik musí projít běžnou kontrolou
oprávnění**. Oznámení je jen odkaz — o tom, co uživatel uvidí, rozhoduje
server podle jeho role, ne obsah zprávy. Odesílač zároveň nesmí doručit
uživateli, který mezitím ztratil přístup (smazaný, deaktivovaný, přeřazený).

### 7. Povolení se žádá na gesto, po přihlášení, s vysvětlením

Nikdy při startu aplikace. Systémový dialog vyskočený na neznámé obrazovce se
odklikne „ne" — a **druhá šance není**, iOS ani Android ho znovu nenabídnou.
Správné pořadí: přihlášení → vlastní obrazovka s vysvětlením, co bude chodit →
kliknutí uživatele → teprve systémový dialog.

### 8. Tiché hodiny a vypnutelnost po typech

Časové pásmo `Europe/Prague`, nic mimo pracovní dobu, pokud to není havárie.
V profilu přepínač na každý typ oznámení. **Vypnutelnost je součást
spolehlivosti** — nevypnutelné oznámení skončí vypnuté na úrovni systému,
a pak jsou zticha i ta důležitá.

### 9. Doručování se měří

Bez čísel se na výpadek přijde tak, že ho za měsíc ohlásí uživatel. Minimum:
počet živých odběrů, počet LIDÍ s aspoň jedním odběrem, čas posledního
úspěšného odeslání, počet odpovědí `410` za týden, počet položek ve schránce
čekajících déle než hodinu.

Čtyři věci, na kterých ta čísla stojí nebo padají:

- **Všechna z JEDNOHO dotazu**, tedy z jednoho okamžiku. Pět samostatných
  dotazů dá pět různých „teď" a obrazovka umí ukázat stav, který nikdy
  nenastal.
- **Čekání ve schránce se počítá od `send_after`, ne od `created_at`.** Tiché
  hodiny legitimně parkují událost i deset hodin; při počítání od vzniku by
  každá noc vypadala jako výpadek a hlídač by se všichni naučili ignorovat.
- **Počet `410` je počet DORUČENÍ, ne mrtvých zařízení.** Jeden mrtvý telefon
  s pěti čekajícími událostmi se přečte jako pět. Jednotka patří do jména
  i do popisku.
- **Kdo tu obrazovku smí vidět, se určuje spolu s rolí na endpointu.** Jinak
  vznikne sekce, která se roli zobrazí a umí vyrenderovat jedině chybu.

### 10. iPhone: jen instalovaná aplikace

Safari doručuje pouze do PWA **přidané na plochu**. V záložce ani v běžném
panelu nefunguje nic. Aplikace to musí umět **rozpoznat a poradit** — jinak
uživatel jen vidí, že mu nic nechodí. Detekce: `navigator.standalone` a
`display-mode: standalone`.

Praktický důsledek pro plánování: u cílové skupiny s iPhony je největší
nejistota projektu **onboarding, ne kód**.

### 11. Proklik musí přežít přihlašovací zeď

Proklik z oznámení při vypršené relaci nevede na cílovou stránku, ale na
přihlašovací obrazovku — a uživatel skončí na domovské stránce, netuše, kvůli
čemu ho appka volala. **Ověřit sondou dřív, než se postaví odesílač**; jinak se
vyrobí funkční doručování s nefunkčním koncem cesty.

**Nepředpokládej, že tou zdí je Cloudflare Access.** Původní znění to tvrdilo
o všech eco aplikacích a u první implementace to nebyla pravda — produkce WANu
Access před sebou nemá a přihlášení drží aplikace sama. Zeď je proto **ta
aplikační**: chybějící zapamatování cíle v ochraně routy a natvrdo zadrátovaný
skok na domovskou stránku po přihlášení. Sonda je jednoduchá (jeden požadavek
na chráněnou cestu bez přihlášení, kouknout na přesměrování) a rozhoduje, kterou
z těch dvou zdí opravuješ. Kde Access opravdu je, souvisí s tím i servírování
manifestu — vystavuje se oklikou přes vlastní API cestu, protože kořenovou
cestu Access zachytí.

**Zapamatovaný cíl je vstup od útočníka.** Jakmile si aplikace pamatuje, kam
chtěl uživatel jít, má otevřené přesměrování, pokud ten řetězec nekontroluje:
musí začínat jedním lomítkem, nesmí začínat dvěma (to je jiný původ) a nesmí
obsahovat zpětné lomítko **nikde** — normalizace v routeru z něj udělá lomítko
až po kontrole. Platí to pro tutéž hodnotu v service workeru i ve stránce.

## Why (proč to platí)

Typický rozbitý stav nevypadá jako chyba. Vypadá takhle:

1. Někdo napíše obsluhu oznámení a otestuje ji na svém počítači. Funguje.
2. Odeslání visí přímo v požadavku, protože „je to jen jeden HTTP call".
3. Půl roku nikdo nic nehlásí, protože nedoručené oznámení nikoho neupozorní
   na to, že nedorazilo.
4. Pak se zjistí, že polovina uživatelů má odběr mrtvý od aktualizace
   prohlížeče, třetina si to nikdy nepovolila a zbytku se to ztratilo mezi
   ostatními oznámeními, protože chodilo desetkrát denně.

Každé jednotlivé pravidlo výše zavírá jeden z těchhle čtyř kroků. Nejdražší je
bod 3: mrtvý notifikační kód se v eco projektech **už jednou stal** — WAN má
od P008 kompletní pomocnou vrstvu v `ui/src/lib/notify.ts` a obsluhu
v `ui/public/sw.js`, kterou nikdy nikdo nezavolal, takže povolení se nikdy
nevyžádalo a oznámení nikdy nevzniklo. Vypadalo to jako hotová funkce.

## How (jak se to dělá)

### Znovupoužitelné jádro

Sdílí se **standard a tvar, ne balíček** (stejně jako u ostatních eco
pravidel — G-020 zakazuje sdílené databáze, projekty mají vlastní stack).
Nový projekt kopíruje z referenční implementace a přizpůsobí si typy událostí.

| Vrstva | Co je stejné napříč projekty | Co je per projekt |
|---|---|---|
| Klíče VAPID | postup vygenerování, uložení v prostředí | vlastní pár na aplikaci |
| Tabulka odběrů | schéma, čištění mrtvých | — |
| Odchozí schránka | schéma, odesílač, idempotence, tiché hodiny | typy událostí, texty |
| Service worker | obsluha `push`, `notificationclick` | cílové cesty prokliků |
| Obnova odběru | srovnání při přihlášení a při obnovení relace | kde v aplikaci přihlášení žije |
| Přihlášení k odběru | okamžik, obnova, detekce iOS | obrazovka s vysvětlením |

### Datový tvar (minimum)

Odběry — jeden řádek na zařízení:

```
push_subscriptions
  id, user_id, endpoint (ČÁSTEČNÝ UNIQUE — jen WHERE deleted_at IS NULL), p256dh, auth,
  user_agent, created_at, last_success_at, last_failure_at, failure_count
```

Odchozí schránka — jeden řádek na **událost**, ne na zařízení:

```
notification_outbox
  id, user_id, event_type, subject_id, occurrence_key,
  title, body, url,
  created_at, send_after, claimed_at, done_at
  UNIQUE (event_type, user_id, subject_id, occurrence_key)   -- idempotence
```

Pokusy o doručení — jeden řádek na **událost × zařízení**:

```
notification_delivery
  id, outbox_id, subscription_id,
  attempts, last_status, last_attempt_at, retry_after, final, last_error
  INDEX (last_status, last_attempt_at)   -- kvůli měření (bod 9)
```

Tři věci, které si tenhle tvar vynutila první implementace a které v původním
znění chyběly (podrobněji v oddílu „Zkušenosti" na konci):

- **`occurrence_key` jako čtvrtý sloupec klíče.** Trojice (typ, adresát,
  předmět) se legitimně opakuje: dávka se vrátí, obchodník ji doplní, vrátí se
  znovu. Bez čtvrtého členu by druhé vrácení `ON CONFLICT` zahodil. Klíč se
  odvozuje **z přechodu** (čas přechodu spočítaný na volajícím místě), ne
  z hodin v okamžiku volání — jinak nekoliduje nikdy a idempotence je jen
  ozdoba. Délku sloupce hlídej v kódu; delší hodnota jinak spadne na
  `DataError` **uvnitř cizí transakce**, tedy jako by selhala obchodní změna.
- **`last_error` patří na DORUČENÍ, ne na událost.** Když má člověk telefon
  i počítač, přepíše poslední selhavší zařízení hlášku po tom druhém a z jednoho
  řádku už nejde poznat, čí ta chyba byla. Chybový signál pro měření se pak
  nedá postavit vůbec.
- **`retry_after` a `final` na doručení, `claimed_at` na události.** Jsou to
  dvě různé věci a snadno se pletou — viz „Odesílač" níž.

Odběry mají `endpoint` unikátní **jen mezi živými řádky** (částečný index
`WHERE deleted_at IS NULL`). Opětovné přihlášení zakládá NOVÝ řádek, ne
vzkříšení starého — jinak `created_at` lže o tom, kdy se zařízení přihlásilo.

Dvě tabulky, a ne jedna, protože jeden člověk má víc zařízení: telefon může
odpovědět `410` (mrtvý odběr) zatímco počítač doručí. Sloučené do jednoho
řádku by se to muselo vyhodnotit jako „celé selhalo" nebo „celé prošlo" —
obojí je lež a obojí vede k opakovanému doručení na to funkční zařízení.

`send_after` řeší tiché hodiny bez zvláštní logiky v odesílači: událost, která
vznikne ve 22:40, dostane čas na ráno. Počítá se v `Europe/Prague`, ne v UTC —
v létě je to dvě hodiny rozdílu a oznámení dorazí, když nemá.

### Odesílač je samostatný běh, ne úloha na pozadí

`BackgroundTasks` ve FastAPI ani `asyncio.create_task` **nejsou** odesílač.
Obojí zmizí s restartem procesu a nemá opakování; typický precedens v eco
projektech je odeslání alertu stylem „pošli a zapomeň", které při chybě jen
zaloguje varování. Pro provozní alert je to v pořádku, pro uživatelské
oznámení ne.

Odesílač si událost **zabere** (claim), zkusí doručit na všechna zařízení,
zapíše výsledky a s odstupem to zopakuje.

**Zabrání není zámek databáze.** První implementace to zkusila číst doslova
a skončila u jediného tvaru, který funguje: zabrání je **UPDATE, který vrátí
zabrané řádky** —

```sql
UPDATE notification_outbox SET claimed_at = now()
WHERE id IN (
  SELECT id FROM notification_outbox
  WHERE done_at IS NULL AND send_after <= now()
    AND (claimed_at IS NULL OR claimed_at < now() - interval '10 minutes')
  ORDER BY send_after LIMIT :limit FOR UPDATE SKIP LOCKED
)
RETURNING id
```

Proč zrovna takhle: `FOR UPDATE SKIP LOCKED` udělá výběr bezkolizní i při dvou
běžících instancích (každý řádek si vezme právě jedna), `LIMIT` musí být uvnitř
poddotazu (`UPDATE … LIMIT` v PostgreSQL neexistuje) a stáří zabrání propouští
řádky po pádu instance, které by jinak zůstaly zabrané navždy. Skutečný zámek
by musel držet transakci po celou dobu čekání na cizí push službu — což je
přesně to, co dělat nechceme.

**Zabrání a odstup jsou dvě různé věci.** `claimed_at` chrání před souběhem
instancí; `notification_delivery.retry_after` řídí, kdy se smí zkusit znovu.
Kdyby opakování řídilo zabrání, žádný odstup kratší než životnost zabrání by
nemohl nastat. Nevyřízená událost se proto na konci průchodu **uvolní**
a o dalším pokusu rozhoduje `retry_after`.

**Práce musí být ohraničená, ne jen intervalová**, a ta čísla jsou provázaná:
interval + rozpočet průchodu + souběžnost + strop doručení na průchod dohromady
dávají nejhorší čekání. Vypiš je vedle sebe jako jeden celek, protože kdo změní
jedno, musí přepočítat zbylá — a **hodnota v šabloně prostředí musí být stejná
jako výchozí hodnota v kódu**. Rozejít se to umí tiše: v první implementaci
šablona ještě týden nesla trojnásobný interval, slib „do minuty" tím padl a
nespadl na tom jediný test.

Mez počítej v **DORUČENÍCH, ne v událostech**. Jedna událost může mít libovolný
počet zařízení, takže dvacet událostí může znamenat dvě stě doručení.

### Klíče a prostředí

Pár VAPID se generuje jednou na aplikaci, veřejná část jde do klienta, tajná
do prostředí (`services/.env` nebo projektový `.env`, **nikdy do gitu**).
Změna páru **zneplatní všechny existující odběry** — je to jednosměrná operace,
po které se musí všichni uživatelé přihlásit znovu.

**Generátor klíčů vypisuje tajnou část na terminál.** Je to záměr (nikam ji
nezapisovat je bezpečnější než soubor, na který se zapomene), ale znamená to,
že klíč projde historií shellu, případným záznamem relace a schránkou. Kdo ho
generuje, ať to dělá na stroji, kde mu to nevadí, a ať historii potom uklidí.

### Obsluha v service workeru

```js
// Odkaz z pushe je VNĚJŠÍ VSTUP. `clients.openWindow()` umí podle specifikace
// otevřít i cizí původ, a tahle větev běží právě tehdy, když je telefon zamčený
// a žádné okno otevřené není. Guard musí být na OBOU cestách (zápis i klik)
// a musí odmítat i zpětné lomítko — normalizace v routeru z něj udělá lomítko.
function samePath(u) {
  if (typeof u !== 'string' || !u.startsWith('/') || u.startsWith('//')) return '/';
  if (u.includes('\\')) return '/';
  // Řídicí znaky MUSÍ ven taky. Prohlížeč tab/LF/CR z URL vyhazuje JEŠTĚ PŘED
  // parsováním, takže „/\t/evil.com" se stane „//evil.com" — protokolově
  // relativní adresa na cizí doménu — a `clients.openWindow` ji otevřít smí.
  // Ukázka to dřív neměla, přestože pravidlo 3 níž to přikazuje; našla to
  // revize posledního kroku P093.
  // eslint-disable-next-line no-control-regex
  if (/[\u0000-\u001f\u007f]/.test(u)) return '/';
  return u;
}

// Klik je ta druhá cesta, a je to ta, která `openWindow` doopravdy volá —
// proto tudy MUSÍ projít guard taky, ne jen při zápisu do oznámení.
self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const url = samePath(event.notification.data && event.notification.data.url);
  event.waitUntil(
    self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then((all) => {
      for (const c of all) {
        if (new URL(c.url).origin === self.location.origin && 'focus' in c) {
          c.focus();
          c.postMessage({ type: 'navigate', url });
          return;
        }
      }
      if (self.clients.openWindow) return self.clients.openWindow(url);
    }),
  );
});

self.addEventListener('push', (event) => {
  // Data mohou chybět (testovací push z devtools) — i tak MUSÍME něco ukázat,
  // jinak prohlížeč po pár tichých pushích odběr zruší.
  let d = {};
  try { d = event.data ? event.data.json() : {}; } catch (e) { /* necháme prázdné */ }
  event.waitUntil(
    self.registration.showNotification(d.title || 'Nová událost', {
      body: d.body || '',
      // `tag` posílá SERVER a skládá ho z typu události a předmětu. Bez něj
      // se seskupuje podle URL, takže „dávka se vrátila" a „zpracování
      // selhalo" u TÉŽE dávky splynou v jedno oznámení.
      tag: d.tag,          // stejný tag = nahrazení, ne hromada
      data: { url: samePath(d.url) },
    }),
  );
});

// `pushsubscriptionchange` je doplněk: na iOS neexistuje a autentizované API
// odsud volat nejde. Skutečnou obnovu dělá aplikace při přihlášení.
self.addEventListener('pushsubscriptionchange', (event) => {
  event.waitUntil(markSubscriptionStale());   // jen značka, žádné volání API
});
```

### Špatně

```python
# Odeslání přímo v požadavku: když push service neodpoví, buď spadne
# uživatelův požadavek, nebo (u fire-and-forget) událost zmizí beze stopy.
await session.commit()
await push_client.send(subscription, payload)
```

```js
// Vyžádání povolení při startu — jednorázová šance zahozená na obrazovce,
// kde uživatel netuší, o co jde.
Notification.requestPermission()
```

## Exceptions (výjimky)

Standard se netýká aplikací, které uživatele upozorňují **jen zatímco jsou
otevřené** (in-app hlášky, odznaky, tečky u položek menu). Ty žádné doručování
neřeší a nic z výše uvedeného pro ně neplatí.

Aplikace, která odesílá jen provozní alerty směrem k obsluze, používá
alert bota `@eco_system_alerts_bot`, ne Web Push, a tenhle standard se jí netýká.

## Enforcement (jak se vynucuje)

### Kontrola za dvě minuty

```bash
# 1) Je notifikační kód vůbec živý? (klasická past — vrstva existuje, nikdo ji nevolá)
grep -rn "requestPermission\|pushManager.subscribe" ui/src --include=*.ts --include=*.tsx

# 2) Má service worker obsluhu push, nebo jen lokální notifikace?
grep -n "addEventListener('push'" ui/public/sw.js

# 3) Kolik odběrů je živých a kdy naposledy něco prošlo
psql -c "SELECT count(*), max(last_success_at) FROM push_subscriptions;"

# 4) Neleží něco ve schránce? (`send_after`, NE `created_at` — viz bod 9)
psql -c "SELECT count(*) FROM notification_outbox WHERE done_at IS NULL AND send_after < now() - interval '1 hour';"
```

Nula u bodu 1 při existující vrstvě v repu znamená mrtvý kód, ne chybějící
funkci.

### Akceptační test

1. Přihlásit se na telefonu, povolit oznámení, **zavřít aplikaci**.
2. Z druhého účtu vyvolat událost.
3. Oznámení dorazí na zamčenou obrazovku, proklik otevře správnou stránku —
   **i po vypršení relace Cloudflare Access** (bod 11).
4. Odebrat aplikaci z plochy, znovu přidat, přihlásit se: odběr se obnoví sám,
   starý řádek v databázi zmizí (bod 4). **Na iPhonu je tohle jediná cesta,
   jak se odběr obnoví** — proto se ten krok nesmí vynechat.

Bod 3 a 4 jsou ty, které se v praxi vynechávají a které rozhodují.

Dál musí být pokryté testem (proti falešné bráně, ne proti reálné push
službě):

- neúspěšný obchodní commit **nevytvoří** událost ve schránce;
- restart procesu po zápisu do schránky událost přesto doručí;
- opakovaný pokus nevyrobí druhé oznámení;
- odpověď `410` odběr zruší;
- smazaný nebo deaktivovaný uživatel nedostane nic.

### Automatická brána

Zapojení odesílací cesty se hlídá testem na úrovni struktury, ne chování —
tedy „místo, kde vzniká událost, opravdu zapisuje do schránky". Testy chování
u oznámení bývají integrační a na cestě k merge neběží (viz
[Test standard](./test-standard)).

**Ten test se musí ověřit mutací**, ne přečtením. Postup: smaž po jednom každé
volání, které test tvrdí že hlídá, a přesvědč se, že spadne. Bez toho je to
jen kus textu, který kontroluje kus textu — a přesně tenhle druh testu umí
zůstat zelený nad mrtvým produktem (viz bod 3 v oddílu níž).

Vedlejší důsledek, na který se přijde až později: **strukturální test váže
funkci k modulu.** Přesun funkce jinam takový test buď shodí, nebo — hůř —
vykuchá i integrační testy, které si ji záplatují přes `monkeypatch` na
původním modulu, aniž by kterýkoli z nich zčervenal. Než se funkce přesune,
projdi, kdo ji záplatuje.

## Zkušenosti z první implementace

Tenhle standard vznikl **dřív než kód**, což byl záměr — a taky to znamená, že
se o něj implementace musela otlouct. Body níž nejsou stížnosti; jsou to
opravy, které už jsou zapracované do textu výš. Nový projekt je čte proto, aby
o ně nezavadil znovu.

Zdroj: WAN (LISA), plán P093, srpen 2026 — dva typy událostí, role „obchodník
v terénu", převážně iPhony.

### 1. „Zamkni událost" je špatná rada. Vyhrálo zabrání řádku

**Standard říkal:** odesílač událost *zamkne* (claim).

**Realita:** skutečný zámek databáze by musel držet transakci po celou dobu
čekání na cizí push službu — tedy spojení do databáze blokované na sekundy až
na timeout, a to na každou událost. Fungovat začalo teprve
`UPDATE … FOR UPDATE SKIP LOCKED … RETURNING`: zabrání je **zápis času do
sloupce**, ne zámek, a `SKIP LOCKED` řeší souběh dvou instancí bez čekání.
Přesné znění je v oddílu „Odesílač" výš.

Dvě věci, které se přitom ukázaly a v původním textu nebyly vůbec:

- **zabrání se musí po vypršení propouštět** (jinak řádek po pádu instance
  zůstane zabraný navždy a nikdy se nedoručí), a
- **zabrání není odstup.** Kdyby o dalším pokusu rozhodovalo zabrání, žádný
  odstup kratší než jeho životnost by nemohl nastat.

**Generalizuje:** ano, na každou odchozí schránku nad SQL databází.

### 2. Ověřovat adresu jedním rozborem a odesílat druhým je díra, ne nepřesnost

Nejzávažnější nález celého plánu a **není specifický pro oznámení** — proto je
teď pravidlem tady.

Obrana adresu odběru rozebírala jedním rozborovačem (`urlsplit`), ale odesílalo
se knihovnou, která používá jiný (`urllib3`/`requests`). Na adrese
`https://169.254.169.254\@fcm.googleapis.com/...` se ty dva **rozešly**: jeden
viděl povoleného hostitele, druhý metadatovou službu cloudu. Propustilo to
naráz seznam povolených hostitelů, zákaz holé IP i zákaz vnitřních rozsahů.
Táž adresa bez zpětného lomítka se odmítala správně — rozdíl dělal jediný znak.
Kromě osahání vnitřní sítě by útočníkovi odešla i hlavička s podpisovým
tokenem.

Táž třída chyby se v tomtéž plánu objevila **podruhé a jinde**: ověřoval se
`url.strip()`, ale ukládal a odesílal se neořezaný řetězec. A **potřetí** na
frontendu, kde se zapamatovaný cíl prokliku kontroloval jinak, než jak ho
potom normalizoval router.

**Pravidlo, které z toho plyne** (platí pro každou adresu z vnějšku, ne jen pro
odběry):

1. **Ověřuj přesně ten řetězec, který se odešle.** Žádné ořezání, doplnění ani
   normalizace mezi kontrolou a použitím.
2. **Rozeber adresu OBĚMA rozborovači a trvej na shodě hostitele.** Rozhoduje
   ten, kterým se skutečně odesílá; neshoda znamená, že nevíme kam to poletí,
   a to není co odpouštět ani v ladicím režimu.
3. **Znaky, na kterých se rozborovače rozcházejí** (zpětné lomítko, bílé
   a řídicí znaky), odmítej rovnou.
4. **Test musí porovnat skutečný cíl**, tedy hostitele, který vytočí odesílací
   knihovna — ne výčet literálů. Revize před tímhle nálezem prošla přes 52
   tvarů adresy a nenašla nic, protože „skutečný cíl" počítala **týmž
   rozborovačem, kterým se kontroluje**. Ověřovala se proti špatné referenci.

Ještě jedna past ze stejného rohu: vlastní `requests.Session` postavená kvůli
zákazu přesměrování **dědí `trust_env=True`**, takže proměnná `HTTP_PROXY`
v prostředí odkloní celý odchozí provoz — včetně podpisové hlavičky — mimo
seznam povolených hostitelů.

**Generalizuje:** ano, na jakékoli odchozí volání na adresu, kterou určil
uživatel.

### 3. Test, který kontroluje řetězec ve zdrojáku, umí zůstat zelený nad mrtvým produktem

Zákaz přesměrování u odesílání byl několik commitů **rozbitý a nedoručovalo se
nic**, zatímco test, který ten zákaz „hlídal", byl celou dobu zelený — hlídal
totiž přítomnost textu ve zdrojovém souboru, ne chování.

Je to táž rodina jako past, kvůli které tenhle standard vůbec vznikl (mrtvá
notifikační vrstva, kterou nikdo nevolal). Rozdíl je v tom, že tady navíc
existoval **doklad o opaku**.

**Pravidlo:** strukturální test je legitimní tam, kde test chování běží jen
v noci — ale
1. musí být **ověřený mutací** (smaž to, co hlídá, a přesvědč se, že spadne),
2. **nesmí být jediným dokladem, že věc funguje**. Aspoň jeden test v portfoliu
   musí projít celou cestou proti falešné bráně na smyčce, i kdyby běžel jen
   v noci.

Přidej k tomu dvě konkrétní díry v nástrojích, na které se přišlo:
**brána, která vypisuje výsledky po souborech, nevidí soubor, který spadne už
při sběru** (nula testů = nula spadlých jmen = zeleno nad mrtvým souborem),
a **falešná push brána musí být vícevláknová** — jednovláknový server měří
sám sebe, ne souběžnost odesílače.

**Generalizuje:** ano, mimo oznámení úplně.

### 4. `pushsubscriptionchange` jako povinná cesta obnovy — opraveno předem

Původní znění ho předepisovalo jako povinnou cestu obnovy odběru. Safari na
iOS ho **neimplementuje vůbec** a i tam, kde existuje, se z něj nedá zavolat
autentizované API. Opraveno ještě před implementací (commit `cac6a01`), znění
je v bodu 4; tady zůstává jen záznam, že to byla první chyba standardu, na
kterou se přišlo.

Implementace k tomu doplnila dvě věci, které v bodu 4 nebyly:

- **Srovnávat samotnou adresu odběru nestačí.** Po výměně klíčů VAPID zůstává
  adresa stejná, takže „prohlížeč odběr má, server ho má taky" nic neudělá —
  a další pokus o přihlášení k odběru skončí chybou. Srovnávat se musí i
  **veřejný klíč**, kterým byl odběr sjednán. Je to zrovna ten případ, který
  standard sám vyjmenovává jako důvod, proč obnova existuje.
- **Srovnání potřebuje místní příznak „nechci".** Bez něj se odběr při každém
  přihlášení znovu zapne uživateli, který si ho vědomě vypnul.

### 5. Odběr přežije odhlášení — a je to nejčastější nedorozumění celé funkce

Standard mlčel o vztahu odběru a přihlášení, protože se zdál zřejmý. Není.

Odběr je adresa zařízení u push služby. **S přihlášením nemá společného nic**:
přežije odhlášení, přežije zamčení účtu, přežije vypršení relace. Na předaném
nebo sdíleném telefonu z toho vzniká stav, ze kterého se uživatel sám
nedostane — bývalému majiteli dál chodí oznámení a nový narazí na „tenhle odběr
patří někomu jinému" s radou „odhlaste se tam", přičemž právě to udělal.

**Pravidla, která z toho plynou:**

- **odhlášení odběr uvolní** — best-effort, na pozadí, odhlášení na to nesmí
  čekat ani na tom spadnout (potřebuje ještě platnou autorizaci, takže běží
  PŘED zahozením tokenu);
- **uvolnění při odhlášení NESMÍ nastavit příznak „nechci oznámení"** — odchod
  z účtu není totéž co odmítnutí funkce, jinak si další uživatel téhož zařízení
  oznámení nezapne a nezjistí proč;
- **zámek účtu po neúspěšných přihlášeních odběry NERUŠÍ** — je to dočasná
  zábrana přihlášení, ne odchod;
- **obě vrstvy jsou potřeba.** Úklid při odchodu uživatele (poctivost) i filtr
  adresáta při odesílání (bezpečnost). Úklid běží ve vnořené transakci a nesmí
  shodit odchod uživatele, takže se nedá spolehnout na to, že proběhl vždy;
  filtr zase nic neuklízí. Kdo jednu z nich smaže jako zdvojenou, buď nechá
  odběr přežít člověka, nebo si vyrobí tabulku odběrů neexistujících lidí.

**Generalizuje:** ano, na každou aplikaci, kde se zařízení předávají nebo sdílí.

### 6. Service worker se nemá jak autentizovat — a standard s tím počítal jen implicitně

Token bývá ve web storage, kam service worker nevidí, a událost se spouští bez
otevřené stránky, takže není koho se zeptat. Je to důvod, proč obnova stojí na
srovnání při přihlášení (bod 4), ale platí i jinam: **cokoli, co má service
worker udělat, musí jít bez přihlášení.** Značka „odběr je zastaralý" ano;
volání API ne.

Druhá půlka: **service worker je samostatný skript mimo balík aplikace**, takže
si s ní nemůže sdílet moduly. Kontrola odkazu proto v aplikaci existuje
dvakrát — jednou ve workeru, jednou ve stránce — a to jsou dvě kopie, které
se rozejdou. Buď sdílený soubor s testovacími vektory, nebo test, který obě
těla porovná.

A do třetice, drobnost s velkým dopadem: **verzi mezipaměti service workeru je
nutné zvednout.** Bez toho běží dál uložený worker bez obsluhy `push` a každá
zpráva se zahodí — potichu.

### 7. „Ve stejné transakci" nestačí. Rozhoduje POŘADÍ zápisů

Bod 3 předepisuje zápis události do schránky ve stejné transakci jako změnu
stavu. Doslovné splnění téhle věty **nestačí**: vstup do vnořené transakce
provede flush, takže rozdělaná práce volajícího se do databáze dostane
**PŘED** savepointem a savepoint ji už neochrání. Implementace, která zapíše
stav a pak do savepointu zabalí událost, splňuje každé slovo bodu 3 a přesto
umí nechat dávku ve špatném stavu, když zápis události selže.

**Pravidlo:** událost se zapisuje **PŘED** změnou stavu, a je na to test.
Táž rodina: úklid odběrů musí změnu uživatele **flushnout ještě před** otevřením
savepointu, jinak si odrolování savepointu vezme i ji.

Dvě další věci ze stejného rohu:

- **Zápis události nesmí spustit autoflush.** Jinak vyleje do databáze
  rozdělanou práci volajícího — cizí objekty, o kterých nic neví, v okamžiku,
  který si nezvolil. Test na to musí ověřovat ten přepínač; falešná session
  s počítadlem `flush()` tuhle chybu nechytí, protože autoflush `flush()`
  nevolá.
- **Politika při selhání je per volací místo, ne globální.** Na uživatelské
  cestě (asistentka vrací dávku) je správné nechat výjimku propadnout —
  ať selže obojí najednou, protože tiše ztracené oznámení o vrácení je horší
  než chyba na obrazovce. Na cestě „zpracování selhalo" je správné ji spolknout
  — stav `failed` se musí zapsat tak jako tak.

**Generalizuje:** ano, na každou odchozí schránku nad ORM.

### 8. Dlouho žijící odesílač musí číst z databáze, ne z paměti

Session odesílače přežije v jednom průchodu několik commitů. Bez vynuceného
čtení z databáze se odstupy, příznaky smazání i předvolby uživatele načtou
jako kopie z doby před commitem — takže **opakování v provozu tiše nefunguje**,
zatímco v testu s krátkou session vypadá dobře.

**Generalizuje:** ano, na každou smyčku, která si bere práci a drží session.

### 9. Nová knihovna znamená STAVBU obrazu, ne restart

Knihovna pro Web Push je nová závislost. Nasazení stylem „stáhni a nastartuj"
skončí tím, že se aplikace **vůbec neimportuje** — tedy úplný výpadek, ne
nefunkční oznámení. Vedlejší, obecnější důsledek zapsaný během téhle práce do
ekosystémového CI standardu: **CI musí obraz stavět, ne jen používat**, a stavba
patří PŘED kontrolu stylu, protože ta běží v tomtéž obrazu.

Dvě drobnosti ze stejného kroku, obě z kategorie „první, co provozní uvidí":

- **Ověření konfigurace při startu nesmí vyhazovat `ValueError` z validátoru
  modelu nastavení.** Vstupem validátoru je celý objekt nastavení a ten se
  z výjimky dá vytáhnout celý — tedy všechna tajemství aplikace. Brání se
  **typem výjimky**, ne textem hlášky, a test to musí ověřovat na typu.
- **Hláška při startu nesmí odkazovat na soubor, který v produkčním obrazu
  není.** Skripty se do obrazu běžně nekopírují a odkaz na generátor klíčů je
  pak první věc, co provozní uvidí selhat.

### 10. Co se do standardu nedostalo, protože to bylo mimo jeho rámec

Zaznamenáno pro příště, ne jako pravidlo:

- **Samočinné hledání uvízlých položek** (dávka, kterou nikdo neotevřel, tedy
  se nikdy nepřeklopila do „selhalo") mění hlídač spouštěný čtením na
  **nehlídaného odesílatele**. První zapnutí umí rozeslat oznámení o věcech
  starých týdny — **před zapnutím spočítej historickou frontu a ukliď ji**.
- **Události bez adresáta se zahazují, nevymýšlí se jim příjemce.** Dávky
  z e-mailového kanálu autora nemají. Souvisí s tím i to, že přiřazovat příjemce
  podle hlavičky `From` znamená, že podvržený e-mail se stane kanálem do cizího
  telefonu — a jediné, co z toho dělá pouhou otravu, je fakt, že texty zpráv
  jsou konstanty (bod 6). Ty konstanty tedy nesou víc, než se zdá.
- **Tiché hodiny otravují testy.** Sada, která je nevypne, po 21:00 nedoručí
  nic a je závislá na denní době.
- **Karta s povolením potřebuje stav „načítám".** Než dorazí odpověď serveru,
  nabízí zapnutí i tam, kde je funkce vypnutá — a rychlé kliknutí spálí tu
  jedinou šanci na systémový dialog, o které mluví bod 7.
- **Seznam povolených hostitelů je i rozhodnutí o dostupnosti**, ne jen
  o bezpečnosti. Chybí-li v něm push služba Microsoftu, uživatelé Edge se
  nepřihlásí a nikdy se nedozvědí proč. Rozsah prohlížečů se rozhoduje dřív,
  než se seznam napíše.
- **Logování na cestě přihlášení k odběru nesmí vypsat celou chybu klienta** —
  nese autorizační hlavičku a klíče odběru. Jen text hlášky.
