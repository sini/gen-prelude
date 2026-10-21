# What Nix can apply, and the function it applies (den-hoag-b6nyh, after gen-bind's den-hoag-k0whn
# machine, which answers the verdict only). Nix calls a set carrying `__functor` by pushing the set
# and calling its `__functor`, so `f x` is `(f.__functor f) x`, and `__functor` may itself be such a
# set. `applicability` runs that machine for one unknown argument and answers `{ verdict; head; }`:
# `verdict` is true when it reaches a function with nothing left to push (`head` is that function,
# the one the argument meets), false when Nix would call a non-function or a pattern that cannot bind
# the pushed set, and null when no answer comes within `applicableLevels` `__functor` steps.
# Applicability is only semi-decidable (a `__functor` may return its own set forever), so the walk is
# fuelled and an exhausted walk is refused. Evaluating `f.__functor f` runs the caller's code; what
# that code throws, the reader throws.
{ isFunction, patternOf }:
let
  applicableLevels = 32;
  # Whether Nix can bind the pushed set to `h`'s pattern: a set pattern needs every required formal
  # present, and without `...` no attribute beyond its formals (the set always carries `__functor`).
  # `functionArgs` reads `x:` and `{ }:` alike as `{ }`, so a `{ }:` pattern passes here.
  binds =
    h: arg:
    let
      fa = builtins.functionArgs h;
    in
    fa == { }
    || (
      builtins.all (n: fa.${n} || arg ? ${n}) (builtins.attrNames fa)
      && ((patternOf h).ellipsis || builtins.all (n: fa ? ${n}) (builtins.attrNames arg))
    );
  refused = {
    verdict = false;
    head = null;
  };
  walk =
    fuel: h: known:
    if builtins.isFunction h then
      if known == [ ] then
        {
          verdict = true;
          head = h;
        }
      else if binds h (builtins.head known) then
        walk fuel (h (builtins.head known)) (builtins.tail known)
      else
        refused
    else if builtins.isAttrs h && h ? __functor then
      if fuel == 0 then
        {
          verdict = null;
          head = null;
        }
      else
        walk (fuel - 1) h.__functor ([ h ] ++ known)
    else
      refused;
  # The one-step case first: a set whose `__functor` is a function that binds the set yields the head
  # by one application, with no walk frame; anything else takes the fuelled walk. `binds`' own first
  # disjunct is written out here so a `__functor` with no set pattern costs no call to `binds`.
  applicability =
    f:
    if
      builtins.isAttrs f
      && f ? __functor
      && builtins.isFunction f.__functor
      && (builtins.functionArgs f.__functor == { } || binds f.__functor f)
    then
      let
        h = f.__functor f;
      in
      if builtins.isFunction h then
        {
          verdict = true;
          head = h;
        }
      else
        walk (applicableLevels - 1) h [ ]
    else
      walk applicableLevels f [ ];
in
{
  inherit applicableLevels applicability;
  # The door's question, a bool. A lambda costs no walk.
  isApplicable = f: builtins.isFunction f || (applicability f).verdict == true;
  # The pattern of an applicable value: read on the value itself where `isFunction` holds (so a
  # published `__functionArgs` is honoured), else on the head the walk reaches.
  applicablePatternOf = f: patternOf (if isFunction f then f else (applicability f).head);
  # A refused value's kind as a door names it: "a set" is false of a functor whose walk exhausted the
  # bound (Nix may still apply it), so that one names the bound. Read on the refusal path only.
  applicableKindOf =
    v:
    if builtins.isAttrs v && v ? __functor && (applicability v).verdict == null then
      "a functor that reaches no function within ${toString applicableLevels} `__functor` steps"
    else
      "a ${builtins.typeOf v}";
}
