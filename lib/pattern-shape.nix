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
# The domain is `isFunction` values whose `functionArgs` is an attrset of booleans. Outside it the
# reader refuses by name with a catchable `throw "gen-prelude.patternOf: …"`, fired at the record's
# WHNF, so `tryEval (patternOf v)` observes it.
#
# This file is its own unit so that `parse` is reachable by the ci cells that feed it perturbed
# renderings; `lib/default.nix` publishes `patternOf` only (den-hoag-gtwxg C2).
{ isFunction, functionArgs }:
let
  inherit (builtins)
    all
    attrValues
    elemAt
    filter
    isAttrs
    isBool
    isList
    length
    match
    seq
    split
    stringLength
    substring
    typeOf
    ;

  refuse = msg: throw "gen-prelude.patternOf: ${msg}";

  # The head is read inside this many leading characters, never by a regex over the whole rendering.
  prefixLength = 1024;

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
  # rendering cell in ci, which reds first if an evaluator changes it).
  #
  # THE PARSE IS ANCHORED. It matches the declaration, `<expr>` and the whole head element, and the
  # `<attrspat>` attribute list exactly. Any other rendering is refused by name, never read as a
  # default: a loose `ellipsis="1"` search reads an `ellipsis="true"` rendering as `ellipsis = false`,
  # a silent misread. It reads a bounded prefix because a `.*` over the whole rendering of a pattern
  # with thousands of formals overflows the C stack on Determinate, past `tryEval`.
  #
  # OPTION (c), documented beside (a) and NOT taken (den-hoag-t5hli R8, owner: "have it document
  # option C alongside it"): read no XML, and treat every `functionArgs == { }` shape alike. It is
  # uniform and needs no dependency on the rendering, but it cannot tell `x:` and `{ ... }:` (which
  # accept any set) from `{ }:` (which accepts only the empty one). A consumer must then hand all
  # three the same argument: gen-rules would hand its `{ ... }@a:` closures `{ }` (3 fixtures at
  # gen-rules d933ba8), and no reader could forward a call's arguments by pattern.
  #
  # FAILURE MODE: an evaluator that changes this rendering makes every `patternOf` refuse by name.
  parse =
    xml:
    let
      head = substring 0 prefixLength xml;
      m = match "<[?]xml version='1[.]0' encoding='utf-8'[?]>[[:space:]]*<expr>[[:space:]]*(<function>[[:space:]]*<(varpat) name=\"[^\"]*\" />|<function>[[:space:]]*<(attrspat)( ellipsis=\"1\")?( name=\"[^\"]*\")?>|<unevaluated />).*" head;
      # the declaration, `<expr>`, `<function>` and the head element close with four `>`
      closes = length (filter isList (split ">" head));
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
    else if stringLength xml > prefixLength && closes < 4 then
      refuse "the head of the function's XML rendering is not inside its first ${toString prefixLength} characters"
    else
      refuse "the function's XML rendering is not a form this reader parses";

  patternOf =
    f:
    let
      formals = functionArgs f;
      shape = parse (builtins.toXML (if f ? __functor then f.__functor f else f));
    in
    if !(isFunction f) then
      refuse "the argument is not a function by prelude.isFunction (its type is ${typeOf f})"
    else if !(isAttrs formals && all isBool (attrValues formals)) then
      refuse "the functor's `__functionArgs` is not an attrset of booleans"
    else
      seq shape {
        inherit (shape) kind ellipsis;
        inherit formals;
      };
in
{
  inherit parse patternOf;
}
