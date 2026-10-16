///|
fn compiler_triple(subject : Term, predicate : String, object : Term) -> Triple {
  { subject, predicate, object, }
}

///|
fn compiler_fixture(
  parameters : Array[(String, Term)],
  property? : Bool = false,
) -> Graph {
  let shape = Iri("urn:compiler:shape")
  let triples = [
    compiler_triple(shape, sh + "targetNode", Iri("urn:compiler:focus")),
  ]
  if property {
    triples.push(compiler_triple(shape, sh + "path", Iri("urn:compiler:value")))
  }
  for (parameter, value) in parameters {
    triples.push(compiler_triple(shape, sh + parameter, value))
  }
  Graph::new(triples)
}

///|
test "Core compiler accepts signed and arbitrary precision integer thresholds" {
  for
    name in [
      "minCount", "maxCount", "minLength", "maxLength", "qualifiedMinCount", "qualifiedMaxCount",
    ] {
    for lexical in ["-1", "0", "+2147483648", "184467440737095516160000000000"] {
      assert_true(
        compile(
          compiler_fixture(
            [(name, Literal(lexical, xsd + "integer", None))],
            property=true,
          ),
        )
        is Ok(_),
      )
    }
    assert_true(
      compile(
        compiler_fixture(
          [(name, Literal("1.5", xsd + "integer", None))],
          property=true,
        ),
      )
      is Err(_),
    )
  }
}

///|
test "Core compiler creates all seven formerly missing components" {
  let plan = compile(
    compiler_fixture(
      [
        ("pattern", literal("^[A-Z]+$")),
        ("flags", literal("i")),
        ("minExclusive", Literal("-1", xsd + "integer", None)),
        ("minInclusive", Literal("0", xsd + "integer", None)),
        ("maxExclusive", Literal("11", xsd + "integer", None)),
        ("maxInclusive", Literal("10", xsd + "integer", None)),
        ("lessThan", Iri("urn:compiler:end")),
        ("lessThanOrEquals", Iri("urn:compiler:limit")),
      ],
      property=true,
    ),
  ).unwrap()
  assert_eq(plan.shapes[Iri("urn:compiler:shape")].rules.length(), 7)
  assert_true(
    compile(compiler_fixture([("minInclusive", Iri("urn:invalid"))])) is Err(_),
  )
  assert_true(
    compile(compiler_fixture([("pattern", lang_literal("x", "en"))])) is Err(_),
  )
  assert_true(compile(compiler_fixture([("pattern", literal("["))])) is Err(_))
  assert_true(compile(compiler_fixture([("lessThan", Iri("urn:p"))])) is Err(_))
  assert_true(
    compile(compiler_fixture([("lessThanOrEquals", Iri("urn:p"))])) is Err(_),
  )
}

///|
test "Core compiler accepts custom datatype IRIs and discovers auxiliary parameters" {
  assert_true(
    compile(compiler_fixture([("datatype", Iri("urn:custom:datatype"))]))
    is Ok(_),
  )
  let shape = Iri("urn:auxiliary")
  assert_true(
    compile(
      Graph::new([
        compiler_triple(
          shape,
          sh + "flags",
          Literal("1", xsd + "integer", None),
        ),
      ]),
    )
    is Err(_),
  )
  assert_true(
    compile(
      Graph::new([
        compiler_triple(
          shape,
          sh + "qualifiedMinCount",
          literal("not an integer"),
        ),
      ]),
    )
    is Err(_),
  )
}

///|
test "Core extension diagnostics and strict audit remain distinct" {
  let graph = compiler_fixture([
    ("sparql", Blank("query")),
    ("unknownExtension", literal("ignored")),
  ])
  let plan = compile(graph).unwrap()
  assert_eq(plan.diagnostics().length(), 2)
  let notices = plan.diagnostics()
  ignore(notices.pop())
  assert_eq(plan.diagnostics().length(), 2)
  assert_true(compile(graph, strict=true) is Err(_))
  let extension_only = Graph::new([
    compiler_triple(Iri("urn:extension"), sh + "target", Blank("custom-target")),
  ])
  assert_eq(compile(extension_only).unwrap().diagnostics().length(), 1)
}

///|
test "Unresolved imports and unsupported entailment are explicit failures" {
  for
    predicate in [
      "http://www.w3.org/2002/07/owl#imports",
      sh + "shapesGraph",
      sh + "entailment",
    ] {
    let graph = Graph::new([
      compiler_triple(Iri("urn:ontology"), predicate, Iri("urn:resource")),
    ])
    assert_true(compile(graph) is Err(_))
  }
}

///|
test "Core target and deactivation syntax is checked without narrowing other booleans" {
  assert_true(
    compile(compiler_fixture([("targetNode", Blank("bad-target"))])) is Err(_),
  )
  assert_true(
    compile(
      compiler_fixture([("deactivated", Literal("1", xsd + "boolean", None))]),
    )
    is Err(_),
  )
  assert_true(
    compile(
      compiler_fixture([("deactivated", Literal("true", xsd + "boolean", None))]),
    )
    is Ok(_),
  )
  assert_true(
    compile(
      compiler_fixture(
        [("uniqueLang", Literal("1", xsd + "boolean", None))],
        property=true,
      ),
    )
    is Ok(_),
  )
  assert_true(
    compile(compiler_fixture([("severity", Blank("bad-severity"))])) is Err(_),
  )
}

