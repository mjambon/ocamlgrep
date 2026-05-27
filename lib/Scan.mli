(* This file is part of the ocamlgrep package.
   See the attached LICENSE file.
   Copyright (C) 2026 LexiFi *)

(** Type-aware search for OCaml expression patterns. *)

(** Alias for {!Match.finding}. *)
type finding = Match.finding = {
  loc   : Location.t;
  lines : string list;
  (** Source lines from [loc_start.pos_lnum] to [loc_end.pos_lnum],
      inclusive. Always non-empty. *)
}

type 'a event =
  | Scan_file of string  (** a source file is about to be scanned *)
  | Finding   of 'a      (** a matching region was found *)
  | Warning   of string  (** non-fatal diagnostic (e.g. missing cmt files) *)

(** [search ~root ~query] searches the Dune project rooted at (or
    containing) [root] for OCaml expressions matching the pattern [query].

    Returns [Ok (findings, warnings)] on success.
    Returns [Error message] for user-facing errors such as a bad query
    or a missing dune project. *)
val search
  :  root:string
  -> query:string
  -> (finding list * string list, string) result

(** Generic incremental search.  Enumerate [cmt_files] (e.g. from
    {!Dune_workspace.local_cmt_files}), call [search_fn] on each, and
    accumulate results via [handle_event].

    This lower-level interface is useful when the caller wants to
    intercept events as they arrive rather than receiving them all at once. *)
(** [finding_filename f] returns the project-relative source path stored in
    [f.loc.loc_start.pos_fname].  This accessor exists so that callers
    outside the library (where [Location] may refer to a different module,
    e.g. the LSP Location type) can retrieve the filename without needing to
    qualify the compiler-libs record fields. *)
val finding_filename : finding -> string

val incremental_search
  :  'acc
  -> Paths.t
  -> string list
  -> ('acc -> 'a event -> 'acc)
  -> (Cmt_format.cmt_infos -> source:string -> src_lines:string array -> 'a list)
  -> 'acc
