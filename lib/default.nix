# gen-prelude — pure, nixpkgs-lib-free utilities for the gen ecosystem.
#
# `builtins` re-exports plus the handful of pure utilities the gen substrate uses,
# vendored behavior-identically from nixpkgs lib. The dependency that lets the pure
# gen libraries drop `nixpkgs.lib`.
#
# NOT a type system, NOT a module-system shim (the `lib.types`/`mkOption`/`evalModules`
# tier is a separate Korora-class concern, out of scope here).
#
# Zero dependencies, so this is a bare value (not a function): `import ./lib`.
let
  inherit (builtins)
    all
    any
    attrNames
    attrValues
    concatLists
    concatMap
    concatStringsSep
    elem
    elemAt
    filter
    foldl'
    functionArgs
    genList
    groupBy
    head
    isAttrs
    isFunction
    isList
    isString
    length
    listToAttrs
    map
    mapAttrs
    match
    partition
    replaceStrings
    seq
    sort
    split
    stringLength
    substring
    tail
    unsafeDiscardStringContext
    ;

  nameValuePair = name: value: { inherit name value; };

  # ── string containment (backtracking-free) ──
  # nixpkgs `lib.hasInfix infix s` is `match ".*${escapeRegex infix}.*" s != null`; the
  # leading/trailing `.*` make std::regex recurse to depth ∝ `stringLength s`, overflowing
  # the C stack when scanning whole source files (readFile'd libraries in purity checks).
  # Split on the escaped literal instead: `split` carries no `.*` anchor and scans linearly.
  # Result is the same boolean as nixpkgs (fidelity-tested), so it is a drop-in.
  #
  # The set below is nixpkgs' `stringToCharacters "\\[{()^$?*+|."` — the same twelve
  # characters, same order — and `escape` is the same `replaceStrings` fold, so the escaped
  # output is byte-identical to `lib.escapeRegex` on every input, not merely equivalent.
  #
  # The set has to be the engine's metacharacter set EXACTLY, because escaping is unsound in
  # both directions. A member left out stops being quoted and the needle silently becomes a
  # pattern. A member added in emits `\c` for a `c` the grammar defines no escape for, which
  # is not the literal `c` and need not be a valid regex at all: `]` is the case in point —
  # it is already literal outside a bracket expression, and `\]` is rejected by the engine,
  # so a set containing `]` turns every `]`-bearing needle into an abort where nixpkgs
  # returns a boolean. `builtins.tryEval` does not contain that abort. `]` is therefore not a
  # member and must not become one; both directions are asserted per member in
  # `prelude-fidelity`.
  escapeRegex =
    let
      metachars = [
        "\\"
        "["
        "{"
        "("
        ")"
        "^"
        "$"
        "?"
        "*"
        "+"
        "|"
        "."
      ];
    in
    replaceStrings metachars (map (c: "\\" + c) metachars);

  hasInfix = infix: content: infix == "" || length (split (escapeRegex infix) content) > 1;

  # ── first-match search (findFirstIndex vendored from nixpkgs lib/lists.nix) ──
  # findFirstIndex: stack-safe first-matching-index scan (nixpkgs' countdown-foldl' trick —
  # reuses one stack frame, no naive recursion, no early cutoff). Internal: the shared scan
  # under `findFirst` and `indexOf`. Returns the 0-based index of the first `pred`-satisfying
  # element, else `default`.
  findFirstIndex =
    pred: default: list:
    let
      resultIndex = foldl' (
        index: el: if index < 0 then (if pred el then -index - 1 else index - 1) else index
      ) (-1) list;
    in
    if resultIndex < 0 then default else resultIndex;

  # ── bounded iteration — the loop encoding for state that a scan cannot carry ──
  # `iterateBounded strict step init bound` applies `step` once per element of `bound` and
  # returns the state after the last application. The ELEMENTS OF `bound` ARE IGNORED: only
  # its length is read, as the bound on how many steps can be productive, so a caller passes
  # a list it already holds and the driver allocates nothing.
  #
  # THEORY: a loop written as a self-applying lambda costs one evaluator frame per iteration —
  # Nix does not reuse the frame of a call in tail position — so its descent depth IS the
  # iteration count, and past `max-call-depth` it aborts uncatchably (`tryEval` does not
  # contain a stack overflow). `foldl'` is a C-level loop: each application returns before the
  # next begins, so the frame cost is constant in the iteration count. This is the same
  # stack-safety argument `findFirstIndex` above makes for a scan, extended to a loop that
  # carries state — which is why the bound is a list rather than a count: it is the scan's
  # driver, reused.
  #
  # Iterating a FIXED number of times where a recursion would run to its own fixed point is
  # sound only if the caller owes two properties, and they are the contract:
  #   (1) at most `length bound` steps do work, and
  #   (2) `step` is the identity once no work remains,
  # so the surplus steps idle and the result is the fixed point the recursion would reach.
  #
  # `strict` names the LOOP-CARRIED fields and is forced on every intermediate state.
  # `foldl'` forces its accumulator to WHNF — for a record, the record and not its fields — so
  # a field left unforced accumulates a thunk chain as long as the loop, and forcing it at the
  # end costs C stack: a second, distinct stack overflow that no `max-call-depth` setting
  # bounds and that `tryEval` does not contain either. The forcing is part of the encoding,
  # not an optimisation; a caller with nothing to force passes `_: null`.
  iterateBounded =
    strict: step: init: bound:
    foldl' (
      st: _:
      let
        next = step st;
      in
      seq (strict next) next
    ) init bound;

  # ── unique — order-preserving dedup under structural `==`, as a guarded two-path ──
  # The incumbent `foldl' (acc: x: if elem x acc then acc else acc ++ [ x ]) [ ]` is QUADRATIC IN
  # THE DISTINCT COUNT K, not in the list length N, and that distinction is the whole design:
  # `acc ++ [ x ]` copies the entire accumulator on each of the K first-sightings, Σ(k+1) for
  # k = 0..K−1 = K(K+1)/2, giving the measured closed form `K(K+1)/2 + K + N + 2` list elements
  # (all-distinct: 502,502 / 2,005,002 / 8,010,002 at N = K = 1,000 / 2,000 / 4,000, exponent
  # 1.9982). THE APPEND IS THE COST. The `elem` scan is Θ(N·K) in comparisons but allocates
  # nothing, so it is invisible to every allocation counter — which is why an attrset-keyed
  # membership test alone fixes nothing here.
  #
  # The string path builds a key→first-index table in one pass instead. `listToAttrs` keeps the
  # FIRST binding for a repeated name, so the table holds exactly the K first-occurrence indices;
  # sorting those indices ascending IS first-occurrence order; and `elemAt` hands back the
  # ORIGINAL element, so nothing about the value is reconstructed from its key. Closed form
  # `2N + 3K + 3` — linear in both variables (20,003 at N = K = 4,000, exponent 0.99978). At the
  # shape real callers present — an endpoint union over an edge list, where every edge contributes
  # two endpoints and the distinct endpoints are nodes, so N ≈ 2K — this measures 23.3× and 91.9×
  # fewer elements at N = 640 and 2,560, and the improvement DOUBLES with every doubling of the
  # input.
  #
  # Keying on `unsafeDiscardStringContext` is exactness, not a safety hatch. A context-carrying
  # string is a legal element (`==` ignores context, so `s == unsafeDiscardStringContext s`) and an
  # ILLEGAL attribute name (`listToAttrs` rejects it: "not allowed to refer to a store path"), so
  # keying on the element as-is would be a latent eval-time abort. Discarding context in the KEY
  # reproduces `==`'s partition precisely; returning the original element preserves the caller's
  # context.
  #
  # THE TRADE IS REAL AND IS STATED: at K ≪ N the table costs Ω(N) pairs where the fold allocated
  # only Θ(K²), so allocation converges to exactly 2.00× worse (1.43× / 1.85× / 1.97× / 2.00× at
  # K = 26, N = 800 / 4,000 / 20,000 / 400,000) and time drifts as `log N / K` — `listToAttrs`
  # orders N entries in Θ(N log N) against the fold's Θ(N·K) scan — measured +29.5% at N = 400,000,
  # K = 8. Whenever K² ≪ N the fold allocates less, and no attrset-keyed construction escapes
  # that, because any of them must hand `listToAttrs` N pairs.
  #
  # THE INCUMBENT FOLD IS RETAINED DELIBERATELY, and is not an oversight left behind by the
  # rewrite. It is the TOTAL path. There is no total, injective, pure value→string key in Nix —
  # `toJSON` is not one, since it aborts on functions and forces deeply, which would change
  # strictness — so a non-string list has no index table to build at all, and `unique` must stay
  # total on ints, lists, attrsets and functions, all of which it accepts today and real callers
  # pass. The guard is therefore per-LIST rather than per-element: a mixed list routes whole to the
  # fold, which is what reproduces `unique [ "a" 1 "a" 1 ]` ⇒ `[ "a", 1 ]` exactly.
  #
  # The `length xs < 2` guard is STRICTNESS PARITY, not an optimisation, and it is why the two-path
  # forces no more than the fold. Without it, `all isString` would force the sole element of a
  # singleton where the fold does not: `elem x [ ]` answers false without comparing, so
  # `unique [ (throw "BOOM") ]` has length 1 under the fold and would ABORT under a bare guard. At
  # N ≥ 2 the fold forces every element to WHNF anyway — each is the `x` of `elem x acc`, with
  # `acc` non-empty from the second step — and `all isString` forces to WHNF and short-circuits, so
  # it forces no more and sometimes less. A list of length ≤ 1 cannot contain a duplicate, so
  # returning it unevaluated is not a fast path, it is the definition.
  unique =
    xs:
    if length xs < 2 then
      xs
    else if all isString xs then
      let
        firstIdx = listToAttrs (
          genList (i: {
            name = unsafeDiscardStringContext (elemAt xs i);
            value = i;
          }) (length xs)
        );
      in
      map (i: elemAt xs i) (sort (a: b: a < b) (attrValues firstIdx))
    else
      foldl' (acc: x: if elem x acc then acc else acc ++ [ x ]) [ ] xs;

  # ── dedupByKey (vendored from den-hoag lib/dedup-by-key.nix; itself the port of v1 scope-walk
  # dedupByKey @ pin 11866c16) — no nixpkgs equivalent, so not in the fidelity suite. ──
  # First-occurrence-wins dedup by `getKey`, order-preserving. A `null` key is ALWAYS kept and
  # NEVER entered into `seen` (the SAFE direction: a keyless element cannot be proven a
  # cross-scope duplicate, so a false-keep of equal content equal-merges harmlessly, whereas a
  # false-collapse of distinct content is silent content-loss). null-key nodes neither evict a
  # later duplicate nor are evicted.
  #
  # THEORY: the recursion this replaces was `[ x ] ++ go … rest` — an append per surviving element
  # and a `builtins.tail` copy per step, so it cost Θ(N²) IN THE LIST LENGTH whatever the distinct
  # count: measured `N² + 2N + 2` list elements (1,002,002 / 4,004,002 / 16,008,002 at N = 1,000 /
  # 2,000 / 4,000, exponent 1.9993). The O(1) attrset membership test bought nothing, because the
  # append was the cost, not the lookup. Worse, `go` is not in tail position — the recursive call
  # must be forced to build the `++` — so descent depth WAS the input length and the function
  # aborted uncatchably past `max-call-depth`: measured, 5,000 and 9,000 evaluate, 10,000 and above
  # give `error: stack overflow; max-call-depth exceeded`, a ceiling inside the range of real
  # inputs. `tryEval` does not contain it.
  #
  # The shape below is the same key→first-index table `unique` uses, and it is linear and
  # frame-flat for the same reasons: `listToAttrs` keeps the FIRST binding for a repeated name, so
  # the table's values ARE the first-occurrence indices, and sorting indices ascending recovers
  # input order. Every step is a primop, so there is no Nix-level recursion to overflow — measured
  # `5N + 3` elements (20,003 at N = 4,000, exponent 0.99978) and it evaluates at N = 200,000,
  # where it reads 1,000,003.
  #
  # The `null` key is the one part that does not transcribe mechanically, and it is where a silent
  # content-loss would enter. Unkeyed elements are filtered OUT of the table (never entered into
  # the index, so they can never evict a later duplicate) and their indices are added back to the
  # kept set unconditionally (so they can never be evicted). Both directions are load-bearing.
  dedupByKey =
    getKey: list:
    let
      pairs = genList (i: {
        name = getKey (elemAt list i);
        value = i;
      }) (length list);
      firstIdx = listToAttrs (filter (p: p.name != null) pairs);
      unkeyed = concatMap (p: if p.name == null then [ p.value ] else [ ]) pairs;
    in
    map (i: elemAt list i) (sort (a: b: a < b) (attrValues firstIdx ++ unkeyed));

  # ── path writer / reader ──
  #
  # The refusal path is the whole reason these live HERE rather than in a composition library.
  # Measured against every source they replace: the three gen hand-rolled twins (gen-view
  # `placement.nix`, gen-merge `modules.nix`, gen-class `apply.nix`) refuse by falling into a raw
  # interpreter error — `expected a list but found a string`, `attribute 'x' missing` — which
  # `tryEval` CANNOT catch, because only `throw`/`assert` are catchable and attribute-selection
  # failure is not. nixpkgs is better and still uncatchable: `getAttrFromPath` names the whole
  # dotted path but does it with `abort`. Both refusals below are `last`/`init`'s convention —
  # NAMED and CATCHABLE — which is strictly more ADR-0025 §1 compliant than any of them.
  #
  # Naming note: current nixpkgs renamed `getAttrByPath` to `getAttrFromPath`. The older name is
  # kept here for symmetry with `setAttrByPath` and with every gen-ecosystem hand-roll; a fidelity
  # diff comparing names rather than behaviour will read that divergence and it is deliberate.

  # setAttrByPath path value — the nested attrset holding `value` at `path`. `[ ]` returns `value`
  # unchanged (the convention nixpkgs and all four hand-rolls already share). Built outward from
  # the innermost segment: the index list descends, so each step wraps the accumulator in one more
  # level. Fidelity is asserted on the HAPPY PATH only — the refusal deliberately diverges.
  setAttrByPath =
    path: value:
    if !isList path || !all isString path then
      throw "gen-prelude.setAttrByPath: path must be a list of strings"
    else
      foldl' (acc: i: { ${elemAt path i} = acc; }) value (genList (i: length path - 1 - i) (length path));

  # getAttrByPath path attrs — the value at `path`, or a named throw. `[ ]` returns `attrs`
  # unchanged, symmetric with the writer and with nixpkgs' `getAttrFromPath`. The membership test
  # at each step is what makes the refusal a `throw` rather than a raw selection failure, and the
  # message names the WHOLE requested path the way nixpkgs' `abort` does — not just the segment
  # that happened to fail, which is all the naive hand-rolls can say.
  getAttrByPath =
    path: attrs:
    foldl' (
      acc: seg:
      if isAttrs acc && acc ? ${seg} then
        acc.${seg}
      else
        throw "gen-prelude.getAttrByPath: attribute path '${concatStringsSep "." path}' not found"
    ) attrs path;
