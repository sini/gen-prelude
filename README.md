# gen-prelude — vendored, nixpkgs-lib-free utilities for the gen ecosystem

[![CI](https://github.com/sini/gen-prelude/actions/workflows/ci.yml/badge.svg)](https://github.com/sini/gen-prelude/actions/workflows/ci.yml) [![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT) [![Sponsor](https://img.shields.io/badge/Sponsor-%E2%9D%A4-pink?logo=github)](https://github.com/sponsors/sini)

The small pure-utility dependency that lets the pure gen substrate drop `nixpkgs.lib`.
It is `builtins` re-exports plus the handful of pure utilities (`genAttrs`, `unique`,
`filterAttrs`, `fix`, `optional`, `sort`, …) the substrate uses, vendored
behavior-identically from nixpkgs `lib`.

**Not** a type system, **not** a module-system shim — only general pure utilities. The
`lib.types` / `mkOption` / `evalModules` tier is a separate concern (a Korora-class
replacement) and out of scope here.

Dependency class: **A (pure)** — the lib takes no flake inputs and imports nothing from
`nixpkgs.lib`; it is the nixpkgs-lib-free base every other pure gen lib depends on. The
lib flake carries zero inputs, so a consumer's lock gains no transitive nixpkgs
dependency from pulling gen-prelude in. Purity is enforced structurally (the flake has
no inputs to draw a `lib` from), and every utility vendored from nixpkgs is held
byte-behavior-identical to its counterpart by the `prelude-fidelity` test suite. (The
few gen-prelude-originals with no nixpkgs counterpart — `indexOf`, `dedupByKey` — are
covered by the literal-expectation `prelude` suite instead; see [Provenance](#provenance).)

## Table of Contents

- [Overview](#overview)
- [Gen Ecosystem](#gen-ecosystem)
- [Usage](#usage)
- [API Reference](#api-reference)
- [Testing](#testing)
- [Performance](#performance)
- [Provenance](#provenance)

## Overview

gen-prelude is a single attrset of pure functions — no inputs, no functor. Two kinds of
member:

- **`builtins` re-exports** — direct aliases of Nix `builtins` (`map`, `filter`,
  `foldl'`, `genList`, `partition`, …), grouped under one name so consumers need not
  reach into `builtins` themselves.
- **Vendored pure utilities** — the small set of `nixpkgs.lib` helpers the gen substrate
  actually uses (`genAttrs`, `filterAttrs`, `unique`, `fix`, …), copied here
  so the pure gen libraries can depend on gen-prelude instead of `nixpkgs.lib`. Each is
  behavior-identical to its `lib.*` original.

The mental model: wherever a pure gen lib would have written `lib.X`, it writes
`prelude.X` instead and gets identical semantics with no `nixpkgs.lib` in its closure.
Downstream libraries — gen-graph (`phaseOrder` over condensation), gen-vars, gen-scope,
gen-dispatch, and others — build on exactly this surface.

## Gen Ecosystem

| Library | Role |
|---------|------|
| [gen-prelude](https://github.com/sini/gen-prelude) | **This lib** — Pure nixpkgs-lib-free utility base (builtins re-exports + vendored lib utils) |
| [gen-algebra](https://github.com/sini/gen-algebra) | Pure primitives (record, search monad, either, intensional identity) |
| [gen-types](https://github.com/sini/gen-types) | Clean-room MIT structural type checker (leaf/poly checkers; `verify: v → null\|err`) |
| [gen-merge](https://github.com/sini/gen-merge) | Byte-mode module merge engine (`evalModuleTree`, byte-identical to nixpkgs `lib.evalModules` over the priority subset) |
| [gen-schema](https://github.com/sini/gen-schema) | Typed registries (kinds, instances, collections, refs); re-hosted on gen-merge |
| [gen-aspects](https://github.com/sini/gen-aspects) | Aspect type system (traits, classification, dispatch); re-hosted on gen-merge |
| [gen-scope](https://github.com/sini/gen-scope) | HOAG scope-graph evaluator (demand-driven, \_eval memoization, circular attributes) |
| [gen-graph](https://github.com/sini/gen-graph) | Accessor-based graph query combinators (traversal, condensation, phaseOrder) |
| [gen-select](https://github.com/sini/gen-select) | Selector algebra (pattern matching over graph positions) |
| [gen-bind](https://github.com/sini/gen-bind) | Module binding (inject external args into NixOS modules) |
| [gen-dispatch](https://github.com/sini/gen-dispatch) | Relational rule dispatch STEP (stratified phases, conflict resolution) |
| [gen-resolve](https://github.com/sini/gen-resolve) | Demand-driven RAG evaluator over scope graphs (attribute schedule + convergence loop) |
| [gen-memo](https://github.com/sini/gen-memo) | The incremental plane — decides reuse, never evaluates (change propagation, AFFECTED set) |
| [gen-vars](https://github.com/sini/gen-vars) | Pure-Nix vars/secrets (den-agnostic) |
| [gen-flake](https://github.com/sini/gen-flake) | The nixpkgs boundary — compose purely, inject resolved values, build NixOS systems (value-injection) |

## Usage

### As a flake input

```nix
{
  inputs.gen-prelude.url = "github:sini/gen-prelude";

  outputs = { gen-prelude, ... }:
    let
      prelude = gen-prelude.lib;
    in
    {
      example = prelude.genAttrs [ "a" "b" ] (n: n + "!");
      # => { a = "a!"; b = "b!"; }
    };
}
```

gen-prelude has **no inputs**, so nothing transitive (no nixpkgs) enters your lock. The
`.lib` output is a plain value — there is no `gen-prelude { inherit lib; }` functor call.

### Without flakes

```nix
let
  prelude = import "${builtins.fetchGit { url = "https://github.com/sini/gen-prelude"; }}/lib";
  # or, against a local checkout:  prelude = import ./path/to/gen-prelude/lib;
in
prelude.unique [ 3 1 1 2 3 ]  # => [ 3 1 2 ]
```

`import ./lib` (equivalently `import ./default.nix`) evaluates directly to the lib
attrset — no arguments, since the lib depends on nothing.

## API Reference

Every name below is a top-level member of the lib attrset (verified against
`nix eval .#lib --apply builtins.attrNames`). 53 members total.

### builtins re-exports

Direct aliases of Nix `builtins`, re-exported so consumers depend only on gen-prelude:

```
all  any  attrNames  attrValues  concatLists  concatMap  concatStringsSep  elem
elemAt  filter  foldl'  functionArgs  genList  head  isAttrs  isFunction  isList
length  listToAttrs  map  mapAttrs  match  partition  sort  stringLength  substring
tail
```

Semantics are exactly those of the corresponding `builtins.*`.

### Vendored pure utilities

Behavior-identical copies of `nixpkgs.lib` helpers:

- `genAttrs names f` — attrset with each name in `names` mapped to `f name`.
- `nameValuePair name value` — `{ inherit name value; }` (pairs for `listToAttrs`).
- `optional cond x` — `[ x ]` if `cond` else `[ ]`.
- `optionalAttrs cond attrs` — `attrs` if `cond` else `{ }`.
- `optionalString cond s` — `s` if `cond` else `""`.
- `last xs` — final element (throws on `[ ]`).
- `init xs` — all but the final element (throws on `[ ]`).
- `setAttrByPath path value` — the nested attrset holding `value` at `path`; `[ ]` returns
  `value` unchanged. Throws `gen-prelude.setAttrByPath: path must be a list of strings` when
  `path` is not one.
- `getAttrByPath path attrs` — the value at `path`; `[ ]` returns `attrs` unchanged. Throws
  `gen-prelude.getAttrByPath: attribute path '<dotted>' not found` on a missing key or a
  non-attrset encountered mid-path, naming the whole requested path rather than the segment
  that failed. nixpkgs spells this one `getAttrFromPath` since its rename; the older name is
  kept for symmetry with the writer. Both refusals are **named and catchable**, where nixpkgs'
  is an uncatchable `abort` — fidelity for this pair is asserted on the happy path only.
- `unique xs` — order-preserving deduplication under structural `==`, first occurrence
  kept. Total on every value: ints, lists, attrsets and functions all work. Internally a
  guarded two-path — a list of strings routes to a linear key→first-index table, anything
  else to the original quadratic fold, retained deliberately because Nix has no total
  injective pure value→string key. See [Performance](#performance) for what each path
  costs and where the trade lies.
- `findFirst pred default list` — the first element satisfying `pred`, else `default`
  (nixpkgs `lib.findFirst`; `foldl'`-based, stack-safe, no early cutoff).
- `filterAttrs pred attrs` — attrset keeping entries where `pred name value`.
- `mapAttrsToList f attrs` — list of `f name value` over the attrset.
- `groupBy keyOf xs` — attrset grouping each element of `xs` under the string key
  `keyOf x`; each value is the list of elements sharing that key, in input order. A
  `builtins` re-export, not a vendored copy: the primop is linear where an accumulating
  fold rebuilds each group at every step.
- `concatMapStringsSep sep f xs` — `map f xs` joined by `sep`.
- `hasPrefix pre s` — whether `s` starts with `pre`.
- `imap0 f xs` — `map` with a 0-based index: `f index element`.
- `fix f` — least fixed point `let x = f x; in x`.
- `max a b` — the larger of two comparables.
- `range from to` — inclusive integer range (`[ ]` when `from > to`).
- `removePrefix pre s` — `s` with a leading `pre` stripped (unchanged if absent).

### Retired: `toposort`

`toposort` used to live here, vendored verbatim from `nixpkgs lib/lists.nix` along with its
internal `listDfs` and list-reverse helpers. It is gone. Ordering has one owner in the gen
ecosystem and it is [gen-graph](https://github.com/sini/gen-graph): use `gen-graph.topoOrder`,
which is Kahn 1962 over an accessor and returns `{ ok = true; order; }` or
`{ ok = false; cycles; }` rather than `{ result }` / `{ cycle; loops; }`.

Two guarantees went with the copy and are not reproduced anywhere: **byte-compatibility with
`nixpkgs lib.toposort`**, and the **polymorphism** that let it order integers and attrset
records directly. gen-graph's accessor is string-keyed; non-string nodes reach it through an
explicit `keyOf` projection. `sort` — the primitive comparator sort — stays here.

### gen-prelude-original (no nixpkgs equivalent)

Three helpers with no `nixpkgs.lib` counterpart, so they are covered by the
literal-expectation `prelude` suite rather than `prelude-fidelity`:

- `indexOf xs x` — first position of `x` in `xs` (structural `==`), or `-1` if absent.
  List-first arg order (`xs` then `x`), built on the same stack-safe first-match scan as
  `findFirst`.

- `iterateBounded strict step init bound` — `step` applied once per element of `bound`,
  returning the state after the last application. **The elements of `bound` are ignored**:
  only its length is read, as the bound on how many steps can be productive, so a caller
  passes a list it already holds and the loop allocates nothing of its own.

  The stack-safe encoding for a loop that carries state, as `findFirst`'s scan is for one
  that does not. A loop written as a self-applying lambda spends one evaluator frame per
  iteration — Nix does not reuse the frame of a tail call — so its descent depth is the
  iteration count and past `max-call-depth` it aborts with a stack overflow `tryEval`
  cannot catch; `foldl'` is a C-level loop whose frame cost is constant in the iteration
  count. Iterating a fixed number of times where a recursion would run to its own fixed
  point is sound on two properties the **caller** owes: at most `length bound` steps do
  work, and `step` is the identity once no work remains, so the surplus steps idle.

  `strict` names the loop-carried fields and is forced on every intermediate state.
  `foldl'` forces its accumulator only to WHNF — for a record, the record and not its
  fields — so a field left unforced accumulates a thunk chain as long as the loop, and
  forcing it at the end costs C stack: a second, distinct overflow that no
  `max-call-depth` setting bounds and that `tryEval` does not contain either. Pass
  `_: null` when there is nothing to force.

  ```nix
  # gen-graph's Kahn loop: the node-key list is the bound, and every accumulating field of
  # the state is what `strict` forces — `emitted` by its LENGTH, because forcing the spine
  # each step is what keeps its pending carries one deep rather than n.
  prelude.iterateBounded
    (st: builtins.seq st.base (builtins.seq st.residue (
      builtins.seq st.width (builtins.seq st.ready (
        builtins.seq st.count (builtins.length st.emitted))))))
    step
    { base = indeg0; residue = { }; width = 0; ready = heapOfSources; emitted = [ ]; count = 0; }
    keys
  ```

- `dedupByKey getKey list` — first-occurrence-wins dedup by `getKey x`, order-preserving.
  A `null` key is **always kept and never deduplicated** — the safe direction against
  silent cross-scope content-loss (a keyless element cannot be proven a duplicate, so a
  false-keep equal-merges harmlessly whereas a false-collapse silently drops distinct
  content). Vendored from den-hoag `lib/dedup-by-key.nix`. `getKey` must return a string
  or `null`: any other type is an interpreter type error at the attribute-name site, which
  `tryEval` does **not** catch.

## Testing

```sh
cd ci && nix flake check
```

The `ci/` directory is a separate flake (it pulls nixpkgs only to supply the `lib`
oracle the fidelity suite compares against — the lib itself pulls nothing). It runs
**114 tests across 2 suites**:

- **`prelude`** (48) — readable literal-expectation sanity checks (`genAttrs`, `unique`,
  `filterAttrs`, `fix`, the `toposort` retirement + its `sort` control, empty-list throw, `groupBy` basic +
  empty + collision-order stability, plus the gen-prelude-originals `dedupByKey`
  first-occurrence + null-keep + empty, `indexOf` present/absent/first, `findFirst`
  match/default, and `iterateBounded` count + ignored elements + empty bound + surplus-step
  idling + forced/unforced pair + stack safety at 20000 iterations + a guarded step carrying
  a field `strict` does not name, at 100000). The `iterateBounded` arms that must FAIL — a
  self-applying loop at the same size, and that last loop with its guard deleted — are not
  here: a stack overflow is an uncatchable abort, so no in-language assertion observes it,
  and the red arms are shell commands.

  `unique`'s two-path carries its own group: first-occurrence ORDER (including two traps
  that a construction sorting keys rather than indices fails); STRING CONTEXT (a
  context-carrying string is a legal element and an illegal attribute name, so this arm
  fails as an uncatchable abort rather than a wrong answer, and no other arm sees it);
  NON-STRING ROUTING over ints, lists, attrsets, a mixed list and a 24-element attrset
  list, each asserted element-for-element against the incumbent expression rather than
  merely "does not throw"; and STRICTNESS PARITY over 14 value classes via
  `tryEval ∘ length`, the only instrument that observes how much a construction forces —
  every arm comparing under `==` forces both sides and is structurally blind to it. The
  load-bearing case is `unique [ (throw "BOOM") ]` ⇒ 1, not an abort. `dedupByKey` adds
  null-keep at EQUAL content, order across a mixed keyed/unkeyed input, and stack safety
  at 50,000 elements.

- **`prelude-fidelity`** (66) — the load-bearing guard: for every nixpkgs-vendored
  utility, `prelude.X input == lib.X input` over normal and boundary inputs (empty lists,
  absent prefixes, reversed ranges, cycles). This is what keeps the vendored copies
  byte-behavior-identical to nixpkgs `lib`. (`indexOf` is additionally cross-checked
  against `lib.lists.findFirstIndex`; `dedupByKey` has no nixpkgs oracle and lives only in
  the `prelude` suite. `groupBy` has no arm here either — it is a `builtins` re-export, and
  nixpkgs' own `lib.groupBy` is `builtins.groupBy or (…)`, so a fidelity arm over it would
  compare the primop with itself.)

  Eighteen of those arms are `escapeRegex`'s metacharacter set, which gets per-member
  coverage rather than a table of representative cases: which member is wrong decides which
  needle notices, so a sample cannot see it. Twelve `test-escset-*` arms cover a member
  DROPPED (the needle stops being quoted and becomes a pattern — eight flip the boolean,
  four raise); `test-escapeRegex-printable-ascii` covers a member ADDED, by byte-identity
  against `lib.escapeRegex` over all 95 printable ASCII characters. The remaining five hold
  `]` to being a NON-member from both sides — escaping it emits `\]`, which the regex engine
  rejects, so the needle aborts where nixpkgs answers, and `tryEval` does not catch it.

There is no separate `purity` suite because purity is structural: the lib flake declares
no inputs, so there is no `nixpkgs.lib` in scope to accidentally depend on.

## Performance

Two functions here have costs worth knowing before you reach for them. Both are stated in
two variables, because one variable hides the answer: **N** is the list length and **K** the
distinct-element count, `1 ≤ K ≤ N`.

`unique` is a guarded two-path. A list of **strings** builds a key→first-index table in one
pass and costs `2N + 3K + 3` list elements — linear in both variables. Anything else takes
the original fold, which costs `K(K+1)/2 + K + N + 2`: **quadratic in K, not in N**, because
`acc ++ [ x ]` copies the whole accumulator on each of the K first-sightings. The append is
the cost, not the membership test — which is why swapping in an O(1) attrset lookup while
keeping the append changes nothing.

That makes the trade explicit rather than uniform:

| shape | which path wins | measured |
|---|---|---|
| K ≈ N (all-distinct) | string path, by a lot | 8,010,002 → 20,003 elements at N = K = 4,000 |
| N ≈ 2K (an endpoint union over an edge list) | string path | 23.3× fewer at N = 640, 91.9× at N = 2,560, doubling with every doubling |
| K ≪ N (few distinct values, long list) | the fold | string path converges to exactly 2.00× more allocation, and time drifts as `log N / K` — measured +29.5% at N = 400,000, K = 8 |

The string path is chosen whenever it applies because the K ≪ N penalty is bounded at 2.00×
while the K ≈ N saving is unbounded and grows with input size. If you are deduplicating a
long list with very few distinct values and it is hot, that is the one case where this
library is knowingly slower than it was, and the reason is in the table.

The **non-string fold is not a leftover**. There is no total, injective, pure value→string
key in Nix — `builtins.toJSON` is not one, since it aborts on functions and forces deeply —
so a non-string list has no index table to build at all, and the fold is what keeps `unique`
total on ints, lists, attrsets and functions. The guard is per-**list**, not per-element: a
mixed list routes whole to the fold.

`dedupByKey` is linear (`5N + 3`) and frame-flat. It previously used a non-tail `[ x ] ++ go … rest` recursion, which was quadratic **in N** whatever the distinct count and, worse, spent
one evaluator frame per element — so it aborted uncatchably past `max-call-depth` at around
10,000 elements. Every step is now a primop, so there is no descent left to overflow.

## Provenance

gen-prelude has no research lineage — it is plumbing, with one exception: `iterateBounded`
is an encoding decision rather than a copy, and its rationale is stated with it above.
The `builtins` members are direct
re-exports of the Nix `builtins` set. The vendored utilities are copied
behavior-identically from `nixpkgs` `lib`:

| Utility | nixpkgs source |
|---------|----------------|
| `genAttrs`, `filterAttrs`, `mapAttrsToList`, `nameValuePair`, `optionalAttrs` | `lib/attrsets.nix` |
| `optional`, `last`, `init`, `unique`, `imap0`, `range`, `findFirst` | `lib/lists.nix` |
| `optionalString`, `concatMapStringsSep`, `hasPrefix`, `removePrefix` | `lib/strings.nix` |
| `fix`, `max` | `lib/trivial.nix` / `lib/fixed-points.nix` |

The `prelude-fidelity` test suite asserts each utility stays
behavior-identical to its `nixpkgs.lib` original, so the vendoring cannot silently
drift.

Three members are **gen-prelude-original** (no nixpkgs origin), so they are held by the
literal-expectation `prelude` suite rather than `prelude-fidelity`:

| Utility | origin |
|---------|--------|
| `indexOf` | gen-prelude-original — small list helper (den-hoag hand-roll shape); shares the internal stack-safe `findFirstIndex` scan (`lib/lists.nix:575`) that also backs `findFirst` |
| `iterateBounded` | gen-prelude-original — the stack-safe loop encoding for state a scan cannot carry; nothing was vendored, so there is no fidelity oracle to hold it against |
| `dedupByKey` | vendored from den-hoag `lib/dedup-by-key.nix` (itself the port of v1 scope-walk `dedupByKey`); null-keep semantics have no `nixpkgs.lib` counterpart |

## License

MIT — see `LICENSE`.
