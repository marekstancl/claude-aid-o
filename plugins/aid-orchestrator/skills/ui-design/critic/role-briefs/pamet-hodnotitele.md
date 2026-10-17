# Paměť hodnotitele mezi koly (obě role, všechna místa rozhodnutí)

Důvod (dílna F3 na zkušebním podniku, kola 3–5): odborník bez paměti v každém kole našel jiné drobnosti a skóre kmitalo
(7,15 → 6,65 → 6,55), i když studio opravilo, co bylo vytknuto. Studio pak honí pohyblivý cíl a kolo nekonverguje.
Praxe: opakovaná revize v agenturách i v code review hodnotí „opraveno / neopraveno“ proti předchozím připomínkám
a nové připomínky v pozdním kole přidává jen u věcné chyby (Google eng-practices „Code Review“: reviewer
neblokuje změnu, která celkově zlepšuje stav, kvůli drobnostem; „Nit:“ nálezy neblokují).

Pravidla:
1. Hodnotitel dostane své předchozí hodnocení (skóre, nálezy, cesta k 10) a nový návrh.
2. Nejdřív u každého předchozího nálezu zapíše `opraveno | částečně | neopraveno` s citací místa.
3. Nový nález v dalším kole smí snížit skóre kritéria pod předchozí úroveň jen tehdy, je-li **věcný**:
   nepravdivé nebo nedoložené tvrzení, chybný odborný pojem, právní riziko, rozpor se zdroji.
   Ostatní nové nálezy (styl, volba slova, „šlo by lépe“) jsou `drobnost` – zapíše je, ale skóre jimi nesnižuje.
4. Skóre kritéria = předchozí skóre ± změny podle bodů 2 a 3; každé zvýšení i snížení s důvodem.
5. Kotvy a strop (test dosazení) platí dál beze změny – paměť neznamená shovívavost.
6. Studio dostane jen nálezy a cestu k 10, ne skóre ani brány (ty zná jen kód).
