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
    ;

  nameValuePair = name: value: { inherit name value; };

  # ── string containment (backtracking-free) ──
  # nixpkgs `lib.hasInfix infix s` is `match ".*${escapeRegex infix}.*" s != null`; the
  # leading/trailing `.*` make std::regex recurse to depth ∝ `stringLength s`, overflowing
  # the C stack when scanning whole source files (readFile'd libraries in purity checks).
  # Split on the escaped literal instead: `split` carries no `.*` anchor and scans linearly.
  # Result is the same boolean as nixpkgs (fidelity-tested), so it is a drop-in.
  # Metacharacter set matches nixpkgs `lib.escapeRegex` verbatim (stringToCharacters
  # "\\[{()^$?*+.|]") so the escaped output is byte-identical — a drop-in.
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
        "."
        "|"
        "]"
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

  # ── dedupByKey (vendored from den-hoag lib/dedup-by-key.nix; itself the port of v1 scope-walk
  # dedupByKey @ pin 11866c16) — no nixpkgs equivalent, so not in the fidelity suite. ──
  # First-occurrence-wins dedup by `getKey`, order-preserving. A `null` key is ALWAYS kept and
  # NEVER entered into `seen` (the SAFE direction: a keyless element cannot be proven a
  # cross-scope duplicate, so a false-keep of equal content equal-merges harmlessly, whereas a
  # false-collapse of distinct content is silent content-loss). null-key nodes neither evict a
  # later duplicate nor are evicted.
  dedupByKey =
    getKey: list:
    let
      go =
        seen: items:
        if items == [ ] then
          [ ]
        else
          let
            x = head items;
            rest = tail items;
            k = getKey x;
          in
          if k != null && seen ? ${k} then
            go seen rest
          else
            [ x ] ++ go (if k != null then seen // { ${k} = true; } else seen) rest;
    in
    go { } list;
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
  unique = foldl' (acc: x: if elem x acc then acc else acc ++ [ x ]) [ ];

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
