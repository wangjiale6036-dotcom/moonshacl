///|
fn round2_triple(s : Term, p : String, o : Term) -> Triple {
  { subject: s, predicate: p, object: o, }
}

///|
fn round2_results(report : Report) -> Array[String] {
  let result = report.results.map(r => r.to_json().stringify())
  result.sort()
  result
}

///|
// Compare both indexes, including the retained spelling/order of RDF-equal
// language literals. Validation alone would not expose an unused broken index.
fn round2_assert_graph(
  actual : Graph,
  expected : Graph,
  probes : Array[Triple],
) -> Unit raise {
  assert_eq(actual.to_ntriples(), expected.to_ntriples())
  assert_eq(actual.size(), expected.size())
  for t in probes {
    assert_eq(
      actual.objects(t.subject, t.predicate).map(n => n.to_ntriples()),
      expected.objects(t.subject, t.predicate).map(n => n.to_ntriples()),
    )
    assert_eq(
      actual.subjects(t.predicate, t.object).map(n => n.to_ntriples()),
      expected.subjects(t.predicate, t.object).map(n => n.to_ntriples()),
    )
  }
}

///|
fn round2_assert_update(
  plan : Plan,
  session : Session,
  additions : Array[Triple],
  removals : Array[Triple],
) -> Unit raise {
  let before = session.graph()
  let before_text = before.to_ntriples()
  let triples = before.triples().filter(t => !removals.contains(t))
  triples.append(additions)
  let expected = Graph::new(triples)
  let full = plan.validate(expected)
  // A preview discards its candidate cache, and must never replace the live
  // cache, even after the caller edits its returned results.
  for _ in 0..<2 {
    let preview = session.preview(additions, removals)
    assert_eq(preview.conforms, full.conforms)
    assert_eq(round2_results(preview), round2_results(full))
    preview.results.clear()
    assert_eq(session.graph().to_ntriples(), before_text)
  }
  let update = session.apply(additions, removals)
  assert_eq(update.committed, full.conforms)
  assert_eq(round2_results(update.report), round2_results(full))
  assert_eq(
    session.graph().to_ntriples(),
    (if full.conforms { expected } else { before }).to_ntriples(),
  )
  assert_eq(before.to_ntriples(), before_text)
  assert_eq(
    round2_results(session.report()),
    round2_results(plan.validate(session.graph())),
  )
}

///|
test "Round two batch candidates preserve all graph indexes over 400 mixed edits" {
  let plan = compile(Graph::new([])).unwrap()
  let pool : Array[Triple] = []
  // Several values share a subject/predicate, and several subjects share the
  // same predicate/object. Include unequal numeric spellings and term kinds.
  let subjects = [Iri("urn:r2:s0"), Iri("urn:r2:s1"), Blank("r2-s2")]
  let values = [
    Iri("urn:r2:v"),
    Blank("r2-v"),
    literal("v"),
    Literal("1", xsd + "integer", None),
    Literal("01", xsd + "integer", None),
    Literal("v", rdf + "langString", Some("EN")),
    Literal("v", rdf + "langString", Some("en")),
  ]
  for subject in subjects {
    for predicate in ["urn:r2:p", "urn:r2:q"] {
      for value in values {
        pool.push(round2_triple(subject, predicate, value))
      }
    }
  }
  let initial = Graph::new(pool)
  let initial_text = initial.to_ntriples()
  let session = Session::new(plan, initial)
  let mut seed = 67193U
  for i in 0..<400 {
    let additions : Array[Triple] = []
    let removals : Array[Triple] = []
    for j in 0..<4 {
      seed = seed * 1664525U + 1013904223U
      let t = pool[(seed % pool.length().reinterpret_as_uint()).reinterpret_as_int()]
      if j % 2 == 0 || i % 5 == 0 {
        additions.push(t)
        additions.push(t)
      }
      if j % 2 == 1 || i % 3 == 0 {
        removals.push(t)
        removals.push(t)
      }
    }
    // Guarantee RDF-equal overlap and spelling changes, rather than relying
    // on the pseudo-random stream to happen to choose the two tag variants.
    if i % 7 == 0 {
      removals.push(pool[5])
      additions.push(pool[6])
      additions.push(pool[5])
    }
    let before = session.graph()
    let before_snapshot = Graph::new(before.triples())
    let triples = before.triples().filter(t => !removals.contains(t))
    triples.append(additions)
    let expected = Graph::new(triples)
    assert_true(session.preview(additions, removals).conforms)
    round2_assert_graph(session.graph(), before_snapshot, pool)
    assert_true(session.apply(additions, removals).committed)
    round2_assert_graph(session.graph(), expected, pool)
    round2_assert_graph(before, before_snapshot, pool)
    // All public result arrays remain copies after the fast graph rebuild.
    let copied = session.graph().objects(subjects[0], "urn:r2:p")
    copied.clear()
    let copied = session.graph().subjects("urn:r2:p", values[5])
    copied.clear()
    let copied = session.graph().triples()
    copied.clear()
    round2_assert_graph(session.graph(), expected, pool)
  }
  assert_eq(initial.to_ntriples(), initial_text)
}