in
{
  # ── builtins re-exports (aliases; zero new code) ──
  inherit
    all
    any
    attrNames
    attrValues
    concatLists
    concatMap
    concatStringsSep
    elem
    elemAt
    filter
    foldl'
    functionArgs
    genList
    # groupBy partitions by string key and keeps input order within each group. It is a primop, so
    # this is an alias and not a vendored utility: the fold this replaces rebuilt
    # `(acc.${key} or [ ]) ++ [ x ]` at every step, copying the whole group each time (quadratic in
    # group size) and re-copying the accumulator attrset with `//`. The key domain is unchanged —
    # the fold used the key as an attribute name, so both forms abort alike on a non-string.
    groupBy
    head
    isAttrs
    isFunction
    isList
    length
    listToAttrs
    map
    mapAttrs
    match
    partition
    sort
    stringLength
    substring
    tail
    ;

  # ── vendored pure utilities (behavior-identical to nixpkgs lib) ──
  inherit nameValuePair;

  genAttrs =
    names: f:
    listToAttrs (
      map (n: {
        name = n;
        value = f n;
      }) names
    );
  optional = c: x: if c then [ x ] else [ ];
  optionalAttrs = c: a: if c then a else { };
  optionalString = c: s: if c then s else "";
  last =
    xs:
    if xs == [ ] then throw "gen-prelude.last: list must not be empty" else elemAt xs (length xs - 1);
  init =
    xs:
    if xs == [ ] then
      throw "gen-prelude.init: list must not be empty"
    else
      genList (i: elemAt xs i) (length xs - 1);

  # setAttrByPath path value / getAttrByPath path attrs — the nested-attrset writer and reader.
  # Vendored from nixpkgs `lib/attrsets.nix` (where the reader is now spelled `getAttrFromPath`),
  # but the refusal path is gen-prelude's own named, catchable `throw` — see the let block for the
  # measurement against nixpkgs' `abort` and the three gen twins these replace.
  inherit setAttrByPath getAttrByPath;

  # unique xs — order-preserving deduplication under structural `==`. See the let block above for
  # why this is a two-path and why the fold is still here.
  inherit unique;

  # findFirst pred default list — the first element satisfying `pred`, else `default`.
  # Behavior-identical to nixpkgs lib.findFirst (foldl'-based via findFirstIndex; stack-safe,
  # no early cutoff).
  findFirst =
    pred: default: list:
    let
      index = findFirstIndex pred null list;
    in
    if index == null then default else elemAt list index;

  # indexOf xs x — first position of `x` in `xs` (structural ==), or -1 if absent. List-first
  # arg order matches den-hoag's hand-rolls (stratum-scope.nix / declarations.nix) so consumers
  # adopt by `inherit (prelude) indexOf`. Built on the stack-safe findFirstIndex scan.
  # gen-prelude-original (no nixpkgs equivalent) → literal-expectation tested, not fidelity.
  indexOf = xs: x: findFirstIndex (y: y == x) (-1) xs;

  # dedupByKey getKey list — first-occurrence-wins dedup by key, order-preserving; a null key is
  # always kept and never deduplicated. Vendored from den-hoag (no nixpkgs equivalent) → defined
  # in the let block above, literal-expectation tested, not fidelity.
  inherit dedupByKey;

  # iterateBounded strict step init bound — `step` applied once per element of `bound` (its
  # elements ignored, its length the bound), with `strict` forced on every intermediate state.
  # The stack-safe encoding for a loop that carries state, as findFirstIndex is for a scan.
  # gen-prelude-original (no nixpkgs equivalent) → literal-expectation tested, not fidelity.
  inherit iterateBounded;
  filterAttrs =
    pred: a:
    listToAttrs (
      concatMap (
        n:
        let
          v = a.${n};
        in
        if pred n v then [ (nameValuePair n v) ] else [ ]
      ) (attrNames a)
    );
  mapAttrsToList = f: a: map (n: f n a.${n}) (attrNames a);
  concatMapStringsSep =
    sep: f: xs:
    concatStringsSep sep (map f xs);
  # Ordering is gen-graph's concern, not this library's: `sort` is the primitive
  # comparator sort and stops there. The vendored nixpkgs `toposort` (with its `listDfs`
  # and list-reverse helpers) that used to sit here is retired — topological ordering now
  # has one owner, `gen-graph.topoOrder`, which is Kahn 1962 over an accessor rather than
  # this depth-first scan.
  hasPrefix = pre: s: substring 0 (stringLength pre) s == pre;
  # Drop-in for nixpkgs lib.hasInfix / lib.escapeRegex, but linear (no `.*` backtracking).
  inherit hasInfix escapeRegex;
  imap0 = f: xs: genList (i: f i (elemAt xs i)) (length xs);
  fix =
    f:
    let
      x = f x;
    in
    x;
  max = a: b: if a > b then a else b;
  range = from: to: if from > to then [ ] else genList (i: from + i) (to - from + 1);
  removePrefix =
    pre: s:
    let
      n = stringLength pre;
    in
    if substring 0 n s == pre then substring n (stringLength s - n) s else s;
}
