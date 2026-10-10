///|
fn example_plan() -> @moonshacl.Plan {
  let s = @moonshacl.Term::Iri("urn:shape")
  let property = @moonshacl.Term::Iri("urn:property-shape")
  @moonshacl.compile(
    @moonshacl.Graph::new([
      {
        subject: s,
        predicate: @moonshacl.sh + "targetClass",
        object: @moonshacl.Term::Iri("urn:Person"),
      },
      { subject: s, predicate: @moonshacl.sh + "property", object: property, },
      {
        subject: property,
        predicate: @moonshacl.sh + "path",
        object: @moonshacl.Term::Iri("urn:name"),
      },
      {
        subject: property,
        predicate: @moonshacl.sh + "minCount",
        object: @moonshacl.Term::Literal("1", @moonshacl.xsd + "integer", None),
      },
      {
        subject: property,
        predicate: @moonshacl.sh + "maxCount",
        object: @moonshacl.Term::Literal("1", @moonshacl.xsd + "integer", None),
      },
      {
        subject: property,
        predicate: @moonshacl.sh + "datatype",
        object: @moonshacl.Term::Iri(@moonshacl.xsd + "string"),
      },
    ]),
  )
  |> Result::unwrap
}

///|
fn fingerprint(report : @moonshacl.Report) -> Array[String] {
  let results = report.results.map(r => r.to_json().stringify())
  results.sort()
  results
}

///|
test "RDF identity, duplicate triples and language case" {
  let t : @moonshacl.Triple = {
    subject: @moonshacl.Term::Iri("urn:s"),
    predicate: "urn:p",
    object: @moonshacl.Term::Literal(
      "x",
      @moonshacl.rdf + "langString",
      Some("EN"),
    ),
  }
  let other : @moonshacl.Triple = {
    ..t,
    object: @moonshacl.lang_literal("x", "en"),
  }
  assert_eq(@moonshacl.Graph::new([t, t, other]).size(), 1)
  assert_true(
    @moonshacl.Term::Literal("01", @moonshacl.xsd + "integer", None) !=
    @moonshacl.Term::Literal("1", @moonshacl.xsd + "integer", None),
  )
  assert_true(
    @moonshacl.Term::Literal("x", @moonshacl.xsd + "string", None) !=
    @moonshacl.Term::Iri("x"),
  )
}

///|
test "Unsupported semantics and malformed parameters fail compilation" {
  for
    parameter in [
      "sparql", "js", "rule", "target", "pattern", "flags", "minInclusive", "unknownExtension",
    ] {
    let s = @moonshacl.Term::Iri("urn:s")
    match
      @moonshacl.compile(
        @moonshacl.Graph::new([
          {
            subject: s,
            predicate: @moonshacl.sh + "targetNode",
            object: @moonshacl.Term::Iri("urn:focus"),
          },
          {
            subject: s,
            predicate: @moonshacl.sh + parameter,
            object: @moonshacl.literal("whatever"),
          },
        ]),
      ) {
      Err(_) => ()
      Ok(_) => fail("accepted unsupported " + parameter)
    }
  }
  for
    n in [
      @moonshacl.literal("1"),
      @moonshacl.Term::Literal("-1", @moonshacl.xsd + "integer", None),
      @moonshacl.Term::Literal("2147483648", @moonshacl.xsd + "integer", None),
    ] {
    match
      @moonshacl.compile(
        @moonshacl.Graph::new([
          {
            subject: @moonshacl.Term::Iri("urn:s"),
            predicate: @moonshacl.sh + "path",
            object: @moonshacl.Term::Iri("urn:p"),
          },
          {
            subject: @moonshacl.Term::Iri("urn:s"),
            predicate: @moonshacl.sh + "minCount",
            object: n,
          },
        ]),
      ) {
      Err(_) => ()
      Ok(_) => fail("invalid count")
    }
  }
}

