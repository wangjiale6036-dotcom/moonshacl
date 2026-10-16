///|
test "blank identity anonymous nodes do not merge with explicit generated-looking labels" {
  // The '[' starts at offset 32, for which MoonTTL generates _:genid32.
  let graph = @turtle.parse(
      "@prefix ex:<urn:ex:>. ex:s ex:p [ex:q 1]. _:genid32 ex:r 2. ex:t ex:p _:genid32. ex:u ex:p _:fresh-genid32.",
    )
    |> Result::unwrap
  let anonymous = graph.objects(@moonshacl.Iri("urn:ex:s"), "urn:ex:p")[0]
  let explicit = graph.objects(@moonshacl.Iri("urn:ex:t"), "urn:ex:p")[0]
  let fresh_looking = graph.objects(@moonshacl.Iri("urn:ex:u"), "urn:ex:p")[0]
  assert_true(anonymous is @moonshacl.Blank(_))
  assert_true(explicit is @moonshacl.Blank(_))
  assert_false(anonymous == explicit)
  assert_false(anonymous == fresh_looking)
  assert_false(explicit == fresh_looking)
  assert_eq(graph.objects(anonymous, "urn:ex:q").length(), 1)
  assert_true(graph.objects(anonymous, "urn:ex:r").is_empty())
  assert_true(graph.objects(explicit, "urn:ex:q").is_empty())
  assert_eq(graph.objects(explicit, "urn:ex:r").length(), 1)
  assert_eq(graph.size(), 5)
}

///|
test "blank identity preserves explicit references and disjoint document scopes" {
  let source = "@prefix ex:<urn:ex:>. ex:s ex:p _:genid32. _:genid32 ex:q _:fresh-genid32. _:fresh-genid32 ex:r _:genid32. ex:t ex:p []. ex:u ex:p []."
  let first = @turtle.parse(source, scope="one-") |> Result::unwrap
  let second = @turtle.parse(source, scope="two-") |> Result::unwrap
  let label = first.objects(@moonshacl.Iri("urn:ex:s"), "urn:ex:p")[0]
  let other = first.objects(label, "urn:ex:q")[0]
  assert_false(label == other)
  assert_eq(first.objects(other, "urn:ex:r"), [label])
  let anonymous1 = first.objects(@moonshacl.Iri("urn:ex:t"), "urn:ex:p")[0]
  let anonymous2 = first.objects(@moonshacl.Iri("urn:ex:u"), "urn:ex:p")[0]
  assert_false(anonymous1 == anonymous2)
  assert_false(anonymous1 == label)
  assert_false(anonymous1 == other)
  for name in ["s", "t", "u"] {
    assert_false(
      first.objects(@moonshacl.Iri("urn:ex:" + name), "urn:ex:p")[0] ==
      second.objects(@moonshacl.Iri("urn:ex:" + name), "urn:ex:p")[0],
    )
  }
}

///|
test "blank identity collection heads and tails stay separate from user labels" {
  // Collection head/tail are generated as genid32n0 and genid32n1.
  let graph = @turtle.parse(
      "@prefix ex:<urn:ex:>. ex:s ex:p (ex:a ex:b). _:genid32n0 ex:q 1. _:genid32n1 ex:q 2. ex:t ex:p _:genid32n0. ex:u ex:p _:genid32n1. ex:v ex:p ().",
    )
    |> Result::unwrap
  let head = graph.objects(@moonshacl.Iri("urn:ex:s"), "urn:ex:p")[0]
  let tail = graph.objects(head, @moonshacl.rdf + "rest")[0]
  let explicit_head = graph.objects(@moonshacl.Iri("urn:ex:t"), "urn:ex:p")[0]
  let explicit_tail = graph.objects(@moonshacl.Iri("urn:ex:u"), "urn:ex:p")[0]
  assert_false(head == tail)
  assert_false(head == explicit_head)
  assert_false(tail == explicit_tail)
  assert_true(graph.objects(head, "urn:ex:q").is_empty())
  assert_true(graph.objects(tail, "urn:ex:q").is_empty())
  assert_eq(graph.objects(head, @moonshacl.rdf + "first"), [
    @moonshacl.Iri("urn:ex:a"),
  ])
  assert_eq(graph.objects(tail, @moonshacl.rdf + "first"), [
    @moonshacl.Iri("urn:ex:b"),
  ])
  assert_eq(graph.objects(tail, @moonshacl.rdf + "rest"), [
    @moonshacl.Iri(@moonshacl.rdf + "nil"),
  ])
  assert_eq(graph.objects(@moonshacl.Iri("urn:ex:v"), "urn:ex:p"), [
    @moonshacl.Iri(@moonshacl.rdf + "nil"),
  ])
}

///|
test "blank identity never rewrites generated-looking text inside RDF literal or IRI terms" {
  let graph = @turtle.parse(
      "@prefix ex:<urn:ex:>. ex:s ex:p [ex:q 1]. _:genid32 ex:r 2. ex:s ex:text \"_:genid32\"^^<urn:custom>; ex:language \"_:genid32n0\"@en; ex:iri <urn:_:genid32>.",
    )
    |> Result::unwrap
  assert_eq(graph.objects(@moonshacl.Iri("urn:ex:s"), "urn:ex:text"), [
    @moonshacl.Literal("_:genid32", "urn:custom", None),
  ])
  assert_eq(graph.objects(@moonshacl.Iri("urn:ex:s"), "urn:ex:language"), [
    @moonshacl.lang_literal("_:genid32n0", "en"),
  ])
  assert_eq(graph.objects(@moonshacl.Iri("urn:ex:s"), "urn:ex:iri"), [
    @moonshacl.Iri("urn:_:genid32"),
  ])
}

///|
test "blank identity SHACL paths cannot reach an unrelated explicit blank node" {
  let shapes = @turtle.parse(
      "@prefix ex:<urn:ex:>. @prefix sh:<http://www.w3.org/ns/shacl#>. ex:S sh:targetNode ex:s; sh:property ex:P. ex:P sh:path (ex:p ex:r); sh:minCount 1.",
      scope="shapes-",
    )
    |> Result::unwrap
  let data = @turtle.parse(
      "@prefix ex:<urn:ex:>. ex:s ex:p [ex:q 1]. _:genid32 ex:r 2.",
      scope="data-",
    )
    |> Result::unwrap
  let plan = @moonshacl.compile(shapes) |> Result::unwrap
  let report = plan.validate(data)
  assert_false(report.conforms)
  assert_eq(report.results.length(), 1)
  assert_eq(
    report.results[0].component,
    @moonshacl.sh + "MinCountConstraintComponent",
  )
  assert_eq(report.results[0].focus_node, @moonshacl.Iri("urn:ex:s"))
}
