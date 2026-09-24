# P099 — volba modelu pro roli Codex (krok 2)

Měřeno 23. 9. 2026 na jednom skutečném balíku: CP1 plánu P099, kolo 1, role
`generalist_b` (prompt 62 kB, stejný strom `main` 9de9b9c3).

## Proč ne `gpt-6-sol`

Plán počítal s `gpt-6-sol`. Na účtu, přes který Codex běží (ChatGPT účet),
ho Codex odmítá: `The 'gpt-6-sol' model is not supported when using Codex with
a ChatGPT account` (HTTP 400). Dostupné jsou `gpt-5.6-sol`, `gpt-5.6-terra`,
`gpt-5.6-luna`, `gpt-reserve` (`~/.codex/models_cache.json` ze 23. 9. 21:04).
Srovnání proto proběhlo mezi `gpt-5.6-terra` a `gpt-5.6-sol`.

## Výsledek

| | gpt-5.6-terra, effort high | gpt-5.6-sol, effort medium |
|---|---|---|
| nálezy | 4 blokery | 5 blokerů, 2 major |
| tokeny vstup / z cache / výstup | 872 156 / 771 584 / 6 403 | 1 024 409 / 928 384 / 7 081 |
| čas | ~2,5 min | 4 min 13 s |

Terra našla: (1) kopie adaptéru v `aid-plan.md` zůstává na starém typu agenta,
(2) odposlech „agent čeká" podle stavu plánu nepohlídá strop dvou zpráv,
(3) instrukce v pipeline dál každá publikovat stránku EPICu, (4) počítadlo
pokračování zapisované hookem do `.aid-o/work` porušuje pravidlo, že stav hooku
je mimo strom.

Sol našel (1), (2), (3), ne (4); navíc čtyři vlastní: záložní revizor je jen
vytištěná instrukce, `/aid-init` dnes nevytváří `orchestration.yaml`,
klasifikace konce kola pro výpočet času není definovaná, a následné měření
v kroku 10 nemá práh úspěchu.

## Rozhodnutí

Pravidlo kroku 2: sol zůstává, jen když najde aspoň blokery, které našla terra,
a tokeny má do 1,5× terry. Tokeny splnil (1,17×), blokery ne (3 ze 4).
**Nastaveno: `gpt-5.6-terra`, effort `high`** (`review-checkpoints.yaml`,
výchozí `CODEX_MODEL` v `lib/aid-codex-transport.sh`), tedy přesně to, co bylo
změřeno. Srovnání zopakovat, až účet pustí řadu `gpt-6` nebo až `gpt-5.6`
přestane být k dispozici.
