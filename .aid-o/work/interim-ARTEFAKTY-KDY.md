# Kdy smí vzniknout stránka pro PM (zadání PM, 2026-08-28)

Doslovné znění PM, protože každá dřívější formulace se zvrhla v „renderuj vždycky":

> do evidence nepotřebuju artefakty!!! potřebuju je jak se dopíše plán, ale OPRAVDU
> AŽ SE DOPÍŠE A JE SCHVÁLENEJ A JE VE STAVU GENERUJEME EPICY NIKDY NE DŘÍV!!!!!!
> PŘÍPADNĚ dříve, jen za předpokladu, že se po mě chtějí nějaká rozhodnutí!
> a potom v manual plánu (po EPicu a nakonci plánu) ale zase až po všech kontrolách!!!
> v auto plánu pak jen úplně na konci před MERGE po všech kontrolách zase!!

## Pravidla, jak je bude číst kód

| # | Kdy | Podmínka, která musí platit SOUČASNĚ |
|---|---|---|
| 1 | plán | je dopsaný **a schválený** **a** stav plánu je „generujeme EPICy" |
| 2 | kdykoliv dřív | **jen** když stránka po PM něco chce (je v ní rozhodnutí) |
| 3 | manuální plán | po EPICu a na konci plánu — **až po všech kontrolách** |
| 4 | autonomní plán | **jen** úplně na konci, před MERGE — až po všech kontrolách |

## Co z toho plyne pro kód

- **Evidence není důvod k renderu.** Dnes renderuje pět volajících a žádný se
  neptá, jestli to má jít PM. Vzniknout smí jen to, co odpovídá tabulce výše.
- **Stránka bran (`aid-gate-outcome-summary.sh`) se PM neukazuje nikdy**, ledaže
  by nesla rozhodnutí (pravidlo 2). Doloženo na živém běhu WAN E-099-1_3: v bloku
  „Co se čeká ode mě" stálo „Nic — ozvu se, až bude hotovo". Stránka, která sama
  říká, že nic nechce, nemá PM chodit.
- **„Po všech kontrolách" je součást podmínky, ne dobrá vůle.** Render se nesmí
  spustit, dokud kontroly nedoběhly — jinak stránka nese čísla, která ještě
  neplatí. Tohle je totéž, co dnes hlídá hook „stránka je starší než plán", jen
  z druhé strany.
- **Rozhodnutí je jediná výjimka.** Pravidlo 2 je proto potřeba umět strojově
  poznat: stránka nese neprázdný blok rozhodnutí → smí ven kdykoliv.

## Měření, které to zadání odůvodňuje
WAN vyrobil za dva dny **17 stránek**; PM z nich chtěl **jednu**.
