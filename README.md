# gen-prelude — vendored, nixpkgs-lib-free utilities for the gen ecosystem

[![CI](https://github.com/sini/gen-prelude/actions/workflows/ci.yml/badge.svg)](https://github.com/sini/gen-prelude/actions/workflows/ci.yml) [![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT) [![Sponsor](https://img.shields.io/badge/Sponsor-%E2%9D%A4-pink?logo=github)](https://github.com/sponsors/sini)

The small pure-utility dependency that lets the pure gen substrate drop `nixpkgs.lib`.
`builtins` re-exports plus the handful of pure utilities (`genAttrs`, `unique`,
`filterAttrs`, `fix`, `optional`, …) the substrate uses, vendored behavior-identically
from nixpkgs lib.

**Not** a type system, **not** a module-system shim — only general pure utilities. The
`lib.types` / `mkOption` / `evalModules` tier is a separate concern (a Korora-class
replacement) and out of scope here.

## Gen Ecosystem

| Library | Role |
|---------|------|
| [gen-prelude](https://github.com/sini/gen-prelude) | **This lib** — vendored pure utilities; the nixpkgs-lib-free base |
| [gen-algebra](https://github.com/sini/gen-algebra) | Pure primitives (search, record, identity) |
| [gen-schema](https://github.com/sini/gen-schema) | Typed record registry (extension points over the module system) |
| [gen-aspects](https://github.com/sini/gen-aspects) | Aspect-oriented composition types |
| [gen-graph](https://github.com/sini/gen-graph) | Accessor-based graph query combinators |
| [gen-scope](https://github.com/sini/gen-scope) | Scope graphs (construction, resolution, eval) |
| [gen-select](https://github.com/sini/gen-select) | Selector algebra over graph positions |
| [gen-derive](https://github.com/sini/gen-derive) | Stratified rule dispatch |
| [gen-bind](https://github.com/sini/gen-bind) | Module argument binding |

## Usage

```nix
# As a flake input (inputs.gen-prelude.url = "github:sini/gen-prelude"):
let
  prelude = inputs.gen-prelude.lib; # or `inputs.gen-prelude { }` (the flake is a functor)
in
prelude.genAttrs [ "a" "b" ] (n: n + "!") # => { a = "a!"; b = "b!"; }

# Or import the path directly:  import "${inputs.gen-prelude}/lib" { }
```

The lib takes no inputs — it is `builtins` aliases plus vendored pure utilities.
Consumers depend on `gen-prelude` instead of `nixpkgs.lib`.

## Surface

- **builtins re-exports** (aliases): `all` `any` `attrNames` `attrValues` `concatLists`
  `concatStringsSep` `elem` `elemAt` `filter` `foldl'` `functionArgs` `genList` `head`
  `isAttrs` `isFunction` `isList` `length` `listToAttrs` `map` `mapAttrs` `match` `sort`
  `stringLength` `substring` `tail`.
- **vendored pure utilities:** `genAttrs` `nameValuePair` `concatMap` `optional`
  `optionalAttrs` `optionalString` `last` `init` `unique` `filterAttrs` `mapAttrsToList`
  `concatMapStringsSep` `hasPrefix` `imap0` `fix` `max` `range` `removePrefix`.

## Status

Initial scaffold (2026-06-26). `toposort` is a vendoring **TODO** — copy nixpkgs
`lib.toposort` verbatim before any consumer (gen-derive / gen-vars) migrates onto it.
Surface, vendor strategy, and the per-lib migration plan live in the gen-prelude design
spec (`den-architecture/gen-specs/gen-prelude/`).

## Testing

```sh
cd ci && nix flake check
```
