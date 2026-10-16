///|
test "All added Core constraints remain equivalent across 1000 mixed edits" {
  let plan = plan_from(
    (
      #|@prefix ex: <urn:> . @prefix sh: <http://www.w3.org/ns/shacl#> .
      #|@prefix xsd: <http://www.w3.org/2001/XMLSchema#> .
      #|ex:S sh:targetNode ex:item, ex:unaffected;
      #| sh:property ex:Code, ex:Amount, ex:Start, ex:Inclusive .
      #|ex:Code sh:path ex:code; sh:pattern "^[A-Z]{2}-[0-9]{2}$"; sh:flags "i" .
      #|ex:Amount sh:path ex:amount; sh:minExclusive 0; sh:minInclusive 1;
      #| sh:maxExclusive 100; sh:maxInclusive 99 .
      #|ex:Start sh:path ex:start; sh:lessThan ex:end .
      #|ex:Inclusive sh:path ex:floor; sh:lessThanOrEquals ex:amount .
    ),
  )
  let initial = parse(
      (
        #|@prefix ex: <urn:> . @prefix xsd: <http://www.w3.org/2001/XMLSchema#> .
        #|ex:item ex:code "AB-12"; ex:amount 20; ex:floor 10;
        #| ex:start "2026-10-01T08:00:00Z"^^xsd:dateTime;
        #| ex:end "2026-10-01T09:00:00Z"^^xsd:dateTime .
        #|ex:unaffected ex:code "zz-00"; ex:amount 2; ex:floor 1 .
      ),
    )
    |> Result::unwrap
  let session = @moonshacl.Session::new(plan, initial)
  assert_true(session.report().conforms)
  let item = @moonshacl.Iri("urn:item")
  let candidates = [
    ("code", @moonshacl.literal("xy-99")),
    ("code", @moonshacl.literal("wrong")),
    ("code", @moonshacl.Blank("bad-code")),
    ("amount", @moonshacl.Literal("0", @moonshacl.xsd + "integer", None)),
    ("amount", @moonshacl.Literal("99", @moonshacl.xsd + "integer", None)),
    ("amount", @moonshacl.Literal("100", @moonshacl.xsd + "integer", None)),
    (
      "amount",
      @moonshacl.Literal(
        "50.00000000000000000001",
        @moonshacl.xsd + "decimal",
        None,
      ),
    ),
    ("floor", @moonshacl.Literal("1000", @moonshacl.xsd + "integer", None)),
    ("floor", @moonshacl.Literal("1", @moonshacl.xsd + "integer", None)),
    (
      "end",
      @moonshacl.Literal(
        "2026-10-01T08:00:00Z",
        @moonshacl.xsd + "dateTime",
        None,
      ),
    ),
    (
      "end",
      @moonshacl.Literal(
        "2026-10-01T10:00:00+01:00",
        @moonshacl.xsd + "dateTime",
        None,
      ),
    ),
    (
      "start",
      @moonshacl.Literal(
        "2026-10-01T07:00:00Z",
        @moonshacl.xsd + "dateTime",
        None,
      ),
    ),
    ("start", @moonshacl.literal("not comparable")),
  ]
  let mut state : UInt = 20261016
  for i in 0..<1000 {
    state = state * 1664525 + 1013904223
    let (predicate, value) = candidates[(state % 13).reinterpret_as_int()]
    let predicate = "urn:" + predicate
    let additions : Array[@moonshacl.Triple] = if i % 7 == 0 {
      []
    } else {
      [{ subject: item, predicate, object: value, }]
    }
    let removals = if i % 11 == 0 {
      []
    } else {
      session
      .graph()
      .triples()
      .filter(t => t.subject == item && t.predicate == predicate)
    }
    assert_update_matches_full(plan, session, additions, removals)
  }
}

///|
test "Property-pair constraints preserve failing pair multiplicity and empty-set semantics" {
  let plan = plan_from(
    (
      #|@prefix ex: <urn:> . @prefix sh: <http://www.w3.org/ns/shacl#> .
      #|ex:S sh:targetNode ex:item; sh:path ex:left; sh:lessThan ex:right .
    ),
  )
  let graph = parse("<urn:item> <urn:left> 5; <urn:right> 3, 4 .")
    |> Result::unwrap
  let results = plan.validate(graph).results
  assert_eq(results.length(), 2)
  assert_eq(results[0].value, results[1].value)
  let empty_right = parse("<urn:item> <urn:left> 5 .") |> Result::unwrap
  assert_true(plan.validate(empty_right).conforms)
}

///|
test "Explicit resource closure is cycle safe and preserves inputs and document identity" {
  let root = parse(
      "<urn:root> <http://www.w3.org/2002/07/owl#imports> <urn:a> .",
      scope="root-",
    )
    |> Result::unwrap
  let a = parse(
      (
        #|@prefix sh: <http://www.w3.org/ns/shacl#> .
        #|<urn:a> <http://www.w3.org/2002/07/owl#imports> <urn:b> .
        #|_:s sh:targetNode <urn:x>; sh:nodeKind sh:Literal .
      ),
      scope="a-",
    )
    |> Result::unwrap
  let b = parse(
      (
        #|@prefix sh: <http://www.w3.org/ns/shacl#> .
        #|<urn:b> <http://www.w3.org/2002/07/owl#imports> <urn:a> .
        #|_:s sh:targetNode <urn:x>; sh:nodeKind sh:IRI .
      ),
      scope="b-",
    )
    |> Result::unwrap
  let data = parse(
      "<urn:data> <http://www.w3.org/ns/shacl#shapesGraph> <urn:a> .",
    )
    |> Result::unwrap
  let before = (root.to_ntriples(), data.to_ntriples())
  assert_true(@moonshacl.load_shapes(root, data, Map([])) is Err(_))
  let loaded = @moonshacl.load_shapes(
      root,
      data,
      Map([("urn:a", a), ("urn:b", b)]),
    )
    |> Result::unwrap
  assert_eq(loaded.size(), 4)
  let plan = @moonshacl.compile(loaded) |> Result::unwrap
  assert_eq(plan.validate(data).results.length(), 1)
  assert_eq(before, (root.to_ntriples(), data.to_ntriples()))
}