///|
test "Recursive shapes and cyclic paths are explicitly rejected" {
  match
    @moonshacl.compile(
      @moonshacl.Graph::new([
        {
          subject: @moonshacl.Term::Iri("urn:s"),
          predicate: @moonshacl.sh + "node",
          object: @moonshacl.Term::Iri("urn:s"),
        },
      ]),
    ) {
    Err(_) => ()
    Ok(_) => fail("recursive shape")
  }
  let p = @moonshacl.Term::Blank("path")
  match
    @moonshacl.compile(
      @moonshacl.Graph::new([
        {
          subject: @moonshacl.Term::Iri("urn:s"),
          predicate: @moonshacl.sh + "path",
          object: p,
        },
        { subject: p, predicate: @moonshacl.sh + "inversePath", object: p, },
      ]),
    ) {
    Err(_) => ()
    Ok(_) => fail("cyclic path")
  }
}

///|
test "Datatype lexical validation is exact and preserves arbitrary integer size" {
  let s = @moonshacl.Term::Iri("urn:s")
  for
    (datatype, valid, invalid) in [
      ("integer", "999999999999999999999999999999999999999999", "3.0"),
      ("unsignedLong", "18446744073709551615", "18446744073709551616"),
      ("byte", "127", "128"),
      ("decimal", "-.50", "1e2"),
      ("boolean", "1", "TRUE"),
      ("hexBinary", "AB00", "ABC"),
      ("duration", "-P1Y2M3DT4H5M6.7S", "P1DT"),
    ] {
    let plan = @moonshacl.compile(
        @moonshacl.Graph::new([
          {
            subject: s,
            predicate: @moonshacl.sh + "datatype",
            object: @moonshacl.Term::Iri(@moonshacl.xsd + datatype),
          },
        ]),
      )
      |> Result::unwrap
    let good = plan.validate_node(
        @moonshacl.Graph::new([]),
        s,
        @moonshacl.Term::Literal(valid, @moonshacl.xsd + datatype, None),
      )
      |> Result::unwrap
    let bad = plan.validate_node(
        @moonshacl.Graph::new([]),
        s,
        @moonshacl.Term::Literal(invalid, @moonshacl.xsd + datatype, None),
      )
      |> Result::unwrap
    assert_true(good.conforms)
    assert_false(bad.conforms)
  }
}

///|
test "Atomic update rollback, empty-read invalidation and defensive result copy" {
  let plan = example_plan()
  let person : @moonshacl.Triple = {
    subject: @moonshacl.Term::Iri("urn:p"),
    predicate: @moonshacl.rdf + "type",
    object: @moonshacl.Term::Iri("urn:Person"),
  }
  let name : @moonshacl.Triple = {
    subject: @moonshacl.Term::Iri("urn:p"),
    predicate: "urn:name",
    object: @moonshacl.literal("Alice"),
  }
  let session = @moonshacl.Session::new(plan, @moonshacl.Graph::new([person]))
  assert_false(session.report().conforms)
  let update = session.apply([name], [])
  assert_true(update.committed)
  assert_true(update.report.checked > 0)
  assert_eq(session.graph().size(), 2)
  let rejected = session.apply([], [name])
  assert_false(rejected.committed)
  assert_eq(session.graph().size(), 2)
  assert_true(session.report().conforms)
  assert_false(session.preview([], [name]).conforms)
  assert_eq(session.graph().size(), 2)
  let unchanged = session.apply([name], [])
  assert_true(unchanged.committed)
  assert_eq(unchanged.report.checked, 0)
  assert_true(unchanged.report.reused > 0)
  rejected.report.results.clear()
  assert_true(session.report().conforms)
}

///|
test "New targets, removed targets and inherited class dependencies" {
  let s = @moonshacl.Term::Iri("urn:s")
  let plan = @moonshacl.compile(
      @moonshacl.Graph::new([
        {
          subject: s,
          predicate: @moonshacl.sh + "targetClass",
          object: @moonshacl.Term::Iri("urn:A"),
        },
        {
          subject: s,
          predicate: @moonshacl.sh + "class",
          object: @moonshacl.Term::Iri("urn:B"),
        },
      ]),
    )
    |> Result::unwrap
  let person_type : @moonshacl.Triple = {
    subject: @moonshacl.Term::Iri("urn:p"),
    predicate: @moonshacl.rdf + "type",
    object: @moonshacl.Term::Iri("urn:C"),
  }
  let parent : @moonshacl.Triple = {
    subject: @moonshacl.Term::Iri("urn:C"),
    predicate: @moonshacl.rdfs + "subClassOf",
    object: @moonshacl.Term::Iri("urn:A"),
  }
  let requirement : @moonshacl.Triple = {
    subject: @moonshacl.Term::Iri("urn:C"),
    predicate: @moonshacl.rdfs + "subClassOf",
    object: @moonshacl.Term::Iri("urn:B"),
  }
  let session = @moonshacl.Session::new(
    plan,
    @moonshacl.Graph::new([person_type]),
  )
  assert_true(session.report().conforms)
  assert_false(session.apply([parent], []).committed)
  assert_true(session.apply([parent, requirement], []).committed)
  assert_false(session.apply([], [requirement]).committed)
  assert_true(session.apply([], [parent, requirement]).committed)
}

