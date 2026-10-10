///|
fn copy_path(path : Path) -> Path {
  match path {
    Predicate(p) => Predicate(p)
    Inverse(p) => Inverse(copy_path(p))
    Sequence(paths) => Sequence(paths.map(copy_path))
    Alternative(paths) => Alternative(paths.map(copy_path))
    ZeroOrMore(p) => ZeroOrMore(copy_path(p))
    OneOrMore(p) => OneOrMore(copy_path(p))
    ZeroOrOne(p) => ZeroOrOne(copy_path(p))
  }
}

///|
fn evaluate_path(
  reader : Reader,
  start : Term,
  path : Path,
  reversed : Bool,
) -> Array[Term] {
  match path {
    Predicate(p) =>
      if reversed {
        reader.subjects(p, start)
      } else {
        reader.objects(start, p)
      }
    Inverse(p) => evaluate_path(reader, start, p, !reversed)
    Sequence(paths) => {
      let mut current = [start]
      let paths = if reversed { paths.rev() } else { paths.copy() }
      for p in paths {
        let next = []
        for node in current {
          next.append(evaluate_path(reader, node, p, reversed))
        }
        current = unique(next)
      }
      current
    }
    Alternative(paths) => {
      let all = []
      for p in paths {
        all.append(evaluate_path(reader, start, p, reversed))
      }
      unique(all)
    }
    ZeroOrOne(p) => {
      let all = [start]
      all.append(evaluate_path(reader, start, p, reversed))
      unique(all)
    }
    ZeroOrMore(p) | OneOrMore(p) => {
      let visited : Map[Term, Bool] = Map([])
      let queue = evaluate_path(reader, start, p, reversed)
      let out = []
      if path is ZeroOrMore(_) {
        out.push(start)
        visited[start] = true
      }
      let mut i = 0
      while i < queue.length() {
        let node = queue[i]
        i = i + 1
        if visited.contains(node) {
          continue
        }
        visited[node] = true
        out.push(node)
        queue.append(evaluate_path(reader, node, p, reversed))
      }
      out
    }
  }
}

///|
fn is_instance(reader : Reader, node : Term, class : Term) -> Bool {
  let types = reader.objects(node, rdf + "type")
  let visited : Map[Term, Bool] = Map([])
  let mut i = 0
  while i < types.length() {
    let current = types[i]
    i = i + 1
    if current == class {
      return true
    }
    if visited.contains(current) {
      continue
    }
    visited[current] = true
    types.append(reader.objects(current, rdfs + "subClassOf"))
  }
  false
}

///|
fn target_nodes(shape : Shape, graph : Graph) -> Array[Term] {
  if shape.deactivated {
    return []
  }
  let all = []
  let reader : Reader = { graph, reads: [], }
  for target in shape.targets {
    match target {
      Node(node) => all.push(node)
      Class(class) =>
        for (key, _) in graph.pos {
          if key.0 == rdf + "type" {
            for node in graph.subjects(key.0, key.1) {
              if is_instance(reader, node, class) {
                all.push(node)
              }
            }
          }
        }
      SubjectsOf(p) =>
        for t in graph.triples {
          if t.predicate == p {
            all.push(t.subject)
          }
        }
      ObjectsOf(p) =>
        for t in graph.triples {
          if t.predicate == p {
            all.push(t.object)
          }
        }
    }
  }
  // A stable order makes cache reuse and reports deterministic within the graph.
  let result = unique(all)
  result.sort_by((a, b) => a.to_ntriples().compare(b.to_ntriples()))
  result
}

///|
/// Evaluate a compiled path against an immutable graph.
pub fn Graph::values(self : Graph, start : Term, path : Path) -> Array[Term] {
  evaluate_path({ graph: self, reads: [], }, start, path, false)
}
