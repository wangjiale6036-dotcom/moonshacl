///|
/// Opaque benchmark state. JS only schedules and times exported MoonBit calls.
pub struct Fixture {
  people : Int
  sharing : Int
  changes : Int
  data_text : String
  shapes_text : String
  shapes : @moonshacl.Graph
  graph : @moonshacl.Graph
  invalid_graph : @moonshacl.Graph
  plan : @moonshacl.Plan
  session : @moonshacl.Session
  old_names : Array[@moonshacl.Triple]
  new_names : Array[@moonshacl.Triple]
  mut renamed : Bool
}

///|
fn make_candidate(
  graph : @moonshacl.Graph,
  additions : Array[@moonshacl.Triple],
  removals : Array[@moonshacl.Triple],
) -> @moonshacl.Graph {
  let triples = graph.triples().filter(t => !removals.contains(t))
  triples.append(additions)
  @moonshacl.Graph::new(triples)
}

///|
/// Independent full-validation comparator: index removals once, but keep the
/// same public Graph API, source order, duplicate handling and validation Plan.
fn make_candidate_hashed(
  graph : @moonshacl.Graph,
  additions : Array[@moonshacl.Triple],
  removals : Array[@moonshacl.Triple],
) -> @moonshacl.Graph {
  let removed : Map[@moonshacl.Triple, Bool] = Map([])
  for t in removals {
    removed[t] = true
  }
  let triples = graph.triples().filter(t => !removed.contains(t))
  triples.append(additions)
  @moonshacl.Graph::new(triples)
}

///|
pub fn prepare(people : Int, sharing : Int, changes : Int) -> Fixture {
  prepare_checked(people, sharing, changes) catch {
    _ => abort("Benchmark fixture validation failed")
  }
}

///|
fn prepare_checked(
  people : Int,
  sharing : Int,
  changes : Int,
) -> Fixture raise @moonshacl.ValidationFailure {
  if people <= 0 ||
    sharing <= 0 ||
    people % sharing != 0 ||
    changes <= 0 ||
    changes > people / sharing {
    abort("Invalid benchmark dimensions")
  }
  let lines = ["@prefix ex: <urn:bench:> ."]
  for i in 0..<people {
    let id = i.to_string()
    lines.push(
      "ex:p" +
      id +
      " a ex:Person; ex:name \"Person " +
      id +
      "\"; ex:age 30; ex:employer ex:c" +
      (i / sharing).to_string() +
      " .",
    )
  }
  let old_names : Array[@moonshacl.Triple] = []
  let new_names : Array[@moonshacl.Triple] = []
  for i in 0..<(people / sharing) {
    let id = i.to_string()
    lines.push("ex:c" + id + " ex:name \"Company " + id + "\" .")
    if i < changes {
      old_names.push({
        subject: @moonshacl.Iri("urn:bench:c" + id),
        predicate: "urn:bench:name",
        object: @moonshacl.literal("Company " + id),
      })
      new_names.push({
        subject: @moonshacl.Iri("urn:bench:c" + id),
        predicate: "urn:bench:name",
        object: @moonshacl.literal("Renamed " + id),
      })
    }
  }
  let data_text = lines.join("\n")
  let shapes_text =
    #|@prefix ex: <urn:bench:> .
    #|@prefix sh: <http://www.w3.org/ns/shacl#> .
    #|@prefix xsd: <http://www.w3.org/2001/XMLSchema#> .
    #|ex:PersonShape sh:targetClass ex:Person;
    #| sh:property [sh:path ex:name; sh:minCount 1; sh:maxCount 1; sh:datatype xsd:string];
    #| sh:property [sh:path ex:age; sh:minCount 1; sh:maxCount 1; sh:datatype xsd:integer; sh:minInclusive 0; sh:maxInclusive 130];
    #| sh:property [sh:path (ex:employer ex:name); sh:minCount 1; sh:datatype xsd:string] .
  let graph = @turtle.parse(data_text) |> Result::unwrap
  let shapes = @turtle.parse(shapes_text) |> Result::unwrap
  let plan = @moonshacl.compile(shapes) |> Result::unwrap
  let session = @moonshacl.Session::new(plan, graph)
  {
    people,
    sharing,
    changes,
    data_text,
    shapes_text,
    shapes,
    graph,
    invalid_graph: make_candidate(graph, [], old_names),
    plan,
    session,
    old_names,
    new_names,
    renamed: false,
  }
}

///|
/// The timed boundary returns a small checksum and does not serialize reports.
/// All repeated preview/apply calls retain the SAME session and its cache.
pub fn measure(f : Fixture, operation : Int) -> Int {
  measure_checked(f, operation) catch {
    _ => abort("Benchmark operation validation failed")
  }
}

