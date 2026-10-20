# `patternOf f` — the shape of a function's pattern, the third functor-aware reader beside
# `isFunction` / `functionArgs` (den-hoag-gtwxg; the readers are den-hoag-7gp66 P2-OQ15 arm (i)).
#
#   patternOf : function -> { kind; formals; ellipsis; }
#
#   `kind`      "named" for `x:`; "set" for `{ … }:`, with or without `@`; "primop" for a builtin or
#               a primop application, which has neither pattern form;
#   `formals`   `functionArgs f`, unchanged: a functor's published `__functionArgs` wins;
#   `ellipsis`  true exactly when `kind == "set"` and the pattern carries `...`.
#
# A FUNCTOR is read the way `functionArgs` reads it: `kind` and `ellipsis` describe the lambda the
# call protocol applies, `f.__functor f`, and `formals` is the functor's published claim where it
# publishes one. So a `door` reads "named" with its derived formals: its call syntax, not its
# `__contract`.
#
# The domain is `isFunction` values. A non-function is refused at the record's WHNF, so `tryEval
# (patternOf v)` observes it. Every other refusal fires only where its field is read, because the
# two sources are independent: `kind` and `ellipsis` refuse a rendering the parse does not read, and
# `formals` refuses a functor whose `__functionArgs` is not an attrset of booleans. Each is a
# catchable `throw "gen-prelude.patternOf: …"`, so a reader of `kind` is never refused on `formals`.
#
# This file is its own unit so that `parse` is reachable by the ci cells that feed it perturbed
# renderings; `lib/default.nix` publishes `patternOf` only (den-hoag-gtwxg C2).
{ isFunction, functionArgs }:
let
  inherit (builtins)
    all
    attrValues
    concatStringsSep
    elemAt
    genList
    isAttrs
    isBool
    length
    match
    split
    stringLength
    substring
    typeOf
    ;

  refuse = msg: throw "gen-prelude.patternOf: ${msg}";

  # A COST BOUND, NEVER A REFUSAL: the parse first reads this many leading characters, which hold
  # every head but one whose name is long; past such a name the skeleton reads the head instead.
  prefixLength = 1024;
  # An attribute value the head grammar reads is `1` or a name, so a longer one is elided to `x`,
  # which the grammar reads the same way (`name="[^"]*"` still matches, and `ellipsis="x"` refuses).
  valueLength = 16;
  # Markup between two attribute values does not grow with the function, so a skeleton longer than
  # this is not the relied-on rendering, and is refused before the regex reads it.
  skeletonLength = 512;

  # The rendering split on `"`, which `toXML` escapes inside every attribute value, so the pieces
  # alternate markup and value. Its first six pieces hold every head and the character after it.
  skeletonOf =
    xml:
    let
      parts = split "\"" xml;
      piece =
        i:
        let
          s = elemAt parts (2 * i);
        in
        if i - 2 * (i / 2) == 1 && stringLength s > valueLength then "x" else s;
      pieces = (length parts + 1) / 2;
    in
    concatStringsSep "\"" (genList piece (if pieces < 6 then pieces else 6));

  # ★ THE ONE XML BINDING (den-hoag-a48xt arm (a), owner: "it may use (a) so long as it is well
  # documented and commented"). `patternOf` below is its only caller and holds the library's only
  # `builtins.toXML` call; `parse` reads what that call renders.
  #
  # WHY: no builtin exposes a function's `...`. `builtins.functionArgs` is `{ }` for `x:`, `{ }:` and
  # `{ ... }:` alike, so the pattern can only be read from the evaluator's XML rendering of the
  # lambda.
  #
  # WHAT IT RELIES ON: `builtins.toXML` of a lambda renders its pattern and never its body or its
  # defaults. The rendering opens with the XML declaration, then `<expr>`, then either `<function>`
  # followed by the head element, `<varpat name="…" />` or `<attrspat>` with the attribute list
  # ` ellipsis="1"` then ` name="…"` (each optional, in that order), or `<unevaluated />` for a
  # primop. Byte-identical on upstream Nix, Determinate and Lix (pinned by the `pattern-shape`
  # rendering cell in ci, which reds first if an evaluator changes it). Two facts of the evaluators'
  # XML writer hold this up, read from its source in all three: it writes a `"` inside an attribute
  # value as `&quot;`, so splitting the rendering on `"` alternates markup and value exactly; and
  # `ellipsis` precedes `name` because the attributes are a `std::map` in key order (the renderer
  # inserts `name` first), so an evaluator that kept insertion order would emit `name` first, which
  # the parse refuses.
  #
  # THE PARSE IS ANCHORED. It matches the declaration, `<expr>` and the whole head element, and the
  # `<attrspat>` attribute list exactly. Any other rendering is refused by name, never read as a
  # default: a loose `ellipsis="1"` search reads an `ellipsis="true"` rendering as `ellipsis = false`,
  # a silent misread. The regex never runs over a long name, because a `.*` over a long subject
  # overflows the C stack on Determinate and Lix, past `tryEval`: it reads the first `prefixLength`
  # characters, and where those do not match a longer rendering, its token skeleton instead.
  #
  # OPTION (c), documented beside (a) and NOT taken (den-hoag-t5hli R8, owner: "have it document
  # option C alongside it"): read no XML, and treat every `functionArgs == { }` shape alike. It is
  # uniform and needs no dependency on the rendering, but it cannot tell `x:` and `{ ... }:` (which
  # accept any set) from `{ }:` (which accepts only the empty one). A consumer must then hand all
  # three the same argument: gen-rules would hand its `{ ... }@a:` closures `{ }` (3 fixtures at
  # gen-rules d933ba8), and no reader could forward a call's arguments by pattern. And no builtin
  # exposes an ellipsis, so `{ a }` and `{ a, ... }` cannot be told apart under (c).
  #
  # FAILURE MODE: an evaluator that changes this rendering makes every read of `kind` or `ellipsis`
  # refuse by name (`formals` still serves).
  # bound once, outside `parse`, so an application allocates no regex thunk of its own
  headOf = match "<[?]xml version='1[.]0' encoding='utf-8'[?]>[[:space:]]*<expr>[[:space:]]*(<function>[[:space:]]*<(varpat) name=\"[^\"]*\" />|<function>[[:space:]]*<(attrspat)( ellipsis=\"1\")?( name=\"[^\"]*\")?>|<unevaluated />).*";
  parse =
    xml:
    let
      inPrefix = headOf (substring 0 prefixLength xml);
      skeleton = skeletonOf xml;
      m =
        if inPrefix != null || stringLength xml <= prefixLength then
          inPrefix
        else if stringLength skeleton > skeletonLength then
          null
        else
          headOf skeleton;
    in
    if m != null then
      if elemAt m 1 != null then
        {
          kind = "named";
          ellipsis = false;
        }
      else if elemAt m 2 != null then
        {
          kind = "set";
          ellipsis = elemAt m 3 != null;
        }
      else
        {
          kind = "primop";
          ellipsis = false;
        }
    else
      refuse "the function's XML rendering is not a form this reader parses";

  patternOf =
    f:
    let
      formals = functionArgs f;
      shape = parse (builtins.toXML (if f ? __functor then f.__functor f else f));
    in
    # `kind` and `ellipsis` describe the applied lambda, `formals` the published claim, so each
    # field carries its own source's refusal; only a non-function refuses the record itself.
    if !(isFunction f) then
      refuse "the argument is not a function by prelude.isFunction (its type is ${typeOf f})"
    else
      {
        inherit (shape) kind ellipsis;
        formals =
          if isAttrs formals && all isBool (attrValues formals) then
            formals
          else
            refuse "the functor's `__functionArgs` is not an attrset of booleans";
      };
in
{
  inherit parse patternOf;
}
