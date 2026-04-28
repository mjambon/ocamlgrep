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

(** Return a list of folders to search for cmi and cmt files

    @param root the root folder to search from. Defaults to [_build/default].
 *)
val collect_cmi_dirs : ?root:string -> unit -> string list

val incremental_search : ?root:string -> (event -> unit) -> string -> unit

val search : ?root:string -> string -> event list