///|
fn measure_checked(
  f : Fixture,
  operation : Int,
) -> Int raise @moonshacl.ValidationFailure {
  match operation {
    0 => (@turtle.parse(f.data_text) |> Result::unwrap).size()
    1 => (@turtle.parse(f.shapes_text) |> Result::unwrap).size()
    2 => (@moonshacl.compile(f.shapes) |> Result::unwrap).diagnostics().length()
    3 => f.plan.validate(f.graph).checked
    4 => @moonshacl.Session::new(f.plan, f.graph).graph().size()
    5 => {
      let report = f.session.preview(
        [],
        if f.renamed {
          f.new_names
        } else {
          f.old_names
        },
      )
      report.checked + report.results.length()
    }
    6 => {
      let update = f.session.apply(
        [],
        if f.renamed {
          f.new_names
        } else {
          f.old_names
        },
      )
      if update.committed {
        abort("Invalid update unexpectedly committed")
      }
      update.report.checked + update.report.results.length()
    }
    7 => {
      let (additions, removals) = if f.renamed {
        (f.old_names, f.new_names)
      } else {
        (f.new_names, f.old_names)
      }
      let update = f.session.apply(additions, removals)
      if !update.committed {
        abort("Valid rename unexpectedly rejected")
      }
      f.renamed = !f.renamed
      update.report.checked
    }
    8 => f.plan.validate(f.invalid_graph).results.length()
    9 => {
      let removals = if f.renamed { f.new_names } else { f.old_names }
      let candidate = make_candidate(f.session.graph(), [], removals)
      f.plan.validate(candidate).results.length()
    }
    10 => {
      let removals = if f.renamed { f.new_names } else { f.old_names }
      let candidate = make_candidate_hashed(f.session.graph(), [], removals)
      f.plan.validate(candidate).results.length()
    }
    _ => abort("Unknown benchmark operation")
  }
}

///|
fn same_report(a : @moonshacl.Report, b : @moonshacl.Report) -> Bool {
  a.conforms == b.conforms && a.results == b.results
}

///|
pub fn verify(f : Fixture) -> String {
  verify_checked(f) catch {
    _ => abort("Benchmark correctness verification failed")
  }
}

///|
fn verify_checked(f : Fixture) -> String raise @moonshacl.ValidationFailure {
  let before = f.session.graph().triples()
  let removals = if f.renamed { f.new_names } else { f.old_names }
  let candidate = make_candidate(f.session.graph(), [], removals)
  let hashed_candidate = make_candidate_hashed(f.session.graph(), [], removals)
  let full = f.plan.validate(candidate)
  if candidate.triples() != hashed_candidate.triples() ||
    !same_report(full, f.plan.validate(hashed_candidate)) {
    abort("Hashed full-validation baseline differs from the original baseline")
  }
  let preview = f.session.preview([], removals)
  let rejected = f.session.apply([], removals)
  if !same_report(full, preview) ||
    !same_report(full, rejected.report) ||
    rejected.committed ||
    before != f.session.graph().triples() ||
    preview.results.length() != f.sharing * f.changes ||
    preview.checked != f.sharing * f.changes ||
    preview.checked + preview.reused != f.people {
    abort("Incremental rejection differs from full validation or changes state")
  }
  if !same_report(f.plan.validate(f.session.graph()), f.session.report()) {
    abort("Rejected proposal changed the cached report")
  }
  let (additions, removals) = if f.renamed {
    (f.old_names, f.new_names)
  } else {
    (f.new_names, f.old_names)
  }
  let valid_candidate = make_candidate(f.session.graph(), additions, removals)
  let valid_hashed_candidate = make_candidate_hashed(
    f.session.graph(),
    additions,
    removals,
  )
  let expected = f.plan.validate(valid_candidate)
  if valid_candidate.triples() != valid_hashed_candidate.triples() ||
    !same_report(expected, f.plan.validate(valid_hashed_candidate)) {
    abort("Hashed valid-update baseline differs from the original baseline")
  }
  let preview_valid = f.session.preview(additions, removals)
  if before != f.session.graph().triples() {
    abort("Valid preview changed the session graph")
  }
  let applied = f.session.apply(additions, removals)
  if !applied.committed ||
    !same_report(expected, preview_valid) ||
    !same_report(expected, applied.report) ||
    f.session.graph().triples() != valid_candidate.triples() {
    abort("Incremental commit differs from full validation")
  }
  f.renamed = !f.renamed
  let actual = f.plan.validate(f.session.graph())
  if !same_report(actual, f.session.report()) {
    abort("Cached report differs after commit")
  }
  let json : Json = {
    "passed": true,
    "rejectedResults": preview.results.length(),
    "checked": preview.checked,
    "reused": preview.reused,
    "rejectedAtomic": true,
    "previewNonMutating": true,
    "acceptedEquivalent": true,
    "fullBaselinesEquivalent": true,
    "compared": "conforms and full recursive result arrays; counters intentionally excluded",
  }
  json.stringify()
}

///|
pub fn metadata(f : Fixture) -> String {
  let json : Json = {
    "people": f.people,
    "peoplePerCompany": f.sharing,
    "companies": f.people / f.sharing,
    "changedCompanies": f.changes,
    "affectedPeople": f.sharing * f.changes,
    "dataTriples": f.graph.size(),
    "shapeTriples": f.shapes.size(),
    "dataCharacters": f.data_text.length(),
  }
  json.stringify()
}
