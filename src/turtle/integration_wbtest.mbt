///|
fn plan_from(text : String) -> @moonshacl.Plan {
  parse(text, scope="shapes-")
  |> Result::unwrap
  |> @moonshacl.compile
  |> Result::unwrap
}

///|
fn result_fingerprint(report : @moonshacl.Report) -> Array[String] {
  let signatures = report.results.map(r => r.to_json().stringify())
  signatures.sort()
  signatures
}

///|
fn assert_update_matches_full(
  plan : @moonshacl.Plan,
  session : @moonshacl.Session,
  additions : Array[@moonshacl.Triple],
  removals : Array[@moonshacl.Triple],
) -> Unit raise {
  let before = session.graph()
  let triples = before.triples().filter(t => !removals.contains(t))
  triples.append(additions)
  let candidate = @moonshacl.Graph::new(triples)
  let full = plan.validate(candidate)
  let preview = session.preview(additions, removals)
  assert_eq(preview.conforms, full.conforms)
  assert_eq(result_fingerprint(preview), result_fingerprint(full))
  assert_eq(session.graph().to_ntriples(), before.to_ntriples())
  let update = session.apply(additions, removals)
  assert_eq(update.committed, full.conforms)
  assert_eq(result_fingerprint(update.report), result_fingerprint(full))
  assert_eq(
    session.graph().to_ntriples(),
    (if full.conforms { candidate } else { before }).to_ntriples(),
  )
  assert_eq(
    result_fingerprint(session.report()),
    result_fingerprint(plan.validate(session.graph())),
  )
}

///|
test "Shared paths, inverse reads, closure and targets remain equivalent over 600 edits" {
  let plan = plan_from(
    (
      #|@prefix ex: <urn:> . @prefix sh: <http://www.w3.org/ns/shacl#> .
      #|@prefix xsd: <http://www.w3.org/2001/XMLSchema#> .
      #|ex:S a sh:NodeShape; sh:targetClass ex:Person;
      #| sh:property [sh:path ex:name; sh:minCount 1; sh:maxCount 1; sh:datatype xsd:string];
      #| sh:property [sh:path (ex:employer ex:name); sh:minCount 1; sh:datatype xsd:string];
      #| sh:property [sh:path [sh:zeroOrMorePath ex:friend]; sh:node [sh:class ex:Person]] .
      #|ex:CompanyS a sh:PropertyShape; sh:targetNode ex:c0, ex:c1;
      #| sh:path [sh:inversePath ex:employer]; sh:maxCount 3 .
      #|ex:ContactS a sh:NodeShape; sh:targetSubjectsOf ex:contact;
      #| sh:property [sh:path ex:contact; sh:nodeKind sh:IRI] .
    ),
  )
  let prefixes = "@prefix ex: <urn:> . @prefix rdfs: <http://www.w3.org/2000/01/rdf-schema#> . "
  let initial = parse(
      prefixes +
      "ex:p0 a ex:Person; ex:name \"A\"; ex:employer ex:c0 . " +
      "ex:p1 a ex:Person; ex:name \"B\"; ex:employer ex:c0 . " +
      "ex:p2 a ex:Person; ex:name \"C\"; ex:employer ex:c1 . " +
      "ex:c0 ex:name \"Company0\" . ex:c1 ex:name \"Company1\" . " +
      "ex:Employee rdfs:subClassOf ex:Person .",
    )
    |> Result::unwrap
  let session = @moonshacl.Session::new(plan, initial)
  assert_true(session.report().conforms)
  let candidates = parse(
      prefixes +
      "ex:p0 a ex:Person, ex:Employee; ex:name \"A\", 1; ex:employer ex:c0, ex:c1; ex:friend ex:p1; ex:contact ex:p1, \"invalid\" . " +
      "ex:p1 a ex:Person; ex:name \"B\"; ex:employer ex:c0; ex:friend ex:p0 . " +
      "ex:p2 a ex:Person; ex:name \"C\"; ex:employer ex:c1; ex:friend ex:p3 . " +
      "ex:p3 a ex:Employee; ex:name \"D\"; ex:employer ex:c1 . " +
      "ex:c0 ex:name \"Company0\", 7 . ex:c1 ex:name \"Company1\" . " +
      "ex:Employee rdfs:subClassOf ex:Person .",
    )
    |> Result::unwrap
  let candidates = candidates.triples()
  let mut seed = 30107U
  for _ in 0..<600 {
    seed = seed * 1664525U + 1013904223U
    let a = candidates[(seed % candidates.length().reinterpret_as_uint()).reinterpret_as_int()]
    seed = seed * 1664525U + 1013904223U
    let b = candidates[(seed % candidates.length().reinterpret_as_uint()).reinterpret_as_int()]
    let additions = if seed % 3U == 0U { [a, b] } else { [a] }
    let removals = if seed % 2U == 0U { [b] } else { [a, b] }
    assert_update_matches_full(plan, session, additions, removals)
  }
}

