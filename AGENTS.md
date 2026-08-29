# gen-prelude — agent capability sheet

## Scope

The zero-dependency utility base of the gen ecosystem: `builtins` re-exports plus the pure list/attrset/string helpers the substrate uses, vendored behaviour-identically from `nixpkgs.lib`, so every other pure gen library can drop `nixpkgs.lib` from its closure.

## Not this library's job

gen-prelude holds general pure utilities only. Everything below is a *domain* concern owned by a sibling. Quoted text is the owner's own `flake.nix` `description` field, verbatim.

| Utility-shaped need | Owner |
|---|---|
| Structural type checking, `verify` | `gen-types` — "gen-types: pure, nixpkgs-lib-free structural type checker for the gen ecosystem" |
| Priority-aware / deep module merge, `evalModules`, `mkIf`/`mkMerge`/`mkDefault` | `gen-merge` — "gen-merge — pure-Nix byte-mode module MERGE engine (evalModuleTree) for the pure-gen module system". `lib/default.nix:7-8` states the `lib.types`/`mkOption`/`evalModules` tier is out of scope here |
| Records, search monad, `either`, intensional identity and equality | `gen-algebra` — "gen-algebra: pure Nix algebra — search monad, records, intensional functions, either" |
| Injecting external arguments into modules | `gen-bind` — "gen-bind: module binding with external arguments for Nix" |
| Typed registries, kinds, instances, refs, and identity-key REFLECTION (`id_hash` stamping) | `gen-schema` — "gen-schema: typed record registry with extension points for the pure-gen module system" |
| Identity MINTING — `hashIdentity`, the substrate's one authority (ADR-0016 ruling 5) | `gen-identity` — "gen-identity: the substrate's one identity mint — a bounded canonical encoding of inert values and the kind-tagged digest over it" |
| Aspect traits, classification, composition | `gen-aspects` — "gen-aspects: aspect-oriented composition types (pure-gen, re-hosted on gen-merge)" |
| Scope-graph evaluation, memoized and circular attributes | `gen-scope` — "gen-scope: demand-driven attribute grammar evaluator over algebraic scope graphs" |
| Graph traversal, condensation, `phaseOrder`, **topological ordering of any kind** | `gen-graph` — "gen-graph: accessor-based graph query combinators". `gen-graph.topoOrder` is the one ordering front door; this library keeps `sort` (primitive comparator sort) and nothing above it |
| Predicate matching over graph positions | `gen-select` — "gen-select: selector algebra for attributed graph positions" |
| Rule dispatch, ordering, conflict resolution | `gen-dispatch` — "gen-dispatch: relational rule dispatch over ordered groups (the dispatch STEP)" |
| Demand-driven attribute schedules, convergence loops | `gen-resolve` — "gen-resolve — demand-driven higher-order RAG evaluator over algebraic scope graphs (Knuth 1968 attribute schedule + Vogt 1989 HOAG)" |
| `map`/`filter`/`fold`/`scan` over **channels** (the list versions here are plain list functions) | **`gen-view`, which inherited it — `gen-pipe` RETIRED as a library rather than moving as one.** ADR-0010 §3 retires gen-pipe into the movement vocabulary; twelve of its seventeen exports name gen-view constructs (the fourth destination §3 gained on 2026-08-20) and `sel` retires into `gen-select`. The gen-pipe repository orphans as reference under ADR-0031 §3's F3 pattern, off the `gen/lib/mkGenLibs.nix` roster and not a `gen` hub input. The name collision this row exists to head off is unchanged: the `map`/`filter`/`fold`/`scan` here are plain list functions and always were |
| Graph products, coordinates, slices, fibers | `gen-product` — "gen-product — graph products as first-class operations over accessor-graphs (Cartesian / tensor / strong / lexicographic; cells, slices, fibers, projections, quotients, restriction, containment chains), lazy in and out" |
| Layered settings resolution, refs-as-data, provenance | `gen-settings` — "gen-settings — stratified settings resolution as a pure layered fold, with refs-as-data, structured provenance, and the graduated injection construct" |
| Typed demand cascade, resource/wiring resolution | **`gen-scope`, which inherited it — `gen-demand` RETIRED as a library rather than moving as one.** ADR-0008 §4: *"gen-resolve and gen-demand as libraries retire into these homes; gen-demand's demand/kind folds re-express over scope"*. The cascade is `gen-scope/lib/cascade.nix` + `lib/folds.nix` under claim vocabulary (`mkClaim` / `resolveClaims`); the gen-demand repository orphans as reference under ADR-0031 §3's F3 pattern, off the `gen/lib/mkGenLibs.nix` roster and not a `gen` hub input. This row is the retirement's residue, not a live surface |
| Content-movement `(S,T,P,M)` edge algebra, materialization fold | **`gen-view`, which inherited it — `gen-edge` RETIRED as a library rather than moving as one.** ADR-0010 §3 retires the content-movement contract into the movement vocabulary, with gen-view — the substrate's derived-view constructor — the fourth destination §3 gained on 2026-08-20. Twelve of the eighteen exports name gen-view constructs, and `toposort` splits into `accumulatorRelation` plus `accumulatorOrder` over gen-graph's Kahn arm. The gen-edge repository orphans as reference under ADR-0031 §3's F3 pattern, off the `gen/lib/mkGenLibs.nix` roster and not a `gen` hub input. This row is the retirement's residue, not a live surface |
| Cross-flake aspect federation over origin-labeled subgraphs | `gen-link` — "gen-link: cross-flake aspect federation over origin-labeled subgraphs" |
| Class share: partition / contract / apply / gate | `gen-class` — "gen-class — pure-Nix class-share mechanism (partition / contract / apply / gate) for the pure-gen module system" |
| Incremental rebuild, change propagation, AFFECTED set | `gen-memo` — "gen-memo — the incremental plane: a decision layer over the evaluator that never evaluates, only decides reuse" |
| Variable / secret generation | `gen-vars` — "gen-vars: scope-driven, multi-target variable generation" |
| The nixpkgs boundary; building NixOS systems; value injection | `gen-flake` — "gen-flake — the pure composition boundary of the pure-gen module ecosystem" |
| Ecosystem wiring / two-stage lib instantiation | `gen` (hub) — `gen/flake.nix` carries **no** `description` field; the roster is `gen/lib/mkGenLibs.nix`, which binds this lib as `prelude` (`gen/lib/mkGenLibs.nix:prelude`) |
| `hasSuffix`, `removeSuffix`, `zipAttrsWith`, `concatStrings` | **No gen owner.** Absent from gen-prelude and named nowhere in any `gen-*/lib` tree (see traps). `recursiveUpdate` and `splitString` appear only as private `let` bindings inside `gen-algebra/lib/rec.nix`, `gen-merge/lib/modules.nix` and `gen-class/lib/apply.nix` — not exports |

