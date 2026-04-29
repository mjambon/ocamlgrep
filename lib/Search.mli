(* This file is part of the ocamlgrep package
   See the attached LICENSE file.
   Copyright (C) 2026 LexiFi *)
(**
   Ocamlgrep library - type-aware search for OCaml code patterns
*)

type finding = {
  source: string;
  i: int;
  c1: int;
  c2: int;
  s: string;
}

type event =
  | Finding of finding
  | Warning of string

val incremental_search : Paths.t -> (event -> unit) -> string -> unit

val search : Paths.t -> string -> event list
