#!/bin/zsh
# The worker against the in-process reference: one hair item made over GPP on the signed bundle and one through
# hairdeck-inproc, from the same picture, box, body and seed, must be the same GLB, byte for byte.
#
#   GOLDEN_IMAGE=<cut-out png> GOLDEN_BODY=<vrm> GOLDEN_BOX='{"x":…,"y":…,"width":…,"height":…}' scripts/golden.sh <out-dir>
#
# Environment: GOLDEN_MODELS_ROOT (default /Volumes/DEV_VOL1/Models; the weights must be there, or HF_TOKEN set while
# the weights repo is private), GOLDEN_SEED (default 0), GAEA_SPEC_ROOT (default ../gaea-mes-media-server, for
# tools/gpp-run.py), GAEA_PLUGIN_KIT_PATH. Run scripts/build-plugin.sh first.
#
# gpp-run.py gives a worker an 8 GB ceiling by default, and HairDeck with BiRefNet is charged more, so this asks it
# for 32 GB (GPP_RUN_BUDGET_BYTES).
set -euo pipefail
ROOT=${0:A:h:h}
cd $ROOT
OUT=${1:?usage: scripts/golden.sh <out-dir>}
: ${GOLDEN_IMAGE:?} ${GOLDEN_BODY:?} ${GOLDEN_BOX:?}
SPEC=${GAEA_SPEC_ROOT:-$ROOT/../gaea-mes-media-server}
MODELS=${GOLDEN_MODELS_ROOT:-/Volumes/DEV_VOL1/Models}
SEED=${GOLDEN_SEED:-0}
mkdir -p $OUT/work
[[ -e $OUT/work/models ]] || ln -s $MODELS $OUT/work/models
PARAMS="{\"subject_box\":$GOLDEN_BOX,\"part\":\"hair\",\"physics\":true,\"texture\":\"atlas\",\"background\":\"alpha\",\"quality\":\"standard\"}"
GPP_RUN_BUDGET_BYTES=32000000000 GPP_RUN_INPUTS="{\"image\": \"${GOLDEN_IMAGE:A}\", \"body\": \"${GOLDEN_BODY:A}\"}" \
  python3 $SPEC/tools/gpp-run.py dist/hairdeck.gaeaplugin $OUT/work hairdeck fp32 mesh.generate_part $PARAMS '{}' $SEED > $OUT/worker.json
# the box in pixels as GaeaPluginKit makes it: left and top rounded down, right and bottom up
BOX=$(python3 - $GOLDEN_IMAGE $GOLDEN_BOX <<'PY'
import json, math, struct, sys
b = open(sys.argv[1], 'rb').read(); w, h = struct.unpack('>II', b[16:24]); s = json.loads(sys.argv[2])
print(f"{math.floor(s['x']*w)},{math.floor(s['y']*h)},{min(w, math.ceil((s['x']+s['width'])*w))},{min(h, math.ceil((s['y']+s['height'])*h))}")
PY
)
xcrun swift run -c release hairdeck-inproc --image $GOLDEN_IMAGE --box $BOX --body $GOLDEN_BODY --seed $SEED --models-root $MODELS --out $OUT/inproc.glb | tail -1 > $OUT/inproc.json
A=$(shasum -a 256 $OUT/work/out/mesh.glb | cut -d' ' -f1); B=$(shasum -a 256 $OUT/inproc.glb | cut -d' ' -f1)
print "worker  $A\ninproc  $B"
[[ $A == $B ]] && print "golden: the worker's hair item is the in-process one, byte for byte" || { print -u2 "golden: the files differ"; exit 1 }
