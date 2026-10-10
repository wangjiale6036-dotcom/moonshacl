///|
struct Cached {
  reads : Array[Read]
  results : Array[ValidationResult]
}

///|
/// A session keeps validation state for one immutable compiled plan.
pub struct Session {
  plan : Plan
  mut graph : Graph
  mut cache : Map[(Term, Term), Cached]
}

///|
pub(all) struct Update {
  committed : Bool
  report : Report
}

///|
fn copy_result(r : ValidationResult) -> ValidationResult {
  {
    ..r,
    path: r.path.map(copy_path),
    messages: r.messages.copy(),
    details: r.details.map(copy_result),
  }
}

///|
fn read_affected(read : Read, changes : Array[Triple]) -> Bool {
  changes.any(t => {
    match read {
      Objects(s, p) => t.subject == s && t.predicate == p
      Subjects(p, o) => t.predicate == p && t.object == o
      Outgoing(s) => t.subject == s
    }
  })
}

///|
fn cached_validate(
  plan : Plan,
  graph : Graph,
  cache : Map[(Term, Term), Cached],
  changes : Array[Triple],
) -> (Report, Map[(Term, Term), Cached]) {
  let next : Map[(Term, Term), Cached] = Map([])
  let results = []
  let mut checked = 0
  let mut reused = 0
  // Targets are always recomputed. Newly added targets and disappeared targets
  // cannot be inferred solely from dependencies of previous focus nodes.
  for id in plan.shape_order {
    for focus in target_nodes(plan.shapes[id], graph) {
      let key = (id, focus)
      let entry = match cache.get(key) {
        Some(old) if !old.reads.any(r => read_affected(r, changes)) => {
          reused = reused + 1
          old
        }
        _ => {
          let reader : Reader = { graph, reads: [], }
          let results = evaluate_shape(plan, id, focus, reader)
          checked = checked + 1
          { reads: reader.reads, results, }
        }
      }
      next[key] = entry
      results.append(entry.results.map(copy_result))
    }
  }
  ({ conforms: results.is_empty(), results, checked, reused, }, next)
}

///|
/// The initial graph may be invalid; only conforming updates can be committed.
pub fn Session::new(plan : Plan, graph : Graph) -> Session {
  let (_, cache) = cached_validate(plan, graph, Map([]), [])
  { plan, graph, cache, }
}

///|
pub fn Session::graph(self : Session) -> Graph {
  self.graph
}

///|
pub fn Session::report(self : Session) -> Report {
  let (report, _) = cached_validate(self.plan, self.graph, self.cache, [])
  report
}

///|
fn Session::candidate(
  self : Session,
  additions : Array[Triple],
  removals : Array[Triple],
) -> (Graph, Report, Map[(Term, Term), Cached]) {
  let triples = self.graph.triples.filter(t => !removals.contains(t))
  triples.append(additions)
  let graph = Graph::new(triples)
  let before : Map[Triple, Bool] = Map([])
  let after : Map[Triple, Bool] = Map([])
  for t in self.graph.triples {
    before[t] = true
  }
  for t in graph.triples {
    after[t] = true
  }
  let changes = []
  for t in self.graph.triples {
    if !after.contains(t) {
      changes.push(t)
    }
  }
  for t in graph.triples {
    if !before.contains(t) {
      changes.push(t)
    }
  }
  let (report, cache) = cached_validate(self.plan, graph, self.cache, changes)
  (graph, report, cache)
}

///|
/// Inspect a proposed graph without changing graph or cache, including on success.
pub fn Session::preview(
  self : Session,
  additions : Array[Triple],
  removals : Array[Triple],
) -> Report {
  let (_, report, _) = self.candidate(additions, removals)
  report
}

///|
/// Deletes are applied before additions. A rejected update changes neither graph nor cache.
pub fn Session::apply(
  self : Session,
  additions : Array[Triple],
  removals : Array[Triple],
) -> Update {
  let (graph, report, cache) = self.candidate(additions, removals)
  let committed = report.conforms
  if committed {
    self.graph = graph
    self.cache = cache
  }
  { committed, report, }
}
