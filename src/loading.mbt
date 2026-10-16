///|
/// Resolve shapes references from caller-supplied graphs without network access.
/// Each resource graph must have document-scoped blank-node identities.
/// Missing references are failures; import cycles are visited only once.
pub fn load_shapes(
  shapes : Graph,
  data : Graph,
  resources : Map[String, Graph],
  root_iri? : String? = None,
) -> Result[Graph, String] {
  let imports = "http://www.w3.org/2002/07/owl#imports"
  let links = sh + "shapesGraph"
  let pending : Array[Term] = []
  let output : Array[Triple] = []
  let add_graph = fn(graph : Graph) {
    for triple in graph.triples {
      if triple.predicate == imports || triple.predicate == links {
        pending.push(triple.object)
      } else {
        output.push(triple)
      }
    }
  }
  add_graph(shapes)
  for triple in data.triples {
    if triple.predicate == links {
      pending.push(triple.object)
    }
  }
  let visited : Map[String, Bool] = Map([])
  match root_iri {
    Some(iri) => visited[iri] = true
    None => ()
  }
  let mut cursor = 0
  while cursor < pending.length() {
    let reference = pending[cursor]
    cursor = cursor + 1
    let iri = match reference {
      Iri(iri) => iri
      _ =>
        return Err(
          "Shapes graph reference must be an IRI: " + reference.to_ntriples(),
        )
    }
    if visited.contains(iri) {
      continue
    }
    visited[iri] = true
    match resources.get(iri) {
      Some(graph) => add_graph(graph)
      None => return Err("Missing shapes resource: " + iri)
    }
  }
  Ok(Graph::new(output))
}