///|
test "Round two preview then commit retains dependencies as targets appear and disappear" {
  let source_shape = Iri("urn:r2:source-shape")
  let object_shape = Iri("urn:r2:object-shape")
  let class_shape = Iri("urn:r2:class-shape")
  let name_shape = Iri("urn:r2:name-shape")
  let active_class = Iri("urn:r2:Active")
  let thing_class = Iri("urn:r2:Thing")
  let plan = compile(
    Graph::new([
      round2_triple(source_shape, sh + "targetSubjectsOf", Iri("urn:r2:active")),
      round2_triple(source_shape, sh + "property", name_shape),
      round2_triple(object_shape, sh + "targetObjectsOf", Iri("urn:r2:active")),
      round2_triple(object_shape, sh + "class", thing_class),
      round2_triple(class_shape, sh + "targetClass", active_class),
      round2_triple(class_shape, sh + "property", name_shape),
      round2_triple(name_shape, sh + "path", Iri("urn:r2:name")),
      round2_triple(
        name_shape,
        sh + "minCount",
        Literal("1", xsd + "integer", None),
      ),
    ]),
  ).unwrap()
  let a = Iri("urn:r2:a")
  let b = Iri("urn:r2:b")
  let c = Iri("urn:r2:c")
  let edge_b = round2_triple(a, "urn:r2:active", b)
  let edge_c = round2_triple(a, "urn:r2:active", c)
  let name = round2_triple(a, "urn:r2:name", literal("ready"))
  let a_type = round2_triple(a, rdf + "type", active_class)
  let b_type = round2_triple(b, rdf + "type", thing_class)
  let c_type = round2_triple(c, rdf + "type", thing_class)
  let session = Session::new(plan, Graph::new([]))
  round2_assert_update(plan, session, [edge_b, name, a_type, b_type], [])
  assert_eq(session.report().reused, 3)
  round2_assert_update(plan, session, [], [name])
  assert_eq(session.preview([], [name]).results.length(), 2)
  round2_assert_update(plan, session, [], [edge_b, name, a_type, b_type])
  assert_eq(session.report().reused, 0)
  assert_true(session.graph().triples().is_empty())
  // The same focus returns with a different downstream dependency. Its old
  // cached success must neither survive disappearance nor mask a missing type.
  round2_assert_update(plan, session, [edge_c, name], [])
  assert_true(session.graph().triples().is_empty())
  round2_assert_update(plan, session, [edge_c, name, c_type], [])
  assert_eq(session.report().reused, 2)
  round2_assert_update(plan, session, [], [c_type])
  assert_false(session.preview([], [c_type]).conforms)
  assert_true(session.report().conforms)
}

///|
test "Round two committed closure frontier and class reads survive non-committing previews" {
  let shape = Iri("urn:r2:closure-shape")
  let path = Blank("r2-closure-path")
  let allowed = Iri("urn:r2:Allowed")
  let sub = Iri("urn:r2:Sub")
  let other = Iri("urn:r2:Other")
  let root = Iri("urn:r2:root")
  let a = Iri("urn:r2:chain-a")
  let b = Iri("urn:r2:chain-b")
  let c = Iri("urn:r2:chain-c")
  let plan = compile(
    Graph::new([
      round2_triple(shape, sh + "targetNode", root),
      round2_triple(shape, sh + "path", path),
      round2_triple(path, sh + "zeroOrMorePath", Iri("urn:r2:next")),
      round2_triple(shape, sh + "class", allowed),
    ]),
  ).unwrap()
  let hierarchy = round2_triple(sub, rdfs + "subClassOf", allowed)
  let session = Session::new(
    plan,
    Graph::new([
      round2_triple(root, rdf + "type", allowed),
      round2_triple(a, rdf + "type", sub),
      round2_triple(root, "urn:r2:next", a),
      round2_triple(a, "urn:r2:next", root),
      hierarchy,
    ]),
  )
  let edge_b = round2_triple(a, "urn:r2:next", b)
  let b_type = round2_triple(b, rdf + "type", sub)
  round2_assert_update(plan, session, [edge_b, b_type], [])
  // Both new frontier queries and the shared class chain must be retained by
  // apply, although the identical successful previews discarded their cache.
  round2_assert_update(plan, session, [], [hierarchy])
  assert_eq(session.preview([], [hierarchy]).results.length(), 2)
  let edge_c = round2_triple(b, "urn:r2:next", c)
  let c_type = round2_triple(c, rdf + "type", other)
  round2_assert_update(plan, session, [edge_c, c_type], [])
  let other_hierarchy = round2_triple(other, rdfs + "subClassOf", allowed)
  round2_assert_update(plan, session, [edge_c, c_type, other_hierarchy], [])
  round2_assert_update(plan, session, [], [c_type])
  assert_false(session.preview([], [c_type]).conforms)
  // Removing the frontier makes its old class dependency irrelevant. The
  // remaining roots must still recheck their shared hierarchy on later edits.
  round2_assert_update(plan, session, [], [edge_c, c_type, other_hierarchy])
  round2_assert_update(plan, session, [], [hierarchy])
  assert_true(session.report().conforms)
}
