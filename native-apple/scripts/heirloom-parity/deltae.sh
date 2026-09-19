#!/bin/sh
# E3 bronze Delta-E parity harness (on-device-AI PLAN §13 fidelity harness,
# bronze slice; WP-E-EDIT bronze rule: exact match where the math is Apple's
# own pipeline).
# Usage: deltae.sh [--help] <refs-dir> [out-dir]
#
# <refs-dir> holds per-case triples (owner-captured, see reports/WP-E-REPORT.md):
#   <case>.recipe.json  EditRecipe JSON (raw {"adjust": {...}, ...} object)
#   <case>.source.png   synthetic input the recipe renders from
#   <case>.ref.png      Apple Photos export of the same edit (PNG, source size)
# Each recipe renders through the PhotosCore EditRenderer, compares against
# the Photos export with CILabDeltaE, and the script prints per-case
# median/p90 dE plus a text summary (bronze bar: per-case median dE < 3).
# Renders land in [out-dir] (default <refs-dir>/heirloom-renders).
#
# Missing or empty refs dir: prints the owner-capture-pending note, exit 0.
# Any compared case failing the bar (or erroring) exits 1. At most 64 cases
# run per invocation (sorted); the rest are reported and skipped.
set -eu

usage() {
  echo "usage: $0 [--help] <refs-dir> [out-dir]" >&2
}

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
  sed -n '2,17p' "$0" | sed 's/^# //; s/^#//'
  exit 0
fi

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
  usage
  exit 64
fi
refsdir=$1
outdir=${2:-"$refsdir/heirloom-renders"}

if [ "$(uname -s)" != "Darwin" ]; then
  echo "deltae.sh: macOS only (Core Image renderer + CILabDeltaE)" >&2
  exit 64
fi
if ! command -v swiftc >/dev/null 2>&1; then
  echo "deltae.sh: swiftc not found on PATH" >&2
  exit 64
fi

pending() {
  echo "deltae: no references — owner capture pending ($1)"
  echo "deltae: capture 3 synthetic images x fixed D1-D3 strengths in Apple Photos,"
  echo "deltae: export each as PNG plus its recipe JSON into a refs dir, then re-run."
  echo "deltae: see reports/WP-E-REPORT.md (E3 bronze section) for the recipe."
  exit 0
}

[ -d "$refsdir" ] || pending "refs dir '$refsdir' absent"
cases=$(find "$refsdir" -maxdepth 1 -name '*.recipe.json' | sort)
[ -n "$cases" ] || pending "no *.recipe.json in '$refsdir'"

# Locate the PhotosCore checkout relative to this script.
root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
core="$root/PhotosCore"
[ -d "$core/Sources/Editing" ] || {
  echo "deltae.sh: PhotosCore not found at $core" >&2
  exit 64
}

tmp=$(mktemp -d "${TMPDIR:-/tmp}/deltae.XXXXXX")
trap 'rm -rf "$tmp"' EXIT INT TERM
mkdir -p "$outdir"

# The comparison helper compiles against the real renderer sources
# (Editing + its intra-package deps; system frameworks only). It takes
# <recipe.json> <source.png> <ref.png> <out-render.png> and prints
# "median=.. p90=.. max=.. zerofrac=.. pixels=..".
# (The file must be named main.swift: multi-file swiftc is library mode.)
cat > "$tmp/main.swift" <<'SWIFTEOF'
import CoreGraphics
import CoreImage
import Foundation
import ImageIO

func fail(_ msg: String) -> Never {
  fputs("deltae-helper: error: \(msg)\n", stderr)
  exit(1)
}

let args = CommandLine.arguments
guard args.count == 5 else {
  fputs("usage: deltae-helper <recipe.json> <source.png> <ref.png> <out-render.png>\n", stderr)
  exit(64)
}
let recipeURL = URL(fileURLWithPath: args[1])
let sourceURL = URL(fileURLWithPath: args[2])
let refURL = URL(fileURLWithPath: args[3])
let outURL = URL(fileURLWithPath: args[4])

let recipeData: Data
do { recipeData = try Data(contentsOf: recipeURL) } catch {
  fail("cannot read recipe \(args[1]): \(error)")
}
let recipe: EditRecipe
do { recipe = try JSONDecoder().decode(EditRecipe.self, from: recipeData) } catch {
  fail("cannot decode EditRecipe from \(args[1]): \(error)")
}
guard let srcImg = CIImage(contentsOf: sourceURL) else { fail("cannot load image \(args[2])") }
guard let refImg = CIImage(contentsOf: refURL) else { fail("cannot load image \(args[3])") }

let renderer = EditRenderer()
let rendered = renderer.render(source: srcImg, recipe: recipe)

let ctx = CIContext(options: [.cacheIntermediates: false])
let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
do {
  try ctx.writePNGRepresentation(of: rendered, to: outURL, format: .RGBA8, colorSpace: srgb)
} catch {
  fail("cannot write render \(args[4]): \(error)")
}