## Exports

Entry: `inputs.gen-prelude.lib` (flake). Root `default.nix` and `import ./lib` are the same bare value — **not** a function, so it takes no dependency argument. The flake declares zero inputs (`flake.nix:4-6`), so pulling gen-prelude in adds nothing to a consumer's lock. The namespace is **flat**: no export is itself an attrset.

**`builtins` re-exports** — aliases, zero new code (`lib/default.nix` § *builtins re-exports*, the `inherit` block in the exported attrset). Semantics are exactly those of the corresponding `builtins.*`. Note the let-block `inherit (builtins)` is wider than this list: `replaceStrings` and `split` are pulled in for `escapeRegex` / `hasInfix` and deliberately **not** re-exported.

```
all  any  attrNames  attrValues  concatLists  concatMap  concatStringsSep  elem
elemAt  filter  foldl'  functionArgs  genList  groupBy  head  isAttrs  isFunction
isList  length  listToAttrs  map  mapAttrs  match  partition  sort  stringLength
substring  tail
```

**Vendored `nixpkgs.lib` utilities** — `lib/default.nix` § *vendored pure utilities*. Held behaviour-identical to `lib.*` by the `prelude-fidelity` suite.

| Export | Signature |
|---|---|
| `genAttrs` | `[string] -> (string -> a) -> attrset` |
| `nameValuePair` | `string -> a -> { name; value; }` |
| `filterAttrs` | `(string -> a -> bool) -> attrset -> attrset` |
| `mapAttrsToList` | `(string -> a -> b) -> attrset -> [b]` |
| `optional` | `bool -> a -> [a]` |
| `optionalAttrs` | `bool -> attrset -> attrset` |
| `optionalString` | `bool -> string -> string` |
| `last` / `init` | `[a] -> a` / `[a] -> [a]` — both **throw** on `[ ]` |
| `setAttrByPath` | `[string] -> a -> attrset` — `[ ]` returns the value unchanged; **throws** (named, catchable) when the path is not a list of strings |
| `getAttrByPath` | `[string] -> attrset -> a` — `[ ]` returns the attrset unchanged; **throws** (named, catchable) naming the whole dotted path on a missing key or a non-attrset mid-path. nixpkgs renamed its own to `getAttrFromPath`; the older name is kept for symmetry with the writer, so a name-based fidelity diff will read that divergence and it is deliberate |
| `unique` | `[a] -> [a]` (order-preserving, structural `==`; total on every value type) |
| `findFirst` | `(a -> bool) -> a -> [a] -> a` (pred, default, list) |
| `imap0` | `(int -> a -> b) -> [a] -> [b]` (0-based) |
| `range` | `int -> int -> [int]` (inclusive; `[ ]` when `from > to`) |
| `max` | `a -> a -> a` (any `>`-comparable, strings included) |
| `fix` | `(a -> a) -> a` |
| `concatMapStringsSep` | `string -> (a -> string) -> [a] -> string` |
| `hasPrefix` / `removePrefix` | `string -> string -> bool` / `string -> string -> string` |
| `hasInfix` | `string -> string -> bool` — drop-in for `lib.hasInfix`, **reimplemented** (split-based, linear); not a verbatim copy |
| `escapeRegex` | `string -> string` — drop-in for `lib.escapeRegex`; metachar set is nixpkgs' twelve (`stringToCharacters "\\[{()^$?*+\|."`) verbatim, `]` deliberately NOT among them, implementation is `replaceStrings` |

