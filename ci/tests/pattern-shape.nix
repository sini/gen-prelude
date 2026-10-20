# `patternOf` (den-hoag-gtwxg U1): the shape of a function's pattern, read through the one XML
# binding in `lib/pattern-shape.nix`. Every expectation below is written by hand, not derived from
# the reader. `tests` holds the values and the rendering pin; `testsError` pins each refusal by name,
# including the four perturbed renderings that show the parse refuses rather than misreads. The
# unit file is imported directly for its `parse`, which `lib/default.nix` does not publish
# (den-hoag-gtwxg C2).
{ genPrelude, ... }:
let
  inherit (genPrelude) door patternOf;
  inherit (import ../../lib/pattern-shape.nix { inherit (genPrelude) isFunction functionArgs; })
    parse
    ;

  # A lambda with `n` formals and an ellipsis. Nix has no way to build a pattern from a value, so the
  # source is written out and imported.
  manyFormals =
    n:
    import (
      builtins.toFile "many-formals.nix" "{ ${
        genPrelude.concatMapStringsSep ", " (i: "a${toString i}") (builtins.genList (i: i) n)
      }, ... }: 1"
    );
  # A set pattern whose `@`-name is longer than the parse's prefix, so its head cannot close inside it.
  longName = import (
    builtins.toFile "long-name.nix" "${
      builtins.concatStringsSep "" (builtins.genList (_: "x") 1100)
    }@{ a }: a"
  );

  openXml = builtins.toXML ({ a, ... }: a);
  perturb = from: to: builtins.replaceStrings [ from ] [ to ] openXml;
  refusal = msg: {
    type = "ThrownError";
    msg = "^gen-prelude[.]patternOf: ${msg}$";
  };
  notParsed = refusal "the function's XML rendering is not a form this reader parses";
