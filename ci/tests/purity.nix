# PURITY INVARIANT: gen-prelude's library source is `builtins` and nothing else. This is the base
# library — 18 consumers sit on it, and it is the dependency that lets every one of them drop
# `nixpkgs.lib` — so a stray `lib.foo` / `evalModules` / nixpkgs reference creeping in here is not a
# local defect but a tether re-acquired by the whole ecosystem, transitively and silently.
#
# Scope: `lib/**.nix` plus the root `default.nix` — the library and its non-flake entry. NOT `ci/`,
# where the harness legitimately uses nixpkgs lib (including, here, to run this scan). The root
# `flake.nix` is held by a structural cell below rather than by the token scan: a token ban over it
# fires on its own `description`, which is the true sentence "nixpkgs-lib-free", and stripping
# comments cannot help because that string is code. What the flake can actually get wrong is
# DECLARING A DEPENDENCY, and the attribute-set cell states that directly.
#
# ★ THE SCANNER IS THIS LIBRARY'S OWN `hasInfix`, scanning this library. nixpkgs `lib.hasInfix`
# overflows the C stack on whole-file source (its `.*needle.*` recurses to depth ∝ string length),
# which is why every purity suite in the ecosystem takes `genPrelude.hasInfix` — and here that makes
# the instrument a part of the subject. A `hasInfix` broken to always answer false would report this
# library clean; the detector cell is what sees that, because the same call has to FIRE on a planted
# violation in the same run.
{ genPrelude, lib, ... }:
let
  libDir = ../../lib;

  # Drop everything from the first `#` on each line. Sound while no `#` occurs inside a string
  # literal in the scanned source — measured true of both files here, neither of which carries a
  # `''…''` block at all.
  stripComments =
    text:
    lib.concatStringsSep "\n" (
      map (line: lib.head (lib.splitString "#" line)) (lib.splitString "\n" text)
    );

  # Labels are repo-root-relative: a red CI's only product is its message, and a path value renders
  # as the store copy the flake was evaluated from, naming a file no reader can open.
  entries =
    map (name: {
      name = "lib/${name}";
      path = libDir + "/${name}";
    }) (lib.filter (lib.hasSuffix ".nix") (lib.attrNames (builtins.readDir libDir)))
    ++ [
      {
        name = "default.nix";
        path = ../../default.nix;
      }
    ];

  # Two stages off one read: the strip's effect is a property of this library's source rather than a
  # courtesy, so the raw text has to stay available to assert it.
  rawSources = map (e: {
    inherit (e) name;
    code = builtins.readFile e.path;
  }) entries;
  sources = map (s: {
    inherit (s) name;
    code = stripComments s.code;
  }) rawSources;

  # Tokens signalling a nixpkgs-lib tether or the module-system (Korora-class) tier.
  forbidden = [
    "nixpkgs" # a nixpkgs flake input / reference
    "lib." # any nixpkgs lib call (lib.types, lib.genAttrs, …)
    "{ lib }" # the old `{ lib }` parameter signature
    "{ lib," # `{ lib, … }` parameter signature
    "evalModules" # module-system tier
    "mkOption" # module-system tier
  ];

  scan =
    srcs:
    lib.concatMap (
      src:
      map (tok: "${src.name}: '${tok}'") (lib.filter (tok: genPrelude.hasInfix tok src.code) forbidden)
    ) srcs;

  # A synthetic poisoned source — NOT written to disk, so the real scan stays green while the
  # detector is shown to have teeth. Its label is bracketed so it cannot be read as a real path.
  poisoned = {
    name = "<injected>";
    code = stripComments "  foo = mkOption { type = lib.types.str; }; # nixpkgs, in a comment";
  };
in
{
  # The library is clean. That `[ ]` is not evidence by itself — a scan over no files, or over dead
  # text, produces it just as readily — and the three cells below are what make it mean something.
  flake.tests.purity.test-library-source-is-builtins-only = {
    expr = scan sources;
    expected = [ ];
  };

  # WHICH files the scan reads, pinned at the `readDir` rather than after the `.nix` filter, so the
  # subject is total: a subdirectory added under `lib/` — which the flat read would not descend into
  # and the filter would silently drop — arrives here as a RED instead of as unscanned code. This
  # library is one file on purpose; growing it is a decision that gets looked at.
  flake.tests.purity.test-scan-subject-is-the-library-tree = {
    expr = builtins.readDir libDir;
    expected = {
      "default.nix" = "regular";
    };
  };

  # THE DEPENDENCY BUDGET IS ZERO, pinned as the flake's own attribute names rather than as a token
  # ban. gen-prelude declares no inputs at all, so a consumer's lock gains no transitive node from
  # pinning it; an `inputs` attribute appearing here is exactly the breach, and it cannot appear
  # without changing this list.
  flake.tests.purity.test-flake-declares-no-inputs = {
    expr = builtins.attrNames (import ../../flake.nix);
    expected = [
      "description"
      "outputs"
    ];
  };

  # THE DETECTOR FIRES, on the same corpus the invariant cell reports clean, by the same call. The
  # expectation is the violation LIST rather than merely that something was found: a detector firing
  # on the wrong token, or whose `file: 'tok'` message has decayed into something a reader cannot act
  # on off a red CI, is broken in the way that matters and non-emptiness passes both. Its first half
  # also restates that the real sources contribute nothing.
  flake.tests.purity.test-control-detector-catches-planted-violation = {
    expr = scan (sources ++ [ poisoned ]);
    expected = [
      "<injected>: 'lib.'"
      "<injected>: 'mkOption'"
    ];
  };

  # THE STRIP IS LOAD-BEARING, AND IT IS THIS LIBRARY'S OWN DOCUMENTATION THAT MAKES IT SO: the
  # header of `lib/default.nix` states — truly — that the library is nixpkgs-lib-free and that the
  # `lib.types`/`mkOption`/`evalModules` tier is out of scope. Every one of those is a forbidden
  # token. Run over the RAW text the invariant cell reds on true prose, which is how a scan gets
  # weakened at its token list by whoever meets it next.
  #
  # So this cell carries two things at once, over the real subject: the strip is what makes the
  # green above a statement about code, and the reads are LIVE — an emptied or constant `readFile`
  # cannot produce this list, and neither can a scan pointed at some other tree.
  flake.tests.purity.test-control-strip-is-load-bearing-over-live-source = {
    expr = scan rawSources;
    expected = [
      "lib/default.nix: 'nixpkgs'"
      "lib/default.nix: 'lib.'"
      "lib/default.nix: 'evalModules'"
      "lib/default.nix: 'mkOption'"
    ];
  };
}
