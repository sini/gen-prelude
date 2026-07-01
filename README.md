# gen-prelude — vendored, nixpkgs-lib-free utilities for the gen ecosystem

[![CI](https://github.com/sini/gen-prelude/actions/workflows/ci.yml/badge.svg)](https://github.com/sini/gen-prelude/actions/workflows/ci.yml) [![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT) [![Sponsor](https://img.shields.io/badge/Sponsor-%E2%9D%A4-pink?logo=github)](https://github.com/sponsors/sini)

The small pure-utility dependency that lets the pure gen substrate drop `nixpkgs.lib`.
It is `builtins` re-exports plus the handful of pure utilities (`genAttrs`, `unique`,
`filterAttrs`, `fix`, `optional`, `toposort`, …) the substrate uses, vendored
behavior-identically from nixpkgs `lib`.

**Not** a type system, **not** a module-system shim — only general pure utilities. The
`lib.types` / `mkOption` / `evalModules` tier is a separate concern (a Korora-class
replacement) and out of scope here.

Dependency class: **A (pure)** — the lib takes no flake inputs and imports nothing from
`nixpkgs.lib`; it is the nixpkgs-lib-free base every other pure gen lib depends on. The
lib flake carries zero inputs, so a consumer's lock gains no transitive nixpkgs
dependency from pulling gen-prelude in. Purity is enforced structurally (the flake has
no inputs to draw a `lib` from), and every vendored utility is held byte-behavior
-identical to its nixpkgs counterpart by the `prelude-fidelity` test suite.

## Table of Contents

- [Overview](#overview)
- [Gen Ecosystem](#gen-ecosystem)
- [Usage](#usage)
- [API Reference](#api-reference)
- [Testing](#testing)
- [Provenance](#provenance)

## Overview

gen-prelude is a single attrset of pure functions — no inputs, no functor. Two kinds of
member:

- **`builtins` re-exports** — direct aliases of Nix `builtins` (`map`, `filter`,
  `foldl'`, `genList`, `partition`, …), grouped under one name so consumers need not
  reach into `builtins` themselves.
- **Vendored pure utilities** — the small set of `nixpkgs.lib` helpers the gen substrate
  actually uses (`genAttrs`, `filterAttrs`, `unique`, `fix`, `toposort`, …), copied here
  so the pure gen libraries can depend on gen-prelude instead of `nixpkgs.lib`. Each is
  behavior-identical to its `lib.*` original; `toposort` (with its `listDfs` / list-
  reverse helpers) is copied verbatim so its `{ result } | { cycle; loops }` contract
  matches nixpkgs exactly.

The mental model: wherever a pure gen lib would have written `lib.X`, it writes
`prelude.X` instead and gets identical semantics with no `nixpkgs.lib` in its closure.
Downstream libraries — gen-graph (`phaseOrder` over condensation), gen-vars, gen-scope,
gen-dispatch, and others — build on exactly this surface.

## Gen Ecosystem

| Library | Role |
|---------|------|
| [gen-prelude](https://github.com/sini/gen-prelude) | **This lib** — pure nixpkgs-lib-free utility base (builtins re-exports + vendored lib utils) |
| [gen-algebra](https://github.com/sini/gen-algebra) | Pure primitives (record, search monad, either, intensional identity) |
| [gen-schema](https://github.com/sini/gen-schema) | Typed registries (kinds, instances, collections, refs) |
| [gen-aspects](https://github.com/sini/gen-aspects) | Aspect type system (traits, classification, dispatch) |
| [gen-scope](https://github.com/sini/gen-scope) | HOAG scope-graph evaluator (demand-driven, \_eval memoization, circular attributes) |
| [gen-graph](https://github.com/sini/gen-graph) | Accessor-based graph query combinators (traversal, condensation, phaseOrder) |
| [gen-select](https://github.com/sini/gen-select) | Selector algebra (pattern matching over graph positions) |
| [gen-bind](https://github.com/sini/gen-bind) | Module binding (inject external args into NixOS modules) |
| [gen-dispatch](https://github.com/sini/gen-dispatch) | Relational rule dispatch STEP (stratified phases, conflict resolution) |
| [gen-resolve](https://github.com/sini/gen-resolve) | Demand-driven RAG evaluator over scope graphs (attribute schedule + convergence loop) |
| [gen-rebuild](https://github.com/sini/gen-rebuild) | Pure-Nix incremental rebuilder (change propagation, AFFECTED set) |
| [gen-vars](https://github.com/sini/gen-vars) | Pure-Nix vars/secrets (den-agnostic) |

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
`nix eval .#lib --apply builtins.attrNames`). 45 members total.

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
- `unique xs` — order-preserving deduplication.
- `filterAttrs pred attrs` — attrset keeping entries where `pred name value`.
- `mapAttrsToList f attrs` — list of `f name value` over the attrset.
- `concatMapStringsSep sep f xs` — `map f xs` joined by `sep`.
- `hasPrefix pre s` — whether `s` starts with `pre`.
- `imap0 f xs` — `map` with a 0-based index: `f index element`.
- `fix f` — least fixed point `let x = f x; in x`.
- `max a b` — the larger of two comparables.
- `range from to` — inclusive integer range (`[ ]` when `from > to`).
- `removePrefix pre s` — `s` with a leading `pre` stripped (unchanged if absent).
- `toposort before list` — partial-order topological sort. Returns `{ result = sorted; }`
  or, on a cycle, `{ cycle; loops; }` — identical to `nixpkgs lib.toposort`. Copied
  verbatim (with its internal `listDfs` / list-reverse helpers) so the contract matches
  nixpkgs exactly; consumers such as gen-graph's `phaseOrder` and gen-vars rely on the
  `? result` discriminant.

## Testing

```sh
cd ci && nix flake check
```

The `ci/` directory is a separate flake (it pulls nixpkgs only to supply the `lib`
oracle the fidelity suite compares against — the lib itself pulls nothing). It runs
**41 tests across 2 suites**:

- **`prelude`** (7) — readable literal-expectation sanity checks (`genAttrs`, `unique`,
  `filterAttrs`, `fix`, `toposort` result + cycle, empty-list throw).
- **`prelude-fidelity`** (34) — the load-bearing guard: for every vendored utility,
  `prelude.X input == lib.X input` over normal and boundary inputs (empty lists, absent
  prefixes, reversed ranges, cycles). This is what keeps the vendored copies
  byte-behavior-identical to nixpkgs `lib`.

There is no separate `purity` suite because purity is structural: the lib flake declares
no inputs, so there is no `nixpkgs.lib` in scope to accidentally depend on.

## Provenance

gen-prelude has no research lineage — it is plumbing. The `builtins` members are direct
re-exports of the Nix `builtins` set. The vendored utilities are copied
behavior-identically from `nixpkgs` `lib`:

| Utility | nixpkgs source |
|---------|----------------|
| `genAttrs`, `filterAttrs`, `mapAttrsToList`, `nameValuePair`, `optionalAttrs` | `lib/attrsets.nix` |
| `optional`, `last`, `init`, `unique`, `imap0`, `range`, `toposort` (+ `listDfs`) | `lib/lists.nix` |
| `optionalString`, `concatMapStringsSep`, `hasPrefix`, `removePrefix` | `lib/strings.nix` |
| `fix`, `max` | `lib/trivial.nix` / `lib/fixed-points.nix` |

`toposort` is copied verbatim so its `{ result } | { cycle; loops }` contract matches
nixpkgs exactly. The `prelude-fidelity` test suite asserts each utility stays
behavior-identical to its `nixpkgs.lib` original, so the vendoring cannot silently
drift.

## License

MIT — see `LICENSE`.