**gen-prelude originals** (no `nixpkgs.lib` counterpart; covered by the literal-expectation `prelude` suite, not `prelude-fidelity`).

| Export | Signature |
|---|---|
| `indexOf` | `[a] -> a -> int` — **list first**, then needle; `-1` if absent |
| `dedupByKey` | `(a -> string\|null) -> [a] -> [a]` — first-occurrence-wins, order-preserving; a `null` key is always kept and never entered into `seen` |
| `iterateBounded` | `(s -> b) -> (s -> s) -> s -> [a] -> s` (strict, step, init, bound) — `step` once per element of `bound`, **elements ignored, only the length read**; `strict` forced on every intermediate state |

**Internal, not exported**: `findFirstIndex` (the shared stack-safe scan under `findFirst`/`indexOf`), `listDfs`, `reverseList`. `replaceStrings` and `split` are inherited from `builtins` in the `let` block for internal use only and are **not** re-exported.

## Entry points by task

| Task | Reach for |
|---|---|
| Any `builtins.X` without naming `builtins` | `prelude.X` for the 28 aliases above |
| Substitute for a `lib.X` call in a pure gen lib | `prelude.X` — identical semantics, no `nixpkgs.lib` in the closure |
| Substring test over a large string (source files, readFile'd libs) | `hasInfix` — the reason it exists; `lib.hasInfix` overflows the C stack here |
| Escape a literal for use in a regex | `escapeRegex` |
| Order a partial order / detect a cycle | NOT HERE — `gen-graph.topoOrder`; discriminate on `.ok` |
| Deduplicate a list by identity | `unique` (structural `==`) — linear on a list of strings, quadratic in the DISTINCT count on any other element type |
| Deduplicate by a derived key, keeping keyless elements | `dedupByKey` |
| Find an element or its position | `findFirst pred default list` / `indexOf list x` — note the opposite argument orders |
| Build an attrset from names | `genAttrs`; pair-wise via `nameValuePair` + `listToAttrs` |
| Group a list by a string key | `groupBy` (the primop; linear, input order preserved within a group) |
| Loop over state without recursing (a scan cannot carry it) | `iterateBounded strict step init bound` — the bound is a list you already hold; `strict` names the loop-carried fields |
| Tie a knot | `fix` |
| Type checking, module merge, or any domain concern | Not here — see the negative-space table |

## Measured traps

Each row verified in this run. Shared fixtures: `p = import ./lib`; `ok e = (builtins.tryEval e).success`; `big` = 40 000 chars (`"abcdefghij"` × 4000); `mk n` = `genList (i: { k = "k" + toString i; }) n`. All evaluations run from the repo root with `nix eval --impure --expr`.

| Trap | Evidence |
|---|---|
| **`dedupByKey` used to overflow the stack — FIXED, and the ceiling is removed rather than raised.** The naive non-tail recursion (`[ x ] ++ go …`) had to force the recursive call to build the `++`, so descent depth WAS the input length. It is now a first-index table built entirely from primops, with no Nix-level recursion left to descend | Re-run at this revision, same fixture: `n=1000/2000/5000/10000/50000/200000` ⇒ `1000/2000/5000/10000/50000/200000`, no overflow anywhere. ★ **Positive control, same fixture and same run** — the PREVIOUS implementation (`e1794e2`) over the identical `mk n`: `n=9000` ⇒ `9000`, `n=10000` ⇒ `error: stack overflow; max-call-depth exceeded`. Without that arm "no overflow" is a predicate that could not have failed. Second control: `indexOf` at `n=10000` ⇒ `9999`. Test: `test-dedupByKey-stack-safe-at-scale` asserts 50 000 in-suite |
| **`unique`'s cost is in TWO variables, and which path you get depends on element type.** N is the list length, K the distinct count. A list of strings takes a linear key→first-index table (`2N + 3K + 3`); anything else takes the retained fold (`K(K+1)/2 + K + N + 2` — quadratic in **K**, not N). Do not read a figure stated without its K | Fold, all-distinct (K = N): `502,502 / 2,005,002 / 8,010,002` `.list.elements` at `N = 1,000/2,000/4,000`, exponent **1.9982**; the two-path at the same points reads `5,003 / 10,003 / 20,003`, exponent **0.99978**. ★ **The string path is not free everywhere.** At K ≪ N it allocates up to exactly **2.00×** MORE than the fold did (1.43× / 1.85× / 1.97× / 2.00× at K = 26, N = 800/4,000/20,000/400,000) and time drifts as `log N / K` — measured `cpuTime` **+29.5%** at (N = 400,000, K = 8) and **+47.7%** at (N = 1.6 M, K = 8), 9 reps, minimum taken. `cpuTime` drifts between machines and runs: five independent runs of this pair span +24.5%…+31.3% and +47.6%…+54.8%, every one inside the +60% bar the oracle sets, so treat the shape as the finding and the exact percentage as a reading. Deduplicating a long list of few distinct strings is the one shape this library is knowingly slower on than it used to be |
| **`toposort` was quadratic, and is now retired** — the reading that motivated moving ordering to gen-graph | Descending input, wall clock incl. `nix` startup: `n=500` 110 ms, `n=1000` 327 ms, `n=2000` 1201 ms — ~4× per doubling. Control, same harness and fixture: `p.sort` ⇒ 29/28/28 ms. Re-measured on the same fixture before removal: 0.11/0.34/1.25 s, control 0.02 s flat |
| **A non-string, non-`null` `dedupByKey` key is an error `tryEval` does not catch** — it is an interpreter type error at the attribute-name site, not a `throw` | `ok (p.dedupByKey (n: n.k) [ { k = 1; } { k = 1; } ])` ⇒ the whole eval aborts with `error: expected a string but found an integer: 1` at `lib/default.nix:230:9`, the caret under `name = getKey (elemAt list i);` — the `listToAttrs` name field. Controls, same run: `ok` over the same call with `k = "1"` ⇒ `true`; `ok (p.last [ ])` ⇒ `false`, i.e. `tryEval` *does* catch this lib's explicit `throw`s. ★ **Re-run at this revision, not re-pointed.** The re-expression moved the site: the transcript here previously read `lib/default.nix:149:36` with the caret under `seen ? ${k}`, one of the old `go` helper's two dynamic-attribute sites, and that helper no longer exists. The message text survives the re-run unchanged; the line and column both moved, and the failing construct is now a static attribute-name field rather than a dynamic-attr lookup. A transcript asserts that something *was measured*, so the honest repair is to measure again and publish what the run emitted, never to edit a coordinate underneath a message the new location never produced |
| **`indexOf` takes the list first**, opposite to `findFirst pred default list`. Swapping is likewise uncatchable | `p.indexOf [ "a" "b" "c" ] "b"` ⇒ `1`; `ok (p.indexOf "b" [ "a" "b" ])` ⇒ eval aborts, `error: expected a list but found a string: "b"`. Test: `test-indexOf-first` (`ci/tests/prelude.nix`) |
| **`hasInfix "" s` is unconditionally `true`**, empty haystack included — the `infix == ""` short-circuit fires before any scan (`lib/default.nix:75`) | `p.hasInfix "" ""` ⇒ `true`, `p.hasInfix "" "abc"` ⇒ `true` |
| `hasInfix` is a *reimplementation*, not a copy: it is linear where `lib.hasInfix`'s `.*needle.*` regex recurses to depth ∝ haystack length | `p.hasInfix "needle" big` ⇒ `false`, `p.hasInfix "abcdefghij" big` ⇒ `true`, no overflow. Test: `test-hasInfix-large-string-safe` (`ci/tests/prelude.nix`) |
| Needle metacharacters are literal (`escapeRegex` runs first) | `p.hasInfix "a.c" "abc"` ⇒ `false`. Tests: `test-hasInfix-metachars`, `test-hasInfix-metachars-nomatch` |
| `escapeRegex` escapes `{` but **not** `}`, and not `-` — the metachar set is nixpkgs' twelve verbatim, so a needle is only regex-safe to the same degree nixpkgs makes it | `p.escapeRegex "a{b}c"` ⇒ `"a\\{b}c"`; `p.escapeRegex "a-b"` ⇒ `"a-b"`. Test: `test-escapeRegex` |
| **`]` is NOT in the set, and that is load-bearing rather than an omission.** A lone `]` is already literal to the engine, and `\]` is a rejected pattern — so escaping it would turn every `]`-bearing needle into an abort where nixpkgs answers, and `builtins.tryEval` does not catch that abort. Over-escaping is as wrong as under-escaping | `p.escapeRegex "]"` ⇒ `"]"`; `p.escapeRegex "[x]"` ⇒ `"\\[x]"` (`[` quoted, `]` not); `p.hasInfix "]" "a]b"` ⇒ `true`, `p.hasInfix "]" "axb"` ⇒ `false`, `p.hasInfix "[x]" "y[x]z"` ⇒ `true`, each equal to `lib.`'s answer on the same inputs. Planted control, `"]"` re-added to the set: the three `escapeRegex` arms go ❌ and the three `hasInfix` arms go ☢️ `invalid regular expression '\]'`, 60/66. Tests: `test-escapeRegex-close-bracket`, `test-escapeRegex-bracket-expression`, `test-hasInfix-close-bracket-match`, `test-hasInfix-close-bracket-nomatch`, `test-hasInfix-bracket-expression` |
| The escape set is covered **per member**, both directions, because which member is wrong decides which needle notices | Twelve `test-escset-*` arms, one per member, each pair chosen so dropping its member changes the answer — measured one drop at a time: `{`, `^`, `$`, `?`, `*`, `+`, `.`, `\|` flip the boolean, `\`, `[`, `(`, `)` leave an invalid pattern and raise. The ADD direction is `test-escapeRegex-printable-ascii`, byte-identity against `lib.escapeRegex` over all 95 printable ASCII characters — the only arm that sees an added member as an ordinary red rather than an abort |
| `last`/`init` on `[ ]` throw with a **gen-prelude-specific message**, not nixpkgs' text (fidelity is over values, not error strings) | `ok (p.last [ ])` and `ok (p.init [ ])` ⇒ `false`; message: `error: gen-prelude.last: list must not be empty`. Control: `p.last [ 1 2 3 ]` ⇒ `3`. Test: `test-last-empty-throws` |
| `toposort` is **gone**, and its absence is asserted rather than assumed | `p ? toposort` ⇒ `false`. Control on the same predicate in the same run: `p ? sort` ⇒ `true`. Tests: `test-toposort-not-exported`, `test-sort-still-exported` |
| `findFirst` has no early cutoff — the `foldl'` walks every index — but it does **not force** elements past the match | `p.findFirst (x: x == 1) 0 [ 1 (throw "boom") ]` ⇒ `1`, `ok …` ⇒ `true`. `p.findFirst (_: true) "DEF" [ ]` ⇒ `"DEF"` |
| **`iterateBounded`'s `strict` argument is load-bearing, and skipping it fails at a size no `max-call-depth` bounds** — `foldl'` forces the accumulator to WHNF, so a record's FIELDS accumulate a thunk chain that costs C stack on the final force, reported as a DIFFERENT signature | Same expression, same run, `st: { xs = st.xs ++ [ 1 ]; }` over `p.range 1 N`: with `strict = _: null` ⇒ `N=20000/50000` OK, **`N=100000` ⇒ `error: stack overflow (possible infinite recursion)`** — not `max-call-depth exceeded`. Paired control, same N: `strict = st: builtins.length st.xs` ⇒ `100000` returns |
| **A field `strict` never names is still safe IF THE STEP'S OWN GUARD READS IT — the one exception to the row above, and it is a domination property rather than a fact about the field.** The guard forces the field before either branch is chosen, so the previous iteration's thunk collapses every step and the chain stays ONE deep instead of growing to N. ⇒ omitting a field from `strict` is a decision that owes an argument naming the guard, never an omission | Same N, same `strict = _: null`, `init = { c = 0; }` over `p.range 1 100000`, reading `.c` — **only the guard differs**: unguarded `st: { c = st.c + 1; }` ⇒ `error: stack overflow (possible infinite recursion)`, `EXIT=1`; guarded `st: if st.c >= 0 then { c = st.c + 1; } else st` ⇒ `100000`, `EXIT=0`. Command (the failing arm): `nix eval --impure --expr 'let p = import ./lib; in (p.iterateBounded (_: null) (st: { c = st.c + 1; }) { c = 0; } (p.range 1 100000)).c'`. ★ **The failing arm is a SHELL arm, and that is the language rather than a convenience** — wrapping it in `builtins.tryEval` aborts the whole evaluation (`EXIT=1`) instead of returning `false`. Controls, same instrument, same run: `tryEval` over the guarded arm ⇒ `true`, `ok (p.last [ ])` ⇒ `false`, so `tryEval` demonstrably catches what is catchable here. ★★ **Planted control, measured — the unguarded arm does not merely fail to be observable IN the suite, it DESTROYS the suite's report.** With the guard deleted from the cell and nothing else changed, `nix-unit --flake ./ci#tests` dies mid-run at **25 of 114 arms**, emitting **0 ❌ and 0 ☢️** and `error: stack overflow (possible infinite recursion)` — the other 89 arms never run and nothing says so. **Only `EXIT=1` distinguishes that from a clean run**, so a reader counting failure glyphs alone reads a truncated suite as green. The pair also arms the C-stack signature from a second, independent shape. Test (guarded arm only): `test-iterateBounded-step-guard-forces-carried` |
| **The encoding it exists for**: a self-applying loop spends one frame per iteration and its abort is uncatchable | `p.iterateBounded (_: null) (st: st + 1) 0 (p.range 1 20000)` ⇒ `20000` (twice the default `max-call-depth`). Positive control that the comparison loop runs at all: `let go = i: acc: if i == 0 then acc else go (i - 1) (acc + 1); in go 5000 0` ⇒ `5000`; the same at `20000` ⇒ `error: stack overflow; max-call-depth exceeded`, and wrapping it in `builtins.tryEval` aborts the evaluation rather than returning `false` |
| `unique` compares structurally, so distinct attrsets with equal contents collapse | `p.unique [ { a = 1; } { a = 1; } { a = 2; } ]` ⇒ `[ { a = 1; } { a = 2; } ]` |
| `groupBy` is the **primop alias**, not a vendored copy, and so carries no `prelude-fidelity` arm by design (`ci/tests/prelude.nix`, the "groupBy has NO fidelity arm" note in the `prelude-fidelity` suite; behaviour pinned instead by `test-groupBy` / `test-groupBy-empty` / `test-groupBy-collision-order` in the `prelude` suite) | `p.groupBy (s: substring 0 1 s) [ "art" "ale" "bar" ]` ⇒ `{ a = [ "art" "ale" ]; b = [ "bar" ]; }`, equal to `builtins.groupBy` on the same input. Identity cannot be shown by `==`: Nix function equality is always false — controls `builtins.groupBy == builtins.groupBy` ⇒ `false` and `let f = x: x; in f == f` ⇒ `false` |
| `max` is `a > b`, so it works on any comparable, strings included | `p.max "a" "b"` ⇒ `"b"` |
| The lib is a **value**, not a function — there is no `gen-prelude { inherit lib; }` call | `builtins.isFunction (import ./lib)` ⇒ `false`, `builtins.isAttrs` ⇒ `true` |
| `README.md`'s **API Reference** documents neither `hasInfix` nor `escapeRegex`, though both are top-level exports covered by the fidelity suite. They are named only in the test-plane section, which describes arms rather than the surface | `grep -n 'hasInfix\|escapeRegex\|groupBy' README.md` ⇒ `145` (`groupBy`, API Reference — the positive control for the same pattern in the same run), `229`/`256`/`257` (`groupBy`, test plane), `260`/`264`/`265` (`escapeRegex`, test plane). No `hasInfix` line anywhere. ★ **Re-run at this revision, not re-pointed.** The transcript here previously read `141, 183, 192, 193`; the same command at `59f0d71`, before any change in this commit, already returned `145, 229, 256, 257`, so those four coordinates named nothing the command produced. A transcript asserts that something *was measured* — the repair is to run it again and publish the output |
| `replaceStrings` and `split` are **not** re-exported, though the lib uses both internally | `p ? split` and `p ? replaceStrings` ⇒ `false`; control on the same predicate, same run: `genAttrs`/`unique`/`hasInfix`/`escapeRegex`/`sort`/`dedupByKey`/`indexOf` all ⇒ `true` |
| **A PATH WRITER AND READER NOW EXIST — this row used to say they did not.** `setAttrByPath` and `getAttrByPath` landed 2026-08-28 (den-hoag-4kh.53.56, G11); the suffix, split and deep-merge halves of the old claim still hold, and no defaulted `attrByPath` variant was added | `hasSuffix`, `removeSuffix`, `splitString`, `concatStrings`, `recursiveUpdate`, `flatten`, `attrByPath`, `zipAttrsWith`, `mapAttrs'`, `min`, `take`, `drop`, `subtractLists`, `intersectLists`, `reverseList`, `findFirstIndex`, `id`, `pipe`, `trace`, `deepSeq`, `sortOn`, `stringToCharacters`, `types`, `mkOption`, `evalModules`, `mkIf`, `mkMerge`, `mkDefault` — all ⇒ absent (49-name probe, `builtins.filter (n: l ? ${n}) [ … ]` ⇒ `[]` at this revision, against the 7-name positive control above). ★★ **THE PROBE IS NOT AN ORACLE FOR THE SENTENCE, which is why the sentence went false while the probe stayed green.** It names `attrByPath` — the DEFAULTED variant, still absent — and neither name that actually landed, so it reads `[]` on a tree exporting two path helpers. Live control, same run, same revision: `[ "attrByPath" "setAttrByPath" "getAttrByPath" ]` ⇒ `["setAttrByPath","getAttrByPath"]`. A claim and the probe under it can have different domains; check the claim |
| **The path pair's refusals are NAMED, and `tryEval` cannot see that half — SHELL arms.** `tryEval` returns `{ success = false; value = false; }` with the message simply absent, so a build throwing `"bad path"` greens every in-suite refusal cell. The named half rides here until `den-hoag-9mo` lands | Three arms, this revision, each `nix eval --impure --expr '<e>' 2>&1 \| grep -q '<pat>'`. `(import ./lib).setAttrByPath "ab" 1` ⇒ `error: gen-prelude.setAttrByPath: path must be a list of strings`, grep for `gen-prelude\.setAttrByPath:` **EXIT=0**. `(import ./lib).setAttrByPath [ 1 ] "v"` — the NON-STRING SEGMENT, which no `tryEval` cell reaches usefully — ⇒ the same named message, **EXIT=0**; ★ **a build guarding only `!isList` returns `error: expected a string but found an integer: 1` beneath *"while evaluating the name of a dynamic attribute"*, EXIT=1**, and its `tryEval` twin exits 1 with no JSON at all, so the catchability cells are structurally blind to it. `(import ./lib).getAttrByPath ["missing"] {}` ⇒ `error: gen-prelude.getAttrByPath: attribute path 'missing' not found`, grep for `gen-prelude\.getAttrByPath:` **EXIT=0**; through a non-attrset, `["a" "b" "c"]` over `{ a.b = 1; }` ⇒ `attribute path 'a.b.c' not found` — the WHOLE requested path, not the failing segment. Controls, same run: `p.last [ ]` grepped for `gen-prelude\.last:` ⇒ EXIT=0 (the instrument can return 0); the same captured stderr grepped for a planted negative ⇒ EXIT=1. Tests (the catchable half only): `test-setAttrByPath-non-list-path-throws`, `test-setAttrByPath-non-string-segment-throws`, `test-getAttrByPath-missing-throws`, `test-getAttrByPath-through-non-attrset-throws`, with `test-getAttrByPath-present-control` |
| Four of those names occur in **no** `gen-*/lib` tree at all | `grep -rlE '\b<name>\b' gen-*/lib gen/lib` from `~/Documents/repos/sini` ⇒ `<none>` for `hasSuffix`, `removeSuffix`, `zipAttrsWith`, `concatStrings`. Control, same sweep: `genAttrs` 23 files, `toposort` 6 (all comments and gen-edge's own implementation — no call to this library remains), `mkIntensional` 3 |

## Theory

**One encoding claim, and no research lineage.** `iterateBounded` is an encoding decision — bounded iteration in place of recursion to a fixed point — argued in `lib/default.nix` and README rather than copied from anywhere; everything else is vendored or aliased. `README.md`'s own section is *Provenance*: "gen-prelude has no research lineage — it is plumbing." The repo's claim structure is origin attribution plus a fidelity guarantee.

**Origins** (README's Provenance table): `genAttrs`, `filterAttrs`, `mapAttrsToList`, `nameValuePair`, `optionalAttrs` ← nixpkgs `lib/attrsets.nix`; `optional`, `last`, `init`, `unique`, `imap0`, `range`, `findFirst` ← `lib/lists.nix`; `optionalString`, `concatMapStringsSep`, `hasPrefix`, `removePrefix` ← `lib/strings.nix`; `fix`, `max` ← `lib/trivial.nix` / `lib/fixed-points.nix`. `dedupByKey` ← den-hoag `lib/dedup-by-key.nix`; `indexOf` is gen-prelude-original.

**Checked invariant**: purity is *structural*, not test-enforced — the flake declares no inputs, so no `nixpkgs.lib` is in scope to depend on (`flake.nix:4-6`, `README.md:196-197`). There is no `purity` suite here, unlike sibling libs. What the tests do guard is fidelity: `prelude-fidelity` asserts `prelude.X input == lib.X input` for every vendored utility over normal and boundary inputs, against the nixpkgs `lib` oracle that `ci/` pulls in for that purpose (`ci/flake.nix:2-5`).

## Drift check

```sh
nix eval --json .#lib --apply builtins.attrNames
```

The namespace is flat, so this one call is the whole contract — every name the Exports section claims appears below, and nothing claimed sits outside it. (Verified flat in this run: `nix eval --json .#lib --apply 'l: builtins.filter (n: builtins.isAttrs l.${n}) (builtins.attrNames l)'` ⇒ `[]`.)

Current output (verbatim):

```json
["all","any","attrNames","attrValues","concatLists","concatMap","concatMapStringsSep","concatStringsSep","dedupByKey","elem","elemAt","escapeRegex","filter","filterAttrs","findFirst","fix","foldl'","functionArgs","genAttrs","genList","getAttrByPath","groupBy","hasInfix","hasPrefix","head","imap0","indexOf","init","isAttrs","isFunction","isList","iterateBounded","last","length","listToAttrs","map","mapAttrs","mapAttrsToList","match","max","nameValuePair","optional","optionalAttrs","optionalString","partition","range","removePrefix","setAttrByPath","sort","stringLength","substring","tail","unique"]
```

The command observes export *names* only; signatures, trap rows and `file:line` refs rot without changing it.

**Checks.** Test-runner invocation (from the repo root; CI runs the same command with `working-directory: ci`, `.github/workflows/ci.yml:13,18`, followed by `nix fmt -- --ci` at line 19):

```sh
nix flake check ./ci
```