in
{
  flake.tests.pattern-shape = {
    test-named = {
      expr = patternOf (x: x);
      expected = {
        kind = "named";
        ellipsis = false;
        formals = { };
      };
    };
    test-empty-set = {
      expr = patternOf ({ }: 1);
      expected = {
        kind = "set";
        ellipsis = false;
        formals = { };
      };
    };
    test-closed-set = {
      expr = patternOf ({ a }: a);
      expected = {
        kind = "set";
        ellipsis = false;
        formals = {
          a = false;
        };
      };
    };
    test-open-set = {
      expr = patternOf ({ a, ... }: a);
      expected = {
        kind = "set";
        ellipsis = true;
        formals = {
          a = false;
        };
      };
    };
    test-open-set-with-default = {
      expr = patternOf (
        {
          a ? 1,
          ...
        }:
        a
      );
      expected = {
        kind = "set";
        ellipsis = true;
        formals = {
          a = true;
        };
      };
    };
    test-ellipsis-only = {
      expr = patternOf ({ ... }: 1);
      expected = {
        kind = "set";
        ellipsis = true;
        formals = { };
      };
    };
    test-at-pattern = {
      expr = patternOf (args@{ a, ... }: args);
      expected = {
        kind = "set";
        ellipsis = true;
        formals = {
          a = false;
        };
      };
    };
    test-empty-set-at-pattern = {
      expr = patternOf ({ }@args: args);
      expected = {
        kind = "set";
        ellipsis = false;
        formals = { };
      };
    };
    # The rendering carries the pattern and never a default, so a default that spells the ellipsis's
    # own rendering cannot leak into the reading.
    test-a-default-cannot-leak = {
      expr = patternOf (
        {
          a ? "<attrspat ellipsis=\"1\">",
        }:
        a
      );
      expected = {
        kind = "set";
        ellipsis = false;
        formals = {
          a = true;
        };
      };
    };
    # A curried lambda reads its first step only.
    test-curried = {
      expr = patternOf (x: { a, ... }: a);
      expected = {
        kind = "named";
        ellipsis = false;
        formals = { };
      };
    };
    test-functor-over-a-set-pattern = {
      expr = patternOf { __functor = self: { a, ... }: a; };
      expected = {
        kind = "set";
        ellipsis = true;
        formals = {
          a = false;
        };
      };
    };
    # The published map is the formals; the applied lambda is the kind.
    test-functor-publishing-functionArgs = {
      expr = patternOf {
        __functor = self: x: x;
        __functionArgs = {
          a = false;
        };
      };
      expected = {
        kind = "named";
        ellipsis = false;
        formals = {
          a = false;
        };
      };
    };
    # A door is read by its call syntax, not its `__contract`.
    test-door = {
      expr = patternOf (
        door {
          name = "probe";
          required = [ "a" ];
        } (r: r.a)
      );
      expected = {
        kind = "named";
        ellipsis = false;
        formals = {
          a = false;
        };
      };
    };
    test-primop = {
      expr = map patternOf [
        builtins.map
        (builtins.map (x: x))
      ];
      expected = [
        {
          kind = "primop";
          ellipsis = false;
          formals = { };
        }
        {
          kind = "primop";
          ellipsis = false;
          formals = { };
        }
      ];
    };
    # Thousands of formals are served: the head is read inside a bounded prefix, where a `.*` over
    # the whole rendering overflows the C stack on Determinate from about 4000.
    test-many-formals = {
      expr =
        let
          p = patternOf (manyFormals 5000);
        in
        {
          inherit (p) kind ellipsis;
          formals = builtins.length (builtins.attrNames p.formals);
        };
      expected = {
        kind = "set";
        ellipsis = true;
        formals = 5000;
      };
    };

    # THE RENDERING `parse` RELIES ON, pinned literally. An evaluator that changes it reds this cell
    # by name before any reader misreads.
    test-rendering-pin = {
      expr = map builtins.toXML [
        (x: x)
        ({ a, ... }: a)
        (args@{ a, ... }: args)
        builtins.map
      ];
      expected = [
        "<?xml version='1.0' encoding='utf-8'?>\n<expr>\n  <function>\n    <varpat name=\"x\" />\n  </function>\n</expr>\n"
        "<?xml version='1.0' encoding='utf-8'?>\n<expr>\n  <function>\n    <attrspat ellipsis=\"1\">\n      <attr name=\"a\" />\n    </attrspat>\n  </function>\n</expr>\n"
        "<?xml version='1.0' encoding='utf-8'?>\n<expr>\n  <function>\n    <attrspat ellipsis=\"1\" name=\"args\">\n      <attr name=\"a\" />\n    </attrspat>\n  </function>\n</expr>\n"
        "<?xml version='1.0' encoding='utf-8'?>\n<expr>\n  <unevaluated />\n</expr>\n"
      ];
    };
    # The control for the perturbed renderings below: the unperturbed one parses.
    test-parse-control = {
      expr = parse openXml;
      expected = {
        kind = "set";
        ellipsis = true;
      };
    };
  };

  flake.testsError.pattern-shape = {
    test-refuses-a-non-function = {
      expr = patternOf 1;
      expectedError = refusal "the argument is not a function by prelude[.]isFunction [(]its type is int[)]";
    };
    test-refuses-a-functor-yielding-a-non-function = {
      expr = patternOf { __functor = self: 1; };
      expectedError = refusal "the argument is not a function by prelude[.]isFunction [(]its type is set[)]";
    };
    # The call protocol would apply this nested functor, but `prelude.isFunction` reads it as no
    # function, and the refusal says so in those words.
    test-refuses-a-nested-functor = {
      expr = patternOf { __functor = self: { __functor = self: x: x; }; };
      expectedError = refusal "the argument is not a function by prelude[.]isFunction [(]its type is set[)]";
    };
    test-refuses-a-malformed-functionArgs = {
      expr = patternOf {
        __functor = self: x: x;
        __functionArgs = {
          a = 1;
        };
      };
      expectedError = refusal "the functor's `__functionArgs` is not an attrset of booleans";
    };
    test-refuses-a-head-outside-the-prefix = {
      expr = patternOf longName;
      expectedError = refusal "the head of the function's XML rendering is not inside its first 1024 characters";
    };
    test-parse-refuses-an-ellipsis-spelling = {
      expr = parse (perturb "ellipsis=\"1\"" "ellipsis=\"true\"");
      expectedError = notParsed;
    };
    test-parse-refuses-an-extra-attribute = {
      expr = parse (perturb "<attrspat ellipsis=\"1\">" "<attrspat ellipsis=\"1\" extra=\"x\">");
      expectedError = notParsed;
    };
    test-parse-refuses-a-renamed-element = {
      expr = parse (perturb "attrspat" "setpat");
      expectedError = notParsed;
    };
    test-parse-refuses-a-renamed-function = {
      expr = parse (perturb "<function>" "<lambda>");
      expectedError = notParsed;
    };
  };
}
