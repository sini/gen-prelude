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

  # ── toposort (vendored verbatim from nixpkgs lib/lists.nix) ──
  # toposort + its internal helpers listDfs/reverseList, copied byte-for-byte so the
  # `{ result } | { cycle; loops }` contract matches nixpkgs exactly (consumers like
  # gen-derive's dag and gen-vars depend on `? result`). Only `toposort` is exported.
  reverseList =
    xs:
    let
      l = length xs;
    in
    genList (n: elemAt xs (l - n - 1)) l;

  listDfs =
    stopOnCycles: before: list:
    let
      dfs' =
        us: visited: rest:
        let
          c = filter (x: before x us) visited;
          b = partition (x: before x us) rest;
        in
        if stopOnCycles && (length c > 0) then
          {
            cycle = us;
            loops = c;
            inherit visited rest;
          }
        else if length b.right == 0 then
          # nothing is before us
          {
            minimal = us;
            inherit visited rest;
          }
        else
          # grab the first one before us and continue
          dfs' (head b.right) ([ us ] ++ visited) (tail b.right ++ b.wrong);
    in
    dfs' (head list) [ ] (tail list);

  toposort =
    before: list:
    let
      dfsthis = listDfs true before list;
      toporest = toposort before (dfsthis.visited ++ dfsthis.rest);
    in
    if length list < 2 then
      # finish
      { result = list; }
    else if dfsthis ? cycle then
      # there's a cycle, starting from the current vertex, return it
      {
        cycle = reverseList ([ dfsthis.cycle ] ++ dfsthis.visited);
        inherit (dfsthis) loops;
      }
    else if toporest ? cycle then
      # there's a cycle somewhere else in the graph, return it
      toporest
    # Slow, but short. Can be made a bit faster with an explicit stack.
    else
      # there are no cycles
      { result = [ dfsthis.minimal ] ++ toporest.result; };

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
  groupBy =
    keyOf: xs:
    foldl' (
      acc: x:
      let
        key = keyOf x;
      in
      acc // { ${key} = (acc.${key} or [ ]) ++ [ x ]; }
    ) { } xs;
  concatMapStringsSep =
    sep: f: xs:
    concatStringsSep sep (map f xs);
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

  # Partial-order topological sort (vendored above in the let block). Returns
  # `{ result = sorted; }` or `{ cycle; loops; }` — identical to nixpkgs lib.toposort.
  inherit toposort;
}