let rw = Int(rendered.extent.width.rounded()), rh = Int(rendered.extent.height.rounded())
let fw = Int(refImg.extent.width.rounded()), fh = Int(refImg.extent.height.rounded())
guard rw == fw && rh == fh && rw > 0 && rh > 0 else {
  fail(
    "extent mismatch: render \(rw)x\(rh) vs ref \(fw)x\(fh) (owner must export at source size)")
}

guard let deFilter = CIFilter(name: "CILabDeltaE") else { fail("CILabDeltaE unavailable") }
deFilter.setValue(rendered, forKey: kCIInputImageKey)
deFilter.setValue(refImg, forKey: "inputImage2")
guard let deImg = deFilter.outputImage else { fail("CILabDeltaE produced no output") }

let n = rw * rh
var buf = [Float](repeating: 0, count: n)
ctx.render(
  deImg, toBitmap: &buf, rowBytes: rw * 4,
  bounds: CGRect(x: 0, y: 0, width: rw, height: rh), format: .Rf,
  colorSpace: CGColorSpaceCreateDeviceRGB())

// 0.001-wide histogram over 0...100: O(n) median/p90, no giant sort.
// Also tracks exact max/zero-count so a true self-pair reports 0 exactly
// instead of a bin center.
let bins = 100_001
var hist = [Int](repeating: 0, count: bins)
var nzero = 0
var vmax = 0.0
for v in buf {
  let d = Double(v)
  if d == 0.0 { nzero += 1 }
  if d > vmax { vmax = d }
  let c = min(100.0, max(0.0, d))
  hist[min(bins - 1, Int(c * 1000.0))] += 1
}
func quantile(_ q: Double) -> Double {
  let target = Int((Double(n) * q).rounded(.up)) - 1
  var acc = 0
  for i in 0..<bins {
    acc += hist[i]
    if acc > target { return (Double(i) + 0.5) / 1000.0 }
  }
  return 100.0
}
// All-zero fast path: a true self-pair prints 0 exactly, not a bin center.
let median = vmax == 0.0 ? 0.0 : quantile(0.5)
let p90 = vmax == 0.0 ? 0.0 : quantile(0.9)
print(
  String(
    format: "median=%.4f p90=%.4f max=%.4f zerofrac=%.4f pixels=%d", median, p90, vmax,
    Double(nzero) / Double(n), n))
SWIFTEOF

mkdir -p "$tmp/src"
cp "$core"/Sources/Editing/*.swift "$core"/Sources/CoreModel/*.swift "$core"/Sources/Rules/*.swift \
  "$tmp/src/"
# Single-module compile: drop the intra-package imports (Editing <-> CoreModel/Rules).
sed -i '' '/^import CoreModel$/d; /^import Rules$/d; /^import Editing$/d' "$tmp"/src/*.swift

echo "deltae: building helper against $core ..." >&2
if ! swiftc -O -o "$tmp/deltae-helper" "$tmp/main.swift" "$tmp"/src/*.swift 2>"$tmp/build.log"; then
  echo "deltae.sh: helper build failed:" >&2
  tail -20 "$tmp/build.log" >&2
  exit 1
fi

bar=3
compared=0
passed=0
failed=0
skipped=0
maxcases=64
total=$(printf '%s\n' "$cases" | grep -c .)
if [ "$total" -gt "$maxcases" ]; then
  echo "deltae: warning: $total cases found, running first $maxcases (sorted)" >&2
fi

for r in $cases; do
  if [ "$compared" -ge "$maxcases" ]; then
    echo "skip $(basename "$r" .recipe.json) (over 64-case cap)" >&2
    skipped=$((skipped + 1))
    continue
  fi
  base=$(basename "$r" .recipe.json)
  src="$refsdir/$base.source.png"
  ref="$refsdir/$base.ref.png"
  if [ ! -f "$src" ] || [ ! -f "$ref" ]; then
    echo "skip $base (missing side: need $base.source.png + $base.ref.png)" >&2
    skipped=$((skipped + 1))
    continue
  fi
  if ! stats=$("$tmp/deltae-helper" "$r" "$src" "$ref" "$outdir/$base.heirloom.png" 2>"$tmp/case.log"); then
    echo "case=$base ERROR $(cat "$tmp/case.log")" >&2
    failed=$((failed + 1))
    compared=$((compared + 1))
    continue
  fi
  median=$(printf '%s' "$stats" | sed -n 's/.*median=\([0-9.]*\).*/\1/p')
  p90=$(printf '%s' "$stats" | sed -n 's/.*p90=\([0-9.]*\).*/\1/p')
  verdict=$(awk -v m="$median" -v b="$bar" 'BEGIN { print (m < b) ? "PASS" : "FAIL" }')
  echo "case=$base $stats verdict=$verdict"
  compared=$((compared + 1))
  if [ "$verdict" = "PASS" ]; then passed=$((passed + 1)); else failed=$((failed + 1)); fi
done

echo "deltae: compared=$compared passed=$passed failed=$failed skipped=$skipped bar=median_dE<$bar"
if [ "$compared" -eq 0 ]; then
  echo "deltae: nothing comparable (all cases skipped)" >&2
  exit 1
fi
[ "$failed" -eq 0 ]
