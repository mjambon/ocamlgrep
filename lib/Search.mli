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
  | Scan_file of string
  | Finding of finding
  | Warning of string

(** [incremental_search paths handler] scans the project starting
    from the search root embedded in [paths]. Each time a finding or a
    warning is created, the [handler] function is called. *)
val incremental_search : Paths.t -> (event -> unit) -> string -> unit

(** Wrapper around [incremental_search] that returns the results as a list
    at the end instead of incrementally. *)
val search : Paths.t -> string -> event list