///|
test "@moonshacl.Path closure terminates on cycles and respects reversed sequence order" {
  let a = @moonshacl.Term::Iri("urn:a")
  let b = @moonshacl.Term::Iri("urn:b")
  let c = @moonshacl.Term::Iri("urn:c")
  let graph = @moonshacl.Graph::new([
    { subject: a, predicate: "urn:p", object: b, },
    { subject: b, predicate: "urn:p", object: a, },
    { subject: b, predicate: "urn:q", object: c, },
  ])
  let values = graph.values(a, OneOrMore(Predicate("urn:p")))
  assert_eq(values.length(), 2)
  assert_true(values.contains(a))
  assert_true(
    graph
    .values(c, Inverse(Sequence([Predicate("urn:p"), Predicate("urn:q")])))
    .contains(a),
  )
  assert_eq(graph.values(c, ZeroOrOne(Predicate("urn:none"))), [c])
}

///|
test "Deterministic incremental/full equivalence over mixed edits" {
  let plan = example_plan()
  let candidates : Array[@moonshacl.Triple] = []
  for i in 0..<12 {
    let node = @moonshacl.Term::Iri("urn:p" + i.to_string())
    candidates.push({
      subject: node,
      predicate: @moonshacl.rdf + "type",
      object: @moonshacl.Term::Iri("urn:Person"),
    })
    candidates.push({
      subject: node,
      predicate: "urn:name",
      object: @moonshacl.literal("name" + i.to_string()),
    })
    candidates.push({
      subject: node,
      predicate: "urn:name",
      object: @moonshacl.Term::Literal("3", @moonshacl.xsd + "integer", None),
    })
  }
  let session = @moonshacl.Session::new(plan, @moonshacl.Graph::new([]))
  let mut seed = 87331U
  for _ in 0..<400 {
    seed = seed * 1664525U + 1013904223U
    let index = (seed % candidates.length().reinterpret_as_uint()).reinterpret_as_int()
    let t = candidates[index]
    let add = if seed % 3U == 0U { [t] } else { [] }
    let remove = if add.is_empty() { [t] } else { [] }
    let next = session.graph().triples().filter(t => !remove.contains(t))
    next.append(add)
    let full = plan.validate(@moonshacl.Graph::new(next))
    let preview = session.preview(add, remove)
    assert_eq(preview.conforms, full.conforms)
    assert_eq(fingerprint(preview), fingerprint(full))
    let update = session.apply(add, remove)
    assert_eq(update.committed, full.conforms)
    assert_eq(fingerprint(update.report), fingerprint(full))
  }
}

///|
test "Reports are valid standalone RDF with distinct generated blank nodes" {
  let s = @moonshacl.Term::Blank("report")
  let plan = @moonshacl.compile(
      @moonshacl.Graph::new([
        {
          subject: s,
          predicate: @moonshacl.sh + "targetNode",
          object: @moonshacl.Term::Blank("result0"),
        },
        {
          subject: s,
          predicate: @moonshacl.sh + "nodeKind",
          object: @moonshacl.Term::Iri(@moonshacl.sh + "IRI"),
        },
      ]),
    )
    |> Result::unwrap
  let graph = plan.validate(@moonshacl.Graph::new([])).to_graph()
  assert_eq(
    graph
    .objects(@moonshacl.Term::Blank("report"), @moonshacl.sh + "result")
    .length(),
    1,
  )
  let result = graph.objects(
      @moonshacl.Term::Blank("report"),
      @moonshacl.sh + "result",
    )[0]
  assert_true(graph.objects(result, @moonshacl.sh + "focusNode")[0] != result)
  assert_true(
    graph.objects(result, @moonshacl.sh + "sourceShape")[0] !=
    @moonshacl.Term::Blank("report"),
  )
}
