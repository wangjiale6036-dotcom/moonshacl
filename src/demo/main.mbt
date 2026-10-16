///|
/// A MoonBit consumer uses the same API on JS, Wasm-GC and native.
fn main {
  run() catch {
    @moonshacl.ValidationFailure(message) =>
      println("Validation failure: " + message)
  }
}

///|
fn run() -> Unit raise @moonshacl.ValidationFailure {
  let shapes = @turtle.parse(
      (
        #|@prefix ex: <urn:> . @prefix sh: <http://www.w3.org/ns/shacl#> .
        #|ex:PersonShape sh:targetClass ex:Person;
        #| sh:property [sh:path (ex:employer ex:name); sh:minCount 1] .
      ),
      scope="shapes-",
    )
    |> Result::unwrap
  let data = @turtle.parse(
      (
        #|@prefix ex: <urn:> .
        #|ex:alice a ex:Person; ex:employer ex:acme .
        #|ex:bob a ex:Person; ex:employer ex:acme .
        #|ex:carol a ex:Person; ex:employer ex:other .
        #|ex:acme ex:name "Acme" . ex:other ex:name "Other" .
      ),
      scope="data-",
    )
    |> Result::unwrap
  let plan = @moonshacl.compile(shapes) |> Result::unwrap
  let session = @moonshacl.Session::new(plan, data)
  let removed = @turtle.parse("<urn:acme> <urn:name> \"Acme\" .")
    |> Result::unwrap
  let rejected = session.apply([], removed.triples())
  println("Deleting a shared company name:")
  println(rejected.report.to_json().stringify(indent=2))
  println(
    "committed=" +
    rejected.committed.to_string() +
    "; graphTriples=" +
    session.graph().size().to_string(),
  )
  let replacement = @turtle.parse("<urn:acme> <urn:name> \"Acme Limited\" .")
    |> Result::unwrap
  let accepted = session.apply(replacement.triples(), removed.triples())
  println("Atomic name replacement:")
  println(accepted.report.to_json().stringify(indent=2))
  println("committed=" + accepted.committed.to_string())
}
