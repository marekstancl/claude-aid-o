#!/usr/bin/env bats
# aid-tier: t0
# P102 Step 5 — aid-ui-ico.py packs favicon.ico and checks the icon package of /aid-ui step 1i.

setup() {
  ICO="$BATS_TEST_DIRNAME/../../aid-ui-ico.py"
  FX="$BATS_TEST_DIRNAME/../fixtures/aid-ui/icons"
  T="$BATS_TEST_TMPDIR"
}

# hdr <side> <file> — a PNG signature + IHDR only; --verify reads nothing further.
hdr() {
  python3 -c 'import struct,sys; n=int(sys.argv[1]); sys.stdout.buffer.write(b"\x89PNG\r\n\x1a\n"+struct.pack(">I",13)+b"IHDR"+struct.pack(">II",n,n))' "$1" > "$2"
}

complete_set() {
  cp "$FX"/favicon-16.png "$FX"/favicon-32.png "$FX"/favicon-48.png "$T/"
  hdr 180 "$T/apple-touch-icon.png"; hdr 192 "$T/icon-192.png"
  hdr 512 "$T/icon-512.png"; hdr 512 "$T/icon-maskable-512.png"
  echo '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 32 32"/>' > "$T/favicon.svg"
  python3 "$ICO" "$T/favicon.ico" "$T"/favicon-16.png "$T"/favicon-32.png "$T"/favicon-48.png
}

@test "three PNG fixtures -> an ICO with 3 entries of 16/32/48" {
  run python3 "$ICO" "$T/f.ico" "$FX/favicon-16.png" "$FX/favicon-32.png" "$FX/favicon-48.png"
  [ "$status" -eq 0 ]
  run python3 -c 'import struct,sys; d=open(sys.argv[1],"rb").read(); r,t,n=struct.unpack("<HHH",d[:6]); print(r,t,n,*[d[6+16*i] for i in range(n)])' "$T/f.ico"
  [ "$output" = "0 1 3 16 32 48" ]
}

@test "a non-PNG is refused with exit 1" {
  echo 'not a png' > "$T/x.png"
  run python3 "$ICO" "$T/f.ico" "$T/x.png"
  [ "$status" -eq 1 ]
  [[ "$output" == *"not a PNG"* ]]
  [ ! -e "$T/f.ico" ]
}

@test "a PNG above 256 px is refused with exit 1" {
  hdr 512 "$T/big.png"
  run python3 "$ICO" "$T/f.ico" "$T/big.png"
  [ "$status" -eq 1 ]
}

@test "--verify on a complete set -> exit 0" {
  complete_set
  run python3 "$ICO" --verify "$T"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [[ "$output" != *WRONG* ]]
}

@test "--verify with the wrong-sized file -> exit 1 naming it" {
  complete_set
  cp "$FX/wrong-size-100.png" "$T/apple-touch-icon.png"
  run python3 "$ICO" --verify "$T"
  [ "$status" -eq 1 ]
  [[ "$output" == *"WRONG   apple-touch-icon.png expected 180x180, got 100x100"* ]]
}

@test "--verify names a missing file" {
  complete_set
  rm "$T/icon-maskable-512.png"
  run python3 "$ICO" --verify "$T"
  [ "$status" -eq 1 ]
  [[ "$output" == *"icon-maskable-512.png expected 512x512, got missing"* ]]
}
