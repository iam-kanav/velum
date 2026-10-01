#!/bin/bash
# Render the chosen colourway into every existing icon file, keeping each file's size.
set -e
CW=${1:-violet}
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
SRC="$ROOT/branding/logo/colourways"
R="${SVG_RENDER_PY:?set SVG_RENDER_PY to a render_png.py}"
CACHE=$(mktemp -d)
render() { # variant size -> path
  local out="$CACHE/$1-$2.png"
  [ -f "$out" ] || python3 "$R" "$SRC/velum-$CW-$1.svg" -o "$out" --size "$2" --backend chrome >/dev/null 2>&1
  echo "$out"
}
opaque() { # strip alpha via jpeg round-trip (iOS icons must be opaque)
  sips -s format jpeg -s formatOptions best "$1" --out "$CACHE/o.jpg" >/dev/null
  sips -s format png "$CACHE/o.jpg" --out "$2" >/dev/null
}
place() { # variant file [opaque]
  local f="$1" v="$2" w
  w=$(sips -g pixelWidth "$f" | awk '/pixelWidth/{print $2}')
  local p; p=$(render "$v" "$w")
  if [ "$3" = opaque ]; then opaque "$p" "$f"; else cp "$p" "$f"; fi
  echo "$f  ($v ${w}px${3:+, $3})"
}
cd "$ROOT"
for d in android/app/src/main/res assets/icons/android/res; do
  for f in $d/mipmap-*/ic_launcher.png $d/drawable-*/ic_launcher.png; do [ -f "$f" ] && place "$f" circle; done
  for f in $d/mipmap-*/ic_launcher_foreground.png $d/drawable-*/ic_launcher_foreground.png; do [ -f "$f" ] && place "$f" foreground; done
  for f in $d/mipmap-*/ic_launcher_background.png; do place "$f" background; done
  for f in $d/mipmap-*/ic_launcher_monochrome.png; do place "$f" monochrome; done
done
place assets/icons/android/play_store_512.png square
for f in ios/Runner/Assets.xcassets/AppIcon.appiconset/*.png assets/icons/ios/*.png; do place "$f" square opaque; done
for d in web/icons assets/icons/web; do
  for f in $d/*.png; do
    case "$(basename "$f")" in
      *askable*) place "$f" maskable ;;
      apple-touch-icon.png) place "$f" square opaque ;;
      *) place "$f" tile ;;
    esac
  done
done
place web/favicon.png tile
for ico in web/favicon.ico web/icons/favicon.ico assets/icons/web/favicon.ico; do
  python3 "$R" "$SRC/velum-$CW-tile.svg" --ico "$ico" --ico-sizes 16 32 --backend chrome >/dev/null 2>&1 && echo "$ico  (tile ico 16+32)"
done
python3 "$R" "$SRC/velum-$CW-square.svg" -o "$ROOT/branding/logo/velum-icon-512.png" --size 512 --backend chrome >/dev/null 2>&1
rm -rf "$CACHE"
