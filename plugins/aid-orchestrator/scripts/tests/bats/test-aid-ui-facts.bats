#!/usr/bin/env bats
# aid-tier: t1
# aid-subject: lib/ui-fidelity/aid-ui-facts.mjs
# P108 Step 4 — aid-ui-facts.mjs (the gate's facts_match): counted numbers, percentages, years and
# e-mails need a register entry with the same number and a stem of the same meaning; no browser.

setup() { LIB="$BATS_TEST_DIRNAME/../../../lib/ui-fidelity"; }

# claims <text> <facts json> — the claims the register does not cover, one per line
claims() {
  (cd "$LIB" && node --input-type=module -e "
    import { unknownClaims } from './aid-ui-facts.mjs';
    console.log(unknownClaims(process.argv[1], JSON.parse(process.argv[2])).join('\n'));" "$1" "$2")
}
TEXT='Pomohli jsme přes 200 klientům. Úspora 40 %. 15 let praxe. Pište na info@neexistuje.cz. Máme 200 klienty.'
BASE='[{"claim":"telefon","value":"+420 777 123 456"},{"claim":"cena","value":"65 Kč"}]'

@test "invented count, percentage, years, e-mail and another case of the count word are all named" {
  run claims "$TEXT" "$BASE"
  for c in "200 klientům" "40 %" "15 let" "info@neexistuje.cz" "200 klienty"; do grep -qxF "$c" <<<"$output" || { echo "missing $c: $output"; return 1; }; done
}

@test "registered facts cover them, in a list register and in a mapping register" {
  run claims "$TEXT" '[{"claim":"klienti","value":"200"},{"claim":"úspora","value":"40 %"},{"claim":"praxe","value":"15 let"},{"claim":"e-mail","value":"info@neexistuje.cz"}]'
  [ -z "$output" ] || { echo "$output"; return 1; }
  run claims "200 klientům" '{"klienti":{"value":200,"source":"PM"}}'
  [ -z "$output" ]
}

@test "the same digits in another number or under another meaning do not cover a count" {
  run claims "200 klientům" '{"zalozeno":{"value":"2008"}}'; [ "$output" = "200 klientům" ]
  run claims "200 klientům" '{"tymy":{"value":"200"}}';     [ "$output" = "200 klientům" ]
  run claims "200 klientům" '{"zakaznici":{"value":"200"}}'; [ -z "$output" ]   # same meaning group
  run claims "3 projekty" '{"klienti":{"value":"3"}}';     [ "$output" = "3 projekty" ]
  run claims "2 klienti" '{"klienti":{"value":"2,5"}}';    [ "$output" = "2 klienti" ]   # a decimal never covers its integer part
  run claims "200členná klientela" '{}';                   [ "$output" = "200členná" ]
}

@test "phones, prices and times keep the P103 behaviour (each leaf on its own); a year in a date is not a count" {
  F='[{"claim":"telefon","value":"+420 777 123 456"},{"claim":"cena","value":"65 Kč"},{"claim":"eur","value":"12,50 €"},{"claim":"czk","value":"1 200 CZK"},{"claim":"otevřeno","value":"7:00 až 18:00"}]'
  run claims "Volejte +420 777 123 456, bochník 65 Kč, dort 12,50 €, kurz 1 200 CZK, otevřeno od 7:00, od roku 2015 jsme tu." "$F"
  [ -z "$output" ] || { echo "$output"; return 1; }
  run claims "Bochník 999 Kč, zavíráme v 19:30" "$F"
  [ "$output" = "$(printf '999 Kč\n19:30')" ] || { echo "$output"; return 1; }
  # a price is never assembled from two fields of one entry
  run claims "65 Kč" '{"cena":{"amount":"65","unit":"Kč"}}'; [ "$output" = "65 Kč" ]
}

@test "decimal percentages, Slovak companies, compounds and hyphens; 'let' only as years" {
  run claims "Úspora 2,5 %." '{"a":{"value":"2 %"}}';   [ "$output" = "2,5 %" ]
  run claims "Úspora 2,5 %." '{"a":{"value":"2,5 %"}}'; [ -z "$output" ]
  run claims "Pracuje pro nás 20 spoločností." '{}';     [ "$output" = "20 spoločností" ]
  run claims "15leté zkušenosti a 200-klientská základna" '{}'
  [ "$output" = "$(printf '15leté\n200-klientská')" ] || { echo "$output"; return 1; }
  run claims "3 letní pobyty, 2 letadla, 15 letenek" '{}'; [ -z "$output" ] || { echo "$output"; return 1; }
  run claims "15 let praxe" '{"letaky":{"value":15}}';   [ "$output" = "15 let" ]
}

@test "an e-mail passes only when it equals a register value" {
  run claims "Pište na info@fake.cz" '{"info@fake.cz":{"value":"x"}}';           [ "$output" = "info@fake.cz" ]
  run claims "Pište na info@fake.cz" '{"e":{"value":"info@fake.cz.invalid"}}';  [ "$output" = "info@fake.cz" ]
  run claims "Pište na info@fake.cz" '{"e":{"value":"info@fake.cz"}}';          [ -z "$output" ]
}