///|
test "SHACL lists require a clean rdf:nil and resource list nodes" {
  let shape = Iri("urn:compiler:shape")
  let base = [compiler_triple(shape, sh + "in", Iri(rdf + "nil"))]
  assert_true(compile(Graph::new(base)) is Ok(_))
  base.push(
    compiler_triple(Iri(rdf + "nil"), rdf + "first", Iri("urn:unexpected")),
  )
  assert_true(compile(Graph::new(base)) is Err(_))
  assert_true(
    compile(compiler_fixture([("in", literal("bad-list"))])) is Err(_),
  )
}

///|
test "Sequence path annotations are allowed but operator annotations remain invalid" {
  let shape = Iri("urn:compiler:shape")
  let head = Blank("head")
  let tail = Blank("tail")
  let graph = Graph::new([
    compiler_triple(shape, sh + "path", head),
    compiler_triple(shape, sh + "minCount", Literal("1", xsd + "integer", None)),
    compiler_triple(head, rdf + "first", Iri("urn:a")),
    compiler_triple(head, rdf + "rest", tail),
    compiler_triple(head, rdfs + "label", literal("allowed list annotation")),
    compiler_triple(tail, rdf + "first", Iri("urn:b")),
    compiler_triple(tail, rdf + "rest", Iri(rdf + "nil")),
  ])
  assert_true(compile(graph) is Ok(_))
  assert_true(
    compile(
      Graph::new([
        compiler_triple(shape, sh + "path", head),
        compiler_triple(
          shape,
          sh + "minCount",
          Literal("1", xsd + "integer", None),
        ),
        compiler_triple(head, sh + "inversePath", Iri("urn:a")),
        compiler_triple(
          head,
          rdfs + "label",
          literal("invalid operator annotation"),
        ),
      ]),
    )
    is Err(_),
  )
}

///|
test "Deep acyclic shapes compile while recursive references fail" {
  let triples : Array[Triple] = []
  for i = 0; i < 128; i = i + 1 {
    triples.push(
      compiler_triple(
        Iri("urn:shape:" + i.to_string()),
        sh + "node",
        Iri("urn:shape:" + (i + 1).to_string()),
      ),
    )
  }
  assert_true(compile(Graph::new(triples)) is Ok(_))
  triples.push(
    compiler_triple(Iri("urn:shape:128"), sh + "node", Iri("urn:shape:0")),
  )
  assert_true(compile(Graph::new(triples)) is Err(_))
  assert_true(
    compile(
      compiler_fixture(
        [("qualifiedValueShape", Iri("urn:compiler:shape"))],
        property=true,
      ),
    )
    is Err(_),
  )
}

///|
test "Deep valid paths use a separate configurable resource budget" {
  let shape = Iri("urn:deep-path-shape")
  let triples = [
    compiler_triple(shape, sh + "targetNode", Iri("urn:focus")),
    compiler_triple(shape, sh + "path", Blank("path:0")),
  ]
  for i = 0; i < 80; i = i + 1 {
    let next = if i == 79 {
      Iri("urn:predicate")
    } else {
      Blank("path:" + (i + 1).to_string())
    }
    triples.push(
      compiler_triple(Blank("path:" + i.to_string()), sh + "inversePath", next),
    )
  }
  assert_true(compile(Graph::new(triples)) is Ok(_))
  match compile(Graph::new(triples), max_depth=64) {
    Err(problems) =>
      assert_true(problems.any(p => p.message.has_prefix("Resource limit:")))
    Ok(_) => fail("Expected an explicit resource-limit failure")
  }
}

///|
test "Multiple not constraints and standard shape reference kinds are preserved" {
  let shape = Iri("urn:compiler:shape")
  assert_true(
    compile(
      compiler_fixture([
        ("not", Iri("urn:negative:a")),
        ("not", Iri("urn:negative:b")),
      ]),
    )
    is Ok(_),
  )
  assert_true(
    compile(
      Graph::new([
        compiler_triple(shape, sh + "node", Iri("urn:property-shape")),
        compiler_triple(Iri("urn:property-shape"), sh + "path", Iri("urn:p")),
      ]),
    )
    is Err(_),
  )
}

///|
test "Implicit class targets require typed shape classes and IRI shape identifiers" {
  let shape = Iri("urn:class-shape")
  let triples = [
    compiler_triple(shape, rdf + "type", Iri(rdfs + "Class")),
    compiler_triple(shape, sh + "class", Iri("urn:ExpectedClass")),
  ]
  assert_eq(
    compile(Graph::new(triples)).unwrap().shapes[shape].targets.length(),
    0,
  )
  triples.push(compiler_triple(shape, rdf + "type", Iri(sh + "NodeShape")))
  assert_eq(
    compile(Graph::new(triples)).unwrap().shapes[shape].targets.length(),
    1,
  )
  let invalid = triples.map(t => { ..t, subject: Blank("class-shape"), })
  assert_true(compile(Graph::new(invalid)) is Err(_))
}
