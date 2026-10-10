///|
/// A term's identity includes its lexical spelling and datatype, never its coerced value.
pub(all) enum Term {
  Iri(String)
  Blank(String)
  Literal(String, String, String?)
} derive(@debug.Debug)

///|
pub impl Eq for Term with fn equal(self, other) {
  match (self, other) {
    (Iri(a), Iri(b)) | (Blank(a), Blank(b)) => a == b
    (Literal(a, ad, al), Literal(b, bd, bl)) =>
      a == b &&
      ad == bd &&
      al.map(s => s.to_lower()) == bl.map(s => s.to_lower())
    _ => false
  }
}

///|
pub impl Hash for Term with fn hash_combine(self, hasher) {
  match self {
    Iri(s) => {
      hasher.combine_int(0)
      hasher.combine_string(s)
    }
    Blank(s) => {
      hasher.combine_int(1)
      hasher.combine_string(s)
    }
    Literal(value, datatype, language) => {
      hasher.combine_int(2)
      hasher.combine_string(value)
      hasher.combine_string(datatype)
      match language {
        Some(tag) => {
          hasher.combine_int(1)
          hasher.combine_string(tag.to_lower())
        }
        None => hasher.combine_int(0)
      }
    }
  }
}

///|
pub extend Term with Eq::{equal, not_equal}

///|
pub extend Term with Hash::{hash, hash_combine}

///|
pub extend Term with @debug.Debug::{to_repr}

///|
pub(all) struct Triple {
  subject : Term
  predicate : String
  object : Term
} derive(Eq, Hash, @debug.Debug)

///|
pub extend Triple with Eq::{equal, not_equal}

///|
pub extend Triple with Hash::{hash, hash_combine}

///|
pub extend Triple with @debug.Debug::{to_repr}

///|
/// Graphs use RDF set semantics: duplicate triples never count twice.
pub struct Graph {
  triples : Array[Triple]
  spo : Map[(Term, String), Array[Term]]
  pos : Map[(String, Term), Array[Term]]
}

///|
pub fn Graph::new(triples : Array[Triple]) -> Graph {
  let result : Array[Triple] = []
  let seen : Map[Triple, Bool] = Map([])
  let spo : Map[(Term, String), Array[Term]] = Map([])
  let pos : Map[(String, Term), Array[Term]] = Map([])
  for t in triples {
    if !seen.contains(t) {
      seen[t] = true
      result.push(t)
      spo.get_or_init((t.subject, t.predicate), () => []).push(t.object)
      pos.get_or_init((t.predicate, t.object), () => []).push(t.subject)
    }
  }
  { triples: result, spo, pos, }
}

///|
pub fn Graph::triples(self : Graph) -> Array[Triple] {
  self.triples.copy()
}

///|
pub fn Graph::size(self : Graph) -> Int {
  self.triples.length()
}

///|
pub let rdf : String = "http://www.w3.org/1999/02/22-rdf-syntax-ns#"

///|
pub let rdfs : String = "http://www.w3.org/2000/01/rdf-schema#"

///|
pub let sh : String = "http://www.w3.org/ns/shacl#"

///|
pub let xsd : String = "http://www.w3.org/2001/XMLSchema#"

///|
pub fn literal(value : String) -> Term {
  Literal(value, xsd + "string", None)
}

///|
pub fn lang_literal(value : String, language : String) -> Term {
  Literal(value, rdf + "langString", Some(language.to_lower()))
}

///|
pub fn Graph::objects(
  self : Graph,
  subject : Term,
  predicate : String,
) -> Array[Term] {
  self.spo.get_or_default((subject, predicate), []).copy()
}

///|
pub fn Graph::subjects(
  self : Graph,
  predicate : String,
  object : Term,
) -> Array[Term] {
  self.pos.get_or_default((predicate, object), []).copy()
}

///|
pub fn Term::to_ntriples(self : Term) -> String {
  match self {
    Iri(s) => "<" + s + ">"
    Blank(s) => "_:" + s
    Literal(value, datatype, language) => {
      let quoted = Json::string(value).stringify()
      match language {
        Some(tag) => quoted + "@" + tag
        None => quoted + "^^<" + datatype + ">"
      }
    }
  }
}

///|
pub(all) enum Path {
  Predicate(String)
  Inverse(Path)
  Sequence(Array[Path])
  Alternative(Array[Path])
  ZeroOrMore(Path)
  OneOrMore(Path)
  ZeroOrOne(Path)
} derive(Eq, @debug.Debug)

///|
pub extend Path with Eq::{equal, not_equal}

///|
pub extend Path with @debug.Debug::{to_repr}

///|
/// Shape compilation errors are not validation results.
pub(all) struct Problem {
  node : Term
  predicate : String
  message : String
} derive(Eq, @debug.Debug)

///|
pub extend Problem with Eq::{equal, not_equal}

///|
pub extend Problem with @debug.Debug::{to_repr}

///|
pub(all) struct ValidationResult {
  focus_node : Term
  source_shape : Term
  component : String
  severity : Term
  path : Path?
  value : Term?
  messages : Array[Term]
  details : Array[ValidationResult]
} derive(Eq, @debug.Debug)

///|
pub extend ValidationResult with Eq::{equal, not_equal}

///|
pub extend ValidationResult with @debug.Debug::{to_repr}

///|
pub(all) struct Report {
  conforms : Bool
  results : Array[ValidationResult]
  checked : Int
  reused : Int
}

///|
/// Read dependencies include absence queries, preventing stale minCount/closed results.
priv enum Read {
  Objects(Term, String)
  Subjects(String, Term)
  Outgoing(Term)
}

///|
priv struct Reader {
  graph : Graph
  reads : Array[Read]
}

///|
fn Reader::objects(self : Reader, s : Term, p : String) -> Array[Term] {
  self.reads.push(Objects(s, p))
  self.graph.objects(s, p)
}

///|
fn Reader::subjects(self : Reader, p : String, o : Term) -> Array[Term] {
  self.reads.push(Subjects(p, o))
  self.graph.subjects(p, o)
}

///|
fn Reader::outgoing(self : Reader, s : Term) -> Array[Triple] {
  self.reads.push(Outgoing(s))
  self.graph.triples.filter(t => t.subject == s)
}

///|
fn unique(nodes : Array[Term]) -> Array[Term] {
  let seen : Map[Term, Bool] = Map([])
  let out = []
  for node in nodes {
    if !seen.contains(node) {
      seen[node] = true
      out.push(node)
    }
  }
  out
}