///|
test "Qualified sibling dependencies and closed absence reads survive updates" {
  let plan = plan_from(
    (
      #|@prefix ex: <urn:> . @prefix sh: <http://www.w3.org/ns/shacl#> .
      #|ex:S a sh:NodeShape; sh:targetNode ex:root; sh:closed true;
      #| sh:property ex:P, ex:Q .
      #|ex:P sh:path ex:member; sh:qualifiedValueShape ex:A;
      #| sh:qualifiedMinCount 1; sh:qualifiedValueShapesDisjoint true .
      #|ex:Q sh:path ex:other; sh:qualifiedValueShape ex:B .
      #|ex:A sh:class ex:TypeA . ex:B sh:class ex:TypeB .
    ),
  )
  let initial = parse(
      "<urn:root> <urn:member> <urn:item> . <urn:item> a <urn:TypeA> .",
    )
    |> Result::unwrap
  let session = @moonshacl.Session::new(plan, initial)
  assert_true(session.report().conforms)
  let secondary_type : @moonshacl.Triple = {
    subject: @moonshacl.Iri("urn:item"),
    predicate: @moonshacl.rdf + "type",
    object: @moonshacl.Iri("urn:TypeB"),
  }
  let extra_property : @moonshacl.Triple = {
    subject: @moonshacl.Iri("urn:root"),
    predicate: "urn:unexpected",
    object: @moonshacl.literal("bad"),
  }
  for t in [secondary_type, extra_property] {
    let proposal = session.preview([t], [])
    assert_false(proposal.conforms)
    assert_eq(proposal.checked, 1)
    assert_update_matches_full(plan, session, [t], [])
  }
}

///|
test "Returned report paths cannot mutate a compiled plan or session cache" {
  let plan = plan_from(
    (
      #|@prefix sh: <http://www.w3.org/ns/shacl#> .
      #|<urn:S> sh:targetNode <urn:root>; sh:path (<urn:p> <urn:q>); sh:minCount 1 .
    ),
  )
  let graph = @moonshacl.Graph::new([])
  let session = @moonshacl.Session::new(plan, graph)
  for report in [plan.validate(graph), session.report()] {
    match report.results[0].path {
      Some(@moonshacl.Sequence(paths)) => paths.clear()
      _ => fail("Expected sequence report path")
    }
  }
  assert_eq(
    result_fingerprint(session.report()),
    result_fingerprint(plan.validate(graph)),
  )
  match plan.validate(graph).results[0].path {
    Some(@moonshacl.Sequence(paths)) => assert_eq(paths.length(), 2)
    _ => fail("Path was corrupted")
  }
}

///|
test "Indirect SHACL types and custom components cannot bypass the compiler" {
  for
    text in [
      "<urn:Type> <http://www.w3.org/2000/01/rdf-schema#subClassOf> <http://www.w3.org/ns/shacl#ConstraintComponent> . <urn:C> a <urn:Type> .",
      "<urn:Type> <http://www.w3.org/2000/01/rdf-schema#subClassOf> <http://www.w3.org/ns/shacl#NodeShape> . <urn:S> a <urn:Type>; <http://www.w3.org/ns/shacl#path> <urn:p> .",
      "@prefix sh: <http://www.w3.org/ns/shacl#> . <urn:S> sh:property <urn:P>, <urn:Q> . <urn:P> sh:path <urn:p>; sh:qualifiedValueShape <urn:A>; sh:qualifiedMinCount 1; sh:qualifiedValueShapesDisjoint true . <urn:Q> sh:path <urn:q>; sh:qualifiedValueShape <urn:B> . <urn:B> sh:not <urn:P> . <urn:A> sh:nodeKind sh:IRI .",
      "@prefix sh: <http://www.w3.org/ns/shacl#> . <urn:S> sh:node [sh:path <urn:p>] .",
      "@prefix sh: <http://www.w3.org/ns/shacl#> . <urn:S> a sh:NodeShape; sh:closed false; sh:ignoredProperties <urn:bad-list> .",
    ] {
    match @moonshacl.compile(parse(text) |> Result::unwrap) {
      Err(_) => ()
      Ok(_) => fail("Unsupported semantics accepted through subclass typing")
    }
  }
}

///|
test "Duration lexical grammar and XML whitespace are enforced" {
  let plan = plan_from(
    "<urn:S> <http://www.w3.org/ns/shacl#datatype> <http://www.w3.org/2001/XMLSchema#duration> .",
  )
  for value in ["PT.5S", "PT1.S", "PT1M1H", "P", "P1DT", "\u00A0PT1S"] {
    let result = plan.validate_node(
        @moonshacl.Graph::new([]),
        @moonshacl.Iri("urn:S"),
        @moonshacl.Literal(value, @moonshacl.xsd + "duration", None),
      )
      |> Result::unwrap
    assert_false(result.conforms)
  }
  for value in ["PT0.5S", "P1Y", "P1DT2H", " \t-PT1.5S\n"] {
    let result = plan.validate_node(
        @moonshacl.Graph::new([]),
        @moonshacl.Iri("urn:S"),
        @moonshacl.Literal(value, @moonshacl.xsd + "duration", None),
      )
      |> Result::unwrap
    assert_true(result.conforms)
  }
}

///|
test "Count parameters reject nondecimal lexical forms and honor XML whitespace" {
  for value in ["0x1", "0b1", "1.0", "\u00A01", "-1"] {
    let graph = @moonshacl.Graph::new([
      {
        subject: @moonshacl.Iri("urn:S"),
        predicate: @moonshacl.sh + "path",
        object: @moonshacl.Iri("urn:p"),
      },
      {
        subject: @moonshacl.Iri("urn:S"),
        predicate: @moonshacl.sh + "minCount",
        object: @moonshacl.Literal(value, @moonshacl.xsd + "integer", None),
      },
    ])
    match @moonshacl.compile(graph) {
      Err(_) => ()
      Ok(_) => fail("Accepted invalid xsd:integer count: " + value)
    }
  }
  let graph = @moonshacl.Graph::new([
    {
      subject: @moonshacl.Iri("urn:S"),
      predicate: @moonshacl.sh + "path",
      object: @moonshacl.Iri("urn:p"),
    },
    {
      subject: @moonshacl.Iri("urn:S"),
      predicate: @moonshacl.sh + "minCount",
      object: @moonshacl.Literal(" \t+01\r\n", @moonshacl.xsd + "integer", None),
    },
  ])
  assert_true(@moonshacl.compile(graph) is Ok(_))
}
