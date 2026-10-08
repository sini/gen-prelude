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
    genList
    groupBy
    head
    isAttrs
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
  #
  # The path-type guard is the writer's, verbatim: the ruling scopes over THE PAIR, and a reader
  # that falls into `foldl'`'s raw abort on a malformed path does not meet it however well the
  # writer behaves. It also makes the not-found message total — `concatStringsSep` is only ever
  # reached on a list of strings.
  getAttrByPath =
    path: attrs:
    if !isList path || !all isString path then
      throw "gen-prelude.getAttrByPath: path must be a list of strings"
    else
      foldl' (
        acc: seg:
        if isAttrs acc && acc ? ${seg} then
          acc.${seg}
        else
          throw "gen-prelude.getAttrByPath: attribute path '${concatStringsSep "." path}' not found"
      ) attrs path;

  # ── THE DOOR CONSTRUCTS (den-hoag-7gp66 P1) ──
  #
  # Three checks every published door shares, so each has ONE definition: the closed options set
  # and the open data record (R5), and the reference resolver (R1). Each refusal reads
  # `<door>: … (in prelude.<construct>)` — the published door the caller invoked first, the
  # construct as secondary detail (R6) — and is a `throw`, so `tryEval` contains it (ADR-0025
  # item 1). That is why a door takes `...` formals and calls one of these: a native closed formal
  # refuses an unknown argument, and a native required formal a missing one, past `tryEval`.
  # gen-prelude-original (no nixpkgs equivalent) → literal-expectation tested.
  #
  # `refusals` — THE TEXT OF EVERY REFUSAL A DOOR'S CALLER CAN MEET, as values (den-hoag-7jltk). Each
  # checker below throws exactly `refusals.<name> <its own arguments>`, so the published text and the
  # thrown text are one expression and cannot drift. A downstream cell composes its expected message
  # through these with its OWN literal door, field and accepted set, and so keeps every assertion
  # while pinning none of this library's wording. One binding, never forced on a success path: a
  # checker reads it only inside its `throw`. Each renders a caller value by its type alone, as
  # gen-graph's `notAnIdentifier` does: `typeOf` is total, so the refusal cannot itself abort.
  refusals =
    let
      quoteNames = names: concatStringsSep ", " (map (n: "'${n}'") names);
    in
    {
      optionsNotASet =
        door: accepted: v:
        "${door}: the options must be an attrset, not a ${builtins.typeOf v} (accepted: ${quoteNames accepted}) (in prelude.checkOptions)";
      unknownOption =
        door: accepted: field:
        "${door}: '${field}' is not an option of this door; the options are closed (accepted: ${quoteNames accepted}) (in prelude.checkOptions)";
      recordNotASet =
        door: required: v:
        "${door}: the argument must be an attrset, not a ${builtins.typeOf v} (required: ${quoteNames required}) (in prelude.checkRequired)";
      missingField =
        door: required: field:
        "${door}: required field '${field}' is missing (required: ${quoteNames required}) (in prelude.checkRequired)";
      guardedField =
        door: guardName: field:
        "${door}: '${field}' is an option of ${guardName}, not a field of this record (in prelude.checkGuarded)";
      unknownReference =
        door: id: "${door}: reference '${id}' names no entry of the registry (in prelude.resolve)";
      ambiguousDeclaration =
        door: name: candidates:
        "${door}: declaration '${name}' is ambiguous: it matches more than one entry of the registry (candidates: ${quoteNames candidates}) (in prelude.resolve)";
      unregisteredDeclaration =
        door: name: available:
        "${door}: declaration '${name}' is not a member of the registry (available: ${quoteNames available}) (in prelude.resolve)";
      unlocatedDeclaration =
        door: hint: form:
        "${door}: a declaration must carry a string '${hint}' to locate it (expected ${form}) (in prelude.resolve)";
      notAReference =
        door: form: v:
        "${door}: expected an identifier (a string) or a declaration (${form}), got a ${builtins.typeOf v} (in prelude.resolve)";
    };

  # `checkOptions door accepted opts` — an options set is CLOSED: every field is optional, and one
  # outside `accepted` is refused by name, with the accepted set named. A pass-through, so it cannot
  # be written and then not called. A non-set is refused before `attrNames`, which aborts on one.
  checkOptions =
    door: accepted: opts:
    if !isAttrs opts then
      throw (refusals.optionsNotASet door accepted opts)
    else
      let
        unknown = filter (f: !elem f accepted) (attrNames opts);
      in
      if unknown == [ ] then opts else throw (refusals.unknownOption door accepted (head unknown));

  # `checkRequired door required record` — a data record is OPEN (width subtyping, R5): a missing
  # field is refused by name, and an extra one is admitted and never reported. That silence is R5's
  # stated price. A door taking required fields AND options composes the two:
  # `checkOptions door (required ++ optional) (checkRequired door required args)`.
  checkRequired =
    door: required: record:
    if !isAttrs record then
      throw (refusals.recordNotASet door required record)
    else
      let
        missing = filter (f: !(record ? ${f})) required;
      in
      if missing == [ ] then record else throw (refusals.missingField door required (head missing));

  # `checkGuarded door guardName guardedNames record` — a data record's field is refused BY NAME
  # when it is also one of a SIBLING options step's own declared names (den-hoag-7gp66 v1.2,
  # premise 7: R5's width subtyping applied where it should not reach — a chained door's record
  # step silently admitted, then ignored, an option that belonged on its own options step one
  # position earlier). `guardedNames` is always DERIVED from the sibling's own `__contract`
  # (`required ++ optional`), never hand-written, so it cannot drift from what that door actually
  # accepts. Every other extra field keeps R5's unchanged width subtyping (cell G10-ctl) — only a
  # name that collides with the sibling's own options is refused.
  checkGuarded =
    door: guardName: guardedNames: record:
    let
      hits = filter (f: elem f guardedNames) (attrNames record);
    in
    if hits == [ ] then record else throw (refusals.guardedField door guardName (head hits));

  # ── the readers (den-hoag-7gp66 P2-OQ15 arm (i)) ──
  # nixpkgs `lib.isFunction` / `lib.functionArgs` (lib/trivial.nix), vendored verbatim: FUNCTOR-AWARE.
  # These names were once bare `builtins` aliases, which read a functor as a non-function and abort
  # uncatchably (`'functionArgs' requires a function`) on one — so on every `door` below. A functor
  # carrying `__functionArgs` (nixpkgs `setFunctionArgs`, and `door`) reads that map; a lambda reads
  # exactly what the builtin reads.
  functionArgs =
    f:
    if f ? __functor then
      f.__functionArgs or (builtins.functionArgs (f.__functor f))
    else
      builtins.functionArgs f;
  isFunction =
    f:
    builtins.isFunction f
    || (f ? __functor && builtins.isFunction f.__functor && builtins.isFunction (f.__functor f));

  # `door { name; required ? [ ]; optional ? [ ]; open ? false; } body` — a published door that
  # takes a RECORD step and publishes its field contract AS DATA (den-hoag-49yxv, defaulted and
  # reversible; C′). The result is a functor in nixpkgs' `setFunctionArgs` convention:
  #   `__contract`     the contract itself, `{ name; required; optional; open; }` — the one source;
  #   `__functionArgs` DERIVED from it (required ↦ false, optional ↦ true), so `functionArgs` and the
  #                    ADR-0035 vocabulary walk read the door's fields, and the map cannot disagree
  #                    with the check, because both come from one value;
  #   `__functor`      the check, then `body`.
  # The check is derived from the same contract: `open` is R5's data record (`checkRequired` alone,
  # width subtyping); closed is `checkOptions (required ++ optional) ∘ checkRequired required`, and a
  # door with no required field takes `checkOptions optional` alone (`checkRequired _ [ ] r ≡ r` on an
  # attrset, and a non-attrset is still refused catchably, by `checkOptions`).
  #
  # ★ THE CHECK IS FORCED AT THE DOOR'S APPLICATION: `let a = check args; in seq a (body a)`, never
  # `body (check args)` — that form is lazy whenever `body`'s WHNF does not read its argument, and it
  # admits both an unknown and a missing field (trap 23e19dc0; the `seq checked` idiom of `resolve`).
  # A pure options door (closed, no required field) answers `{ }` without the check, since
  # `checkOptions _ _ { } ≡ { }`; the choice is made once per door.
  #
  # Contract, map and check are bound when `door spec` is applied, before `body`, so a nested door
  # binds `door spec` once and supplies only the body per call. A curried door is a chain: each record
  # step is its own door, and `functionArgs` reads the first step. `mkDoor` is the unchecked core;
  # the published `door` is itself a door over its own spec record.
  # `contractOf spec` — a step's published contract, and through `next` every later step's
  # (den-hoag-ak8va; OQ16 "nest", owner 2026-09-28): the range of the step's arrow contract,
  # published as data under the same normal form as its domain (Findler & Felleisen 2002). It reads
  # `name`, `required`, `optional`, `open` and `next` and nothing else, so a `next` spec naming its
  # own `optionsStep` (the OUTER door, `optionsStep = options;`) is never forced here: that is the
  # circular read the construction must not make. A POSITIONAL node, `{ positional = "<operand>";
  # next; }`, is a plain-lambda step between two record steps (`memo.build`'s `engine`): its flat
  # contract is the operand's name, and it publishes the record step behind it as its own `next`.
  contractOf =
    spec:
    if spec ? positional then
      {
        inherit (spec) positional;
        next = contractOf spec.next;
      }
    else
      {
        inherit (spec) name;
        required = spec.required or [ ];
        optional = spec.optional or [ ];
        open = spec.open or false;
      }
      // (if (spec.next or null) == null then { } else { next = contractOf spec.next; });
  # The first RECORD step a `next` chain reaches, past its positional nodes (or null).
  recordNextOf = n: if n != null && n ? positional then recordNextOf n.next else n;
  mkDoor =
    spec:
    let
      inherit (spec) name;
      required = spec.required or [ ];
      optional = spec.optional or [ ];
      open = spec.open or false;
      publishedArgs =
        listToAttrs (map (n: nameValuePair n false) required)
        // listToAttrs (map (n: nameValuePair n true) optional);
      # Every binding here is a thunk per door built, so the guard is bound only on the branch that
      # reads it. (v1.2, den-hoag-7gp66 premise 7) `optionsStep` is an already-built sibling door,
      # consulted only under `open = true`; `guardedNames` is DERIVED from its `__contract`, never
      # hand-written. Forcing `.__contract` never forces `.__functor`, so this can name the OUTER,
      # already-built door of a chain (`optionsStep = dispatch;`) with no circular-evaluation
      # problem, even though that door's own definition calls back into this record step: the two
      # thunks are independent.
      check =
        if open then
          (
            if (spec.optionsStep or null) == null then
              checkRequired name required
            else
              let
                g = spec.optionsStep.__contract;
                guardedNames = g.required ++ g.optional;
              in
              if guardedNames == [ ] then
                checkRequired name required
              else
                record: checkGuarded name g.name guardedNames (checkRequired name required record)
          )
        else if required == [ ] then
          checkOptions name optional
        else
          args: checkOptions name (required ++ optional) (checkRequired name required args);
    in
    body: {
      __contract = contractOf spec;
      __functionArgs = publishedArgs;
      # The functor is chosen once per door. A door without `next` keeps the one it had, so the drift
      # guard costs nothing outside the chains that publish a next step.
      __functor =
        if (spec.next or null) == null then
          (
            if !open && required == [ ] then
              _: args:
              if args == { } then
                body args
              else
                let
                  a = check args;
                in
                seq a (body a)
            else
              _: args:
              let
                a = check args;
              in
              seq a (body a)
          )
        else
          let
            n = spec.next;
            # The drift guard (OQ16 "nest"), the range half of the arrow contract, checked at the
            # result. A record `next` admits a door named `next.name` and refuses anything else by
            # name; it reads the result's WHNF and one attribute, which the caller of a chained
            # step forces anyway to apply it. The NAME is the chain's family (every live chain reuses
            # its step-1 name), so a same-name sibling is caught at `door spec` by the record step's
            # anchor on its `optionsStep`, not here. A positional `next` admits a function.
            guard =
              if n ? positional then
                r:
                if isFunction r then
                  r
                else
                  throw "${name}: the contract declares the positional step '${n.positional}', but the body returned a ${builtins.typeOf r} (in prelude.door)"
              else
                r:
                if
                  isAttrs r && r ? __functor && isAttrs (r.__contract or null) && r.__contract.name or null == n.name
                then
                  r
                else
                  throw "${name}: the contract declares the next step '${n.name}', but the body returned ${
                    if isAttrs r && isAttrs (r.__contract or null) then
                      "the door '${r.__contract.name or "?"}'"
                    else
                      "a ${builtins.typeOf r}"
                  } (in prelude.door)";
          in
          if !open && required == [ ] then
            _: args:
            if args == { } then
              guard (body args)
            else
              let
                a = check args;
              in
              seq a (guard (body a))
          else
            _: args:
            let
              a = check args;
            in
            seq a (guard (body a));
    };
  # A `next` spec is checked at `door spec` like the door's own (closed, `name` required, no field
  # both required and optional), recursively through its own `next`, and its refusals name WHERE it
  # sits (`the next step of '<owner>'`), so a typo inside `next` is never read as one in the outer
  # spec. A positional node is closed over `positional` and `next`, and both are required. Its
  # `optionsStep` is NOT read: it names the outer door being built, and reading its contract here is
  # a cycle.
  checkNextSpec =
    owner: n:
    let
      at = "gen-prelude.door (the next step of '${owner}')";
    in
    if isAttrs n && n ? positional then
      let
        c = checkOptions at [ "positional" "next" ] (checkRequired at [ "positional" "next" ] n);
      in
      if !isString c.positional then
        throw "${at}: 'positional' must name the operand as a string, not a ${builtins.typeOf c.positional} (in prelude.door)"
      else
        checkNextSpec owner c.next
    else
      let
        c = checkOptions at [
          "name"
          "required"
          "optional"
          "open"
          "optionsStep"
          "next"
        ] (checkRequired at [ "name" ] n);
        both = filter (f: elem f (c.optional or [ ])) (c.required or [ ]);
      in
      if both != [ ] then
        throw "${at}: '${head both}' is both required and optional in the next step '${c.name}' (in prelude.door)"
      else if (c.next or null) != null then
        checkNextSpec c.name c.next
      else
        true;
  # The spec record is itself checked at `door spec` (closed, `name` required), and a field both
  # required and optional is refused by name there: the derived map would publish it optional
  # (`//` keeps the right side) while the check requires it, so map and check would disagree.
  #
  # THE ANCHOR (den-hoag-ak8va OQ-2, defaulted and reversible): a record step naming its
  # `optionsStep` is the second step of that door's chain, so the options step must publish THIS
  # step's contract as its next record step, exactly. An undeclared chain and a same-name drift
  # (a `next` that names the family but not the step) are both refused here, once per `door spec`
  # and never per application. It cannot see a chain whose record step names no `optionsStep`
  # (`resolve`'s closed registry), which declares `next` by hand.
  door =
    mkDoor
      {
        name = "gen-prelude.door";
        required = [ "name" ];
        optional = [
          "required"
          "optional"
          "open"
          "optionsStep"
          "next"
        ];
      }
      (
        s:
        if (s.next or null) != null && seq (checkNextSpec s.name s.next) false then
          null
        else if filter (f: elem f (s.optional or [ ])) (s.required or [ ]) != [ ] then
          throw "gen-prelude.door: '${
            head (filter (f: elem f (s.optional or [ ])) (s.required or [ ]))
          }' is both required and optional in the contract of '${s.name}' (in prelude.door)"
        else if !(s ? optionsStep) || s.optionsStep == null then
          mkDoor s
        else if (s.open or false) != true then
          throw "gen-prelude.door: 'optionsStep' guards a record's fields and is meaningless without open = true (in the contract of '${s.name}') (in prelude.door)"
        else
          let
            g = s.optionsStep.__contract;
            overlap = filter (f: elem f (g.required ++ g.optional)) (s.required or [ ]);
            declared = recordNextOf (g.next or null);
          in
          if overlap != [ ] then
            throw "gen-prelude.door: '${head overlap}' is both required here and an option of '${g.name}' (in the contract of '${s.name}') (in prelude.door)"
          else if declared == null then
            throw "gen-prelude.door: '${g.name}' is this record step's optionsStep but declares no next step (in the contract of '${s.name}') (in prelude.door)"
          else if declared != contractOf s then
            throw "gen-prelude.door: '${g.name}' declares a next step that is not this record step's contract (in the contract of '${s.name}') (in prelude.door)"
          else
            mkDoor s
      );

  # `resolve { hint ? "name"; form ? "an attrset"; } { entries; isCanonical; } door ref` — a reference,
  # written as an identifier or as a declaration value, to its IDENTIFIER (R1).
  #
  # - An identifier is a STRING (den-hoag-3w9e7 arm (a)) and must name an entry.
  # - A declaration is an attrset. Its `hint` field LOCATES candidates and never decides: the entry
  #   of that name is tried first, then every entry whose own `hint` field agrees. The VERDICT is the
  #   member's `isCanonical v k` — "v is the canonical entry `entries.${k}`" — which this library
  #   cannot know: it reads the member's own layout (gen-schema: stamp equality and identity-key
  #   value equality, den-hoag-a4158). It must answer a bool or throw, and it mints nothing
  #   (ADR-0034: a comparison mints nothing). The first candidate that passes is the answer, UNLESS
  #   more than one candidate passes: that is ambiguity (gate C2), refused by name naming every
  #   candidate. Ambiguity is a property of `entries`, not of the mint — an injective mint stops one
  #   value being minted twice, not one minted node being filed under two identifiers of one map — so
  #   it is checked on every call, not assumed unreachable within a single registry.
  # - Anything else is refused by name.
  #
  # ★ THE REGISTRY IS BOUND BEFORE THE DOOR NAME, against R6's name-first order everywhere else, and
  # that is cost rather than style: the by-hint index is built in the registry's binding, so it is
  # shared by every door and every reference. A door-first binding rebuilds it per door, and a door
  # whose name varies per call site (an option location) pays O(n) per reference.
  #
  # The index is built only when a hint misses, and it forces every entry's `hint` field and
  # nothing else: an entry whose other fields are computed through this resolver is not dragged in.
  #
  # Two record steps, both doors (P2, R7): the OPTIONS first (`hint`, `form`; closed), then the
  # REGISTRY (`entries`, `isCanonical`; required, closed — an unknown field is a mistake, not
  # extension data). Each is checked at its own application, catchably and by name, so a bad
  # registry is refused when `resolve opts registry` is formed, whether or not the returned door is
  # ever called (gen-memo eed0685's defect class). Both specs are bound once, outside any call.
  resolveRegistrySpec = {
    name = "gen-prelude.resolve";
    required = [
      "entries"
      "isCanonical"
    ];
  };
  resolveOptions = mkDoor {
    name = "gen-prelude.resolve";
    optional = [
      "hint"
      "form"
    ];
    next = resolveRegistrySpec;
  };
  resolveRegistry = mkDoor resolveRegistrySpec;
  resolve = resolveOptions (
    o:
    let
      hint = o.hint or "name";
      form = o.form or "an attrset";
      hintOf =
        v:
        let
          h = v.${hint} or null;
        in
        if isString h then unsafeDiscardStringContext h else null;
    in
    resolveRegistry (
      r:
      let
        inherit (r) entries isCanonical;
        byHint = groupBy (k: hintOf entries.${k}) (
          filter (k: hintOf entries.${k} != null) (attrNames entries)
        );
      in
      door: ref:
      if isString ref then
        let
          id = unsafeDiscardStringContext ref;
        in
        if entries ? ${id} then id else throw (refusals.unknownReference door id)
      else if isAttrs ref && hintOf ref != null then
        let
          h = hintOf ref;
          found = filter (isCanonical ref) (byHint.${h} or [ ]);
        in
        if entries ? ${h} && isCanonical ref h then
          h
        else if length found > 1 then
          throw (refusals.ambiguousDeclaration door h found)
        else if found != [ ] then
          head found
        else
          throw (refusals.unregisteredDeclaration door h (attrNames entries))
      else if isAttrs ref then
        throw (refusals.unlocatedDeclaration door hint form)
      else
        throw (refusals.notAReference door form ref)
    )
  );
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
    genList
    # groupBy partitions by string key and keeps input order within each group. It is a primop, so
    # this is an alias and not a vendored utility: the fold this replaces rebuilt
    # `(acc.${key} or [ ]) ++ [ x ]` at every step, copying the whole group each time (quadratic in
    # group size) and re-copying the accumulator attrset with `//`. The key domain is unchanged —
    # the fold used the key as an attribute name, so both forms abort alike on a non-string.
    groupBy
    head
    isAttrs
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

  # renderValue v — TOTAL RENDERING OF A CALLER VALUE INSIDE A REFUSAL. The one shared renderer
  # (den-hoag-shared-refusal-renderer-6wtos) behind gen-scope's `resolveClaims` refusals, every
  # gen-view `refuse` site and gen-merge's conflict refusal. A refusal is built at the moment
  # something has already gone wrong, and it renders exactly the value that was wrong: `toJSON`
  # aborts on a function at any depth and overflows on a cyclic value, and string interpolation
  # aborts on anything that is not a string, all three past `tryEval`. Scalars and name lists render
  # in full, because those are the shapes a caller acts on; anything else is named by its type,
  # `<a T>`, which reads as a noun phrase inside the refusal's sentence.
  #
  # Two arms keep scalar information `toJSON` would lose or mangle. A FINITE float renders by
  # `toJSON` (`1.5`, `0.30000000000000004`, `1e-10`); a non-finite one by `toString` (`inf`,
  # `-inf`, `-nan`), because `toJSON` renders all three as `null`, and `toString` of a finite float
  # rounds to six places. A path renders by `toString`, because `toJSON` of a path copies it to the
  # store.
  #
  # CONTRACT. It forces the value to WHNF and, for a list, each element to WHNF under `tryEval`, and
  # never deeper — so a cyclic value, a set with a throwing field and a set holding functions all
  # render as `<a set>`. It returns a string for every value whose WHNF evaluates. A list element
  # whose WHNF throws catchably renders the whole list as `<a list>` (the `tryEval` is gen-harness
  # `fail-message.nix`'s third defence, den-hoag-t9ug0). A value or element whose WHNF aborts
  # uncatchably (`abort`, `1 + "a"`, a missing attribute) still aborts, and a top-level `throw` or
  # failed `assert` propagates as the value's own error: no render can observe a value it cannot
  # reach. It RENDERS and never ADDRESSES: two different lambdas render alike, which a message may
  # do and a key may not.
  #
  # COST. Callers reach it only inside a `throw` string, so its element pass costs nothing on any
  # success path.
  # gen-prelude-original (no nixpkgs equivalent) → literal-expectation tested, not fidelity.
  renderValue =
    v:
    if builtins.isString v || builtins.isInt v || builtins.isBool v || v == null then
      builtins.toJSON v
    else if builtins.isFloat v then
      (if v - v == 0.0 then builtins.toJSON v else toString v)
    else if builtins.isPath v then
      toString v
    else if builtins.isList v && (builtins.tryEval (builtins.all builtins.isString v)).value then
      builtins.toJSON v
    else
      "<a ${builtins.typeOf v}>";

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
  # nixpkgs `lib.isStringLike` (lib/strings.nix), vendored verbatim: a string, a path, or a set
  # `toString` coerces (an `outPath` set, which every derivation is, or a `__toString` set).
  isStringLike = x: builtins.isString x || builtins.isPath x || x ? outPath || x ? __toString;
  # The door constructs (den-hoag-7gp66 P1; checkGuarded is v1.2), defined above, and the text of
  # their refusals (den-hoag-7jltk), which each throws verbatim.
  inherit
    refusals
    checkGuarded
    checkOptions
    checkRequired
    door
    resolve
    ;
  # The functor-aware readers (nixpkgs `lib.isFunction` / `lib.functionArgs`), defined above.
  inherit isFunction functionArgs;
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
