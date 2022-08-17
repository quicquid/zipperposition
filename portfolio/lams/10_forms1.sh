#!/bin/bash

# solves 4 under 15s

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"


ulimit -t $2

$DIR/../zipperposition ${1:+"$1"} \
  -i tptp\
  -o tptp\
  --timeout "$2" \
  --mode=ho-pragmatic --kbo-weight-fun-from-precedence=true\
  --prec-gen-fun=invfreqhack\
  -q "6|prefer-formulas|pnrefined(1,1,1,2,2,2,0.5)"\
  -q "4|prefer-goals|pnrefined(2,1,1,1,2,2,2)"\
  -q "2|const|orient-lmax(2,1,2,1,1)" -q "4|prefer-fo|conjecture-relative-e(0.1,0.5,100,100,100,100,1.5,1.5,1.5)"\
  -q "1|prefer-processed|fifo"\
  --select=bb+e-selection\
  --ho-neg-ext-simpl=true --arg-cong-simpl=true\
  --ord=derived_ho_rpo -i tptp --tptp-def-as-rewrite --rewrite-before-cnf=true --sine=40 --sine-take-only-defs=true --sine-depth-min=1\
  --sine-depth-max=5 --sine-tolerance=10 --trigger-bool-inst=1\
  --lazy-cnf=true --lazy-cnf-kind=simp --presaturate=true --lazy-cnf-renaming-threshold=6\
  --boolean-reasoning=simpl-only --bool-select="sel2(consequent_ctx)" --superposition-with-formulas=true\
  --lazy-cnf-clausify-implications=false --lazy-cnf-inf-quant=true\
  --ho-unif-max-depth=1 --ho-solid-decider=true "${@:4}"
