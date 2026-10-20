# `patternOf` (den-hoag-gtwxg U1): the shape of a function's pattern, read through the one XML
# binding in `lib/pattern-shape.nix`. Every expectation below is written by hand, not derived from
# the reader. `tests` holds the values and the rendering pin; `testsError` pins each refusal by name,
# including the perturbed renderings that show the parse refuses rather than misreads, each in a
# short form the prefix decides and a long form the skeleton decides. The unit file is imported
# directly for its `parse`, which `lib/default.nix` does not publish (den-hoag-gtwxg C2).
{ genPrelude, ... }:
let
  inherit (genPrelude) door patternOf;
  inherit (import ../../lib/pattern-shape.nix { inherit (genPrelude) isFunction functionArgs; })
    parse
    ;

  # Nix has no way to build a pattern from a value, so a fixture's source is written out and imported.
  src = text: import (builtins.toFile "fixture.nix" text);
  name = n: builtins.concatStringsSep "" (builtins.genList (_: "x") n);
  formalsList =
    n: genPrelude.concatMapStringsSep ", " (i: "a${toString i}") (builtins.genList (i: i) n);
  # A lambda with `n` formals and an ellipsis.
  manyFormals = n: src "{ ${formalsList n}, ... }: 1";
  # A set pattern whose `@`-name is longer than the parse's prefix, so its head cannot close inside it.
  longName = src "${name 1100}@{ a }: a";
  # A name of `n` characters in each of the seven places a pattern carries one, and the shape each
  # is read as.
  namedIn = n: [
    (src "${name n}: 1")
    (src "${name n}@{ a }: 1")
    (src "{ a }@${name n}: 1")
    (src "${name n}@{ ... }: 1")
    (src "{ a, ... }@${name n}: 1")
    (src "{ ${name n} }: 1")
    (src "{ ${name n}, ... }: 1")
  ];
  namedInExpected = [
    {
      kind = "named";
      ellipsis = false;
    }
    {
      kind = "set";
      ellipsis = false;
    }
    {
      kind = "set";
      ellipsis = false;
    }
    {
      kind = "set";
      ellipsis = true;
    }
    {
      kind = "set";
      ellipsis = true;
    }
    {
      kind = "set";
      ellipsis = false;
    }
    {
      kind = "set";
      ellipsis = true;
    }
  ];
  shapeOf = p: { inherit (p) kind ellipsis; };
  malformed = {
    __functor = self: x: x;
    __functionArgs = {
      a = 1;
    };
  };

  openXml = builtins.toXML ({ a, ... }: a);
  atXml = builtins.toXML (args@{ a, ... }: args);
  closedAtXml = builtins.toXML (args@{ a }: args);
  namedXml = builtins.toXML (x: x);
  emptyOpenXml = builtins.toXML ({ ... }: 1);
  perturb = perturbIn openXml;
  perturbIn =
    xml: from: to:
    builtins.replaceStrings [ from ] [ to ] xml;
  # The long form of a rendering: every name 2000 characters and 200 quoted formals appended, so it
  # is longer than the prefix and a perturbed head is decided by the skeleton.
  lengthen =
    xml:
    builtins.replaceStrings [ "name=\"args" "name=\"x" ] [ "name=\"${name 2000}" "name=\"${name 2000}" ]
      xml
    + builtins.concatStringsSep "" (
      builtins.genList (i: "\n      <attr name=\"p${toString i}\" />") 200
    );
  # Each further perturbation of the head, `[ base from to ]`, refused in both forms below.
  perturbations = {
    # the order an insertion-ordered writer would emit (the renderer inserts `name` first)
    reorder = [
      atXml
      "<attrspat ellipsis=\"1\" name=\"args\">"
      "<attrspat name=\"args\" ellipsis=\"1\">"
    ];
    ellipsis-after-a-closed-name = [
      closedAtXml
      "name=\"args\">"
      "name=\"args\" ellipsis=\"1\">"
    ];
    extra-attribute-after-a-name = [
      atXml
      "name=\"args\">"
      "name=\"args\" extra=\"x\">"
    ];
    unterminated-name = [
      atXml
      "name=\"args\">"
      "name=\"args>"
    ];
    varpat-not-self-closing = [
      namedXml
      "<varpat name=\"x\" />"
      "<varpat name=\"x\">"
    ];
    self-closing-attrspat-with-a-name = [
      atXml
      "name=\"args\">"
      "name=\"args\" />"
    ];
    self-closing-attrspat-with-ellipsis-only = [
      emptyOpenXml
      "<attrspat ellipsis=\"1\">"
      "<attrspat ellipsis=\"1\" />"
    ];
    empty-ellipsis = [
      openXml
      "ellipsis=\"1\""
      "ellipsis=\"\""
    ];
    a-2000-character-ellipsis-value = [
      openXml
      "ellipsis=\"1\""
      "ellipsis=\"${name 2000}\""
    ];
  };
  perturbedCells =
    form: long:
    builtins.listToAttrs (
      map (
        k:
        let
          q = perturbations.${k};
          xml = perturbIn (builtins.elemAt q 0) (builtins.elemAt q 1) (builtins.elemAt q 2);
        in
        {
          name = "test-parse-refuses-${form}-${k}";
          value = {
            expr = parse (if long then lengthen xml else xml);
            expectedError = notParsed;
          };
        }
      ) (builtins.attrNames perturbations)
    );
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

    # Twenty thousand formals behind an `@`-name longer than the prefix: the head is read from the
    # skeleton of a rendering of about 570,000 characters with 40,000 quotes, never by a regex over it.
    test-many-formals-behind-a-long-name = {
      expr =
        let
          p = patternOf (src "${name 2000}@{ ${formalsList 20000}, ... }: 1");
        in
        {
          inherit (p) kind ellipsis;
          formals = builtins.length (builtins.attrNames p.formals);
        };
      expected = {
        kind = "set";
        ellipsis = true;
        formals = 20000;
      };
    };
    # A head whose name pushes its close past the prefix is read from the skeleton, in every place a
    # name sits, at the first length the prefix cannot hold and well past it.
    test-a-long-name-is-read-in-every-place = {
      expr = map (n: map (f: shapeOf (patternOf f)) (namedIn n)) [
        944
        5000
      ];
      expected = [
        namedInExpected
        namedInExpected
      ];
    };
    test-a-head-past-the-prefix-is-read = {
      expr = patternOf longName;
      expected = {
        kind = "set";
        ellipsis = false;
        formals = {
          a = false;
        };
      };
    };
    # No regex runs over a name, so a 200,000-character one is served where a `.*` over it would
    # overflow the C stack.
    test-a-200000-character-at-name = {
      expr = patternOf (src "${name 200000}@{ a }: 1");
      expected = {
        kind = "set";
        ellipsis = false;
        formals = {
          a = false;
        };
      };
    };
    # Each field refuses only when it is read: the record and its shape serve a functor whose
    # published claim is malformed, and only `formals` refuses it (in `testsError`).
    test-a-malformed-functionArgs-leaves-the-shape-readable = {
      expr =
        let
          p = patternOf malformed;
        in
        {
          fields = builtins.attrNames p;
          shape = shapeOf p;
        };
      expected = {
        fields = [
          "ellipsis"
          "formals"
          "kind"
        ];
        shape = {
          kind = "named";
          ellipsis = false;
        };
      };
    };

    # THE RENDERING `parse` RELIES ON, pinned literally. An evaluator that changes it reds this cell
    # by name before any reader misreads.
    test-rendering-pin = {
      expr = map builtins.toXML [
        (x: x)
        ({ a, ... }: a)
        (args@{ a, ... }: args)
        (args@{ a }: args)
        builtins.map
      ];
      expected = [
        "<?xml version='1.0' encoding='utf-8'?>\n<expr>\n  <function>\n    <varpat name=\"x\" />\n  </function>\n</expr>\n"
        "<?xml version='1.0' encoding='utf-8'?>\n<expr>\n  <function>\n    <attrspat ellipsis=\"1\">\n      <attr name=\"a\" />\n    </attrspat>\n  </function>\n</expr>\n"
        "<?xml version='1.0' encoding='utf-8'?>\n<expr>\n  <function>\n    <attrspat ellipsis=\"1\" name=\"args\">\n      <attr name=\"a\" />\n    </attrspat>\n  </function>\n</expr>\n"
        "<?xml version='1.0' encoding='utf-8'?>\n<expr>\n  <function>\n    <attrspat name=\"args\">\n      <attr name=\"a\" />\n    </attrspat>\n  </function>\n</expr>\n"
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

  flake.testsError.pattern-shape =
    perturbedCells "short" false
    // perturbedCells "long" true
    // {
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
      test-formals-refuses-a-malformed-functionArgs = {
        expr = (patternOf malformed).formals;
        expectedError = refusal "the functor's `__functionArgs` is not an attrset of booleans";
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
