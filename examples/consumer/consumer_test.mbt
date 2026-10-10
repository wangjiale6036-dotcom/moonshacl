///|
test "public package API compiles rules and atomically repairs a graph" {
  let shapes = @turtle.parse(
      (
        #|@prefix sh: <http://www.w3.org/ns/shacl#> .
        #|<urn:shape> sh:targetNode <urn:item>;
        #| sh:property [sh:path <urn:name>; sh:minCount 1; sh:maxCount 1] .
      ),
      scope="shapes-",
    )
    |> Result::unwrap
  let plan = @moonshacl.compile(shapes) |> Result::unwrap
  let empty = @moonshacl.Graph::new([])
  assert_false(plan.validate(empty).conforms)
  let session = @moonshacl.Session::new(plan, empty)
  let data = @turtle.parse("<urn:item> <urn:name> \"Example\" .")
    |> Result::unwrap
  assert_true(session.preview(data.triples(), []).conforms)
  assert_eq(session.graph().size(), 0)
  assert_true(session.apply(data.triples(), []).committed)
  assert_eq(session.graph().size(), 1)
  let rejected = session.apply([], data.triples())
  assert_false(rejected.committed)
  assert_eq(rejected.report.results[0].focus_node, @moonshacl.Iri("urn:item"))
  assert_true(rejected.report.to_graph().size() > 0)
  assert_eq(session.graph().triples(), data.triples())
  assert_true(session.report().conforms)
}
