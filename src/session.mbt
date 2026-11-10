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
fn record_change(changes : Map[Read, Bool], triple : Triple) -> Unit {
  // Include absence reads as well as present values. A new or removed edge
  // invalidates each direction and any closed-shape read of its subject.
  changes[Objects(triple.subject, triple.predicate)] = true
  changes[Subjects(triple.predicate, triple.object)] = true
  changes[Outgoing(triple.subject)] = true
}

///|
fn cached_validate(
  plan : Plan,
  graph : Graph,
  cache : Map[(Term, Term), Cached],
  changes : Map[Read, Bool],
  retain_cache? : Bool = true,
) -> (Report, Map[(Term, Term), Cached]) raise ValidationFailure {
  let next : Map[(Term, Term), Cached] = Map([])
  let results = []
  let mut checked = 0
  let mut reused = 0
  // Targets are always recomputed. Newly added targets and disappeared targets
  // cannot be inferred solely from dependencies of previous focus nodes.
  for id in plan.shape_order {
    for focus in target_nodes(plan.shapes[id], graph) {
      let key = (id, focus)
      let (entry, from_cache) = match cache.get(key) {
        Some(old) if !old.reads.any(r => changes.contains(r)) => {
          reused = reused + 1
          (old, true)
        }
        _ => {
          let reader : Reader = { graph, reads: [], }
          let results = evaluate_shape(plan, id, focus, reader)
          checked = checked + 1
          ({ reads: reader.reads, results, }, false)
        }
      }
      if retain_cache {
        next[key] = entry
      }
      // A preview discards its candidate cache. Newly evaluated results already
      // own their mutable paths/messages/details, so they can escape directly.
      // Reused results always require isolation from the live session cache.
      results.append(
        if retain_cache || from_cache {
          entry.results.map(copy_result)
        } else {
          entry.results
        },
      )
    }
  }
  ({ conforms: results.is_empty(), results, checked, reused, }, next)
}

///|
/// The initial graph may be invalid; only conforming updates can be committed.
pub fn Session::new(
  plan : Plan,
  graph : Graph,
) -> Session raise ValidationFailure {
  let (_, cache) = cached_validate(plan, graph, Map([]), Map([]))
  { plan, graph, cache, }
}

///|
pub fn Session::graph(self : Session) -> Graph {
  self.graph
}

///|
pub fn Session::report(self : Session) -> Report raise ValidationFailure {
  let (report, _) = cached_validate(self.plan, self.graph, self.cache, Map([]))
  report
}

///|
fn Session::candidate(
  self : Session,
  additions : Array[Triple],
  removals : Array[Triple],
  retain_cache? : Bool = true,
) -> (Graph, Report, Map[(Term, Term), Cached]) raise ValidationFailure {
  let removed : Map[Triple, Bool] = Map([])
  let added : Map[Triple, Bool] = Map([])
  for t in removals {
    removed[t] = true
  }
  for t in additions {
    added[t] = false
  }
  let triples = []
  let changes : Map[Read, Bool] = Map([])
  for t in self.graph.triples {
    if !removed.contains(t) {
      triples.push(t)
    } else if !added.contains(t) {
      record_change(changes, t)
    }
  }
  // Retained triples are already unique. Visit additions in input order,
  // keeping their first representative only when not retained from the old
  // graph. This proves uniqueness without hashing every retained triple again.
  // The map uses the same RDF equality as Graph::new, including language case.
  for t in additions {
    if added[t] {
      continue
    }
    added[t] = true
    let existed = self.graph.spo
      .get_or_default((t.subject, t.predicate), [])
      .contains(t.object)
    if !existed {
      record_change(changes, t)
    }
    if !existed || removed.contains(t) {
      triples.push(t)
    }
  }
  let graph = Graph::from_unique(triples)
  let (report, cache) = cached_validate(
    self.plan,
    graph,
    self.cache,
    changes,
    retain_cache~,
  )
  (graph, report, cache)
}

///|
/// Inspect a proposed graph without changing graph or cache, including on success.
pub fn Session::preview(
  self : Session,
  additions : Array[Triple],
  removals : Array[Triple],
) -> Report raise ValidationFailure {
  let (_, report, _) = self.candidate(additions, removals, retain_cache=false)
  report
}

///|
/// Deletes are applied before additions. A rejected update changes neither graph nor cache.
pub fn Session::apply(
  self : Session,
  additions : Array[Triple],
  removals : Array[Triple],
) -> Update raise ValidationFailure {
  let (graph, report, cache) = self.candidate(additions, removals)
  let committed = report.conforms
  if committed {
    self.graph = graph
    self.cache = cache
  }
  { committed, report, }
}
