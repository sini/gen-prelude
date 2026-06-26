# gen-prelude — pure, nixpkgs-lib-free utilities for the gen ecosystem.
#
# `builtins` re-exports plus the handful of pure utilities the gen substrate uses,
# vendored behavior-identically from nixpkgs lib. The dependency that lets the pure
# gen libraries drop `nixpkgs.lib`.
#
# NOT a type system, NOT a module-system shim (the `lib.types`/`mkOption`/`evalModules`
# tier is a separate Korora-class concern, out of scope here).
#
# Design + vendor strategy:
#   den-architecture/gen-specs/gen-prelude/2026-06-26-gen-prelude-design.md
{ ... }:
let
  inherit (builtins)
    all
    any
    attrNames
    attrValues
    concatLists
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
    sort
    stringLength
    substring
    tail
    ;

  nameValuePair = name: value: { inherit name value; };
  # nixpkgs lib.concatMap is builtins.concatMap; vendor as concatLists∘map for safety.
  concatMap = f: xs: concatLists (map f xs);
in
{
  # ── builtins re-exports (aliases; zero new code) ──
  inherit
    all
    any
    attrNames
    attrValues
    concatLists
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
    sort
    stringLength
    substring
    tail
    ;

  # ── vendored pure utilities (behavior-identical to nixpkgs lib) ──
  inherit nameValuePair concatMap;

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
  last = xs: elemAt xs (length xs - 1);
  init = xs: genList (i: elemAt xs i) (length xs - 1);
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

  # TODO(vendor): copy nixpkgs `lib.toposort` verbatim (~30 LOC) for byte-fidelity
  # before any consumer (gen-derive / gen-vars) migrates onto it. See design spec §2,§3.
  toposort = throw "gen-prelude.toposort: not yet vendored — copy nixpkgs lib.toposort verbatim";
}
