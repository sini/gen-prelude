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
    sort
    stringLength
    substring
    tail
    ;

  nameValuePair = name: value: { inherit name value; };

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
  hasPrefix = pre: s: substring 0 (stringLength pre) s == pre;
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
