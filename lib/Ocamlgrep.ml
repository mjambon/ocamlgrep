(* This file is part of the ocamlgrep package.
   See the attached LICENSE file.
   Copyright (C) 2026 LexiFi *)

open Printf

(*
   We reuse the location type defined by compiler-libs because there's no
   reason to define it differently.

   To expose a stable interface and make sure users of ocamlgrep-lib
   don't depend on compiler-libs interfaces, the type equation
   [location = Location.t] is omitted in the mli.
*)
type location = Location.t = {
  loc_start : Lexing.position;
  loc_end : Lexing.position;
  loc_ghost : bool;
}

type finding = Match.finding = { loc : location; lines : string list }
type event = Scan_file of string | Finding of finding | Warning of string

(*
   This allows transparently unwrapping Ok values:

   let/ unwrapped = give_me_a_result () in
   Ok (transform_further unwrapped)
*)
let ( let/ ) = Result.bind

let drop_prefix ~prefix s =
  if String.starts_with ~prefix s then
    String.sub s (String.length prefix) (String.length s - String.length prefix)
  else s

(* fragile implementation of Fpath.relativize where
   both path are expected to be normalized such that they share a prefix:

    relativize "a/b/" "a/b/c/d" -> "c/d"
*)
let relativize root path = drop_prefix ~prefix:root path

let read_lines fn =
  String.split_on_char '\n' (In_channel.with_open_text fn In_channel.input_all)

(* Return a relative path to the source file.
   Dune returns a path to a copy of the source file. *)
let resolve_source (workspace : Dune_workspace.t)
    (module_ : Dune_workspace.module_) =
  match module_.impl with
  | None -> Error (sprintf "missing ml file for module %s" module_.name)
  | Some impl_path -> Ok (relativize (workspace.build_context ^ "/") impl_path)

(* True when [dir] is the root of a Dune project.  We check for this before
   running 'dune describe workspace --root dir' to avoid creating a spurious
   _build directory in directories that are not Dune projects. *)
let is_dune_project_root dir =
  List.exists
    (fun f -> Sys.file_exists (Filename.concat dir f))
    [ "dune-project"; "dune-workspace" ]

(* We return Ok/Error for stats purposes only.
   Error messages are passed to the handler as they occur. *)
let process_one_cmt (workspace : Dune_workspace.t)
    (module_ : Dune_workspace.module_) handle_event query : (unit, unit) result
    =
  let warning msg = handle_event (Warning msg) in
  let/ cmt_path = Option.to_result ~none:() module_.cmt in
  (* module_.cmt is relative to workspace.root; make it absolute so that
     Cmt_format.read_cmt works regardless of the process's working directory. *)
  let cmt_path = Filename.concat workspace.root cmt_path in
  match Cmt_format.read_cmt cmt_path with
  | { cmt_source_digest = Some digest; _ } as cmt -> (
      let/ source =
        match resolve_source workspace module_ with
        | Ok x -> Ok x
        | Error msg ->
            warning msg;
            Error ()
      in
      let abs_source = Filename.concat workspace.root source in
      handle_event (Scan_file source);
      if not (Sys.file_exists abs_source) then (
        warning (sprintf "missing source file %s" abs_source);
        Error ())
      else if digest <> Digest.file abs_source then (
        warning
          (sprintf "%s does not correspond to %s (ignoring)" cmt_path abs_source);
        Error ())
      else
        let src_lines = Array.of_list (read_lines abs_source) in
        match Match.search query cmt ~source ~src_lines with
        | exception exn ->
            warning
              (Format.asprintf "error while analysing %s: %a" cmt_path
                 Location.report_exception exn);
            Error ()
        | results ->
            List.iter (fun r -> handle_event (Finding r)) results;
            Ok ())
  | { cmt_sourcefile = None; _ }
  | { cmt_source_digest = None; _ } ->
      Ok ()
  | exception Cmt_format.Error (Cmt_format.Not_a_typedtree _) ->
      warning (sprintf "error reading cmt file: %s" cmt_path);
      Error ()
  | exception Sys_error msg ->
      warning
        (sprintf "system error occurred while reading cmt file: %s: %s" cmt_path
           msg);
      Error ()

(** Generic incremental search. [search_fn] is called for each cmt file and
    should return a list of findings. [handle_event] accumulates state. *)
let incremental_search ?root (handle_event : event -> unit) query =
  let/ expr =
    match Parse.implementation (Lexing.from_string query) with
    | [ { Parsetree.pstr_desc = Pstr_eval (x, _); _ } ] -> Ok x
    | _ -> Error "Can only search for an expression."
    | exception _ -> Error "Could not parse search expression."
  in
  match root with
  | Some r when not (is_dune_project_root r) -> Ok ()
  | _ ->
      let/ workspace = Dune_workspace.describe ?root () in
      let modules = Dune_workspace.get_modules workspace in
      let total = List.length modules in
      let successes =
        List.fold_left
          (fun successes module_ ->
            match process_one_cmt workspace module_ handle_event expr with
            | Ok () -> successes + 1
            | Error () -> successes)
          0 modules
      in
      (if successes < total then
         let missing = total - successes in
         let pct = float (successes * 100) /. float total in
         handle_event
           (Warning
              (sprintf
                 "%d/%d cmt files found (%.1f%% coverage); %d missing — run \
                  'dune build @check' to generate them"
                 successes total pct missing)));
      Ok ()

(* High-level search entry point for use by ocaml-lsp and similar tools. *)
let search ?root query =
  let findings = ref [] in
  let warnings = ref [] in
  let handle_event = function
    | Scan_file _ -> ()
    | Finding f -> findings := f :: !findings
    | Warning w -> warnings := w :: !warnings
  in
  let/ () = incremental_search ?root handle_event query in
  Ok (List.rev !findings, List.rev !warnings)
