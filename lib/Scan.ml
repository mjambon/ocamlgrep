(* This file is part of the ocamlgrep package.
   See the attached LICENSE file.
   Copyright (C) 2026 LexiFi *)

open Printf

(** Re-export {!Match.finding} as the top-level finding type. *)
type finding = Match.finding = {
  loc   : Location.t;
  lines : string list;
}

type 'a event =
  | Scan_file of string   (** a source file is about to be scanned *)
  | Finding   of 'a       (** a matching region was found *)
  | Warning   of string   (** non-fatal diagnostic *)

let drop_prefix ~prefix s =
  if String.starts_with ~prefix s then
    String.sub s (String.length prefix) (String.length s - String.length prefix)
  else s

let read_lines fn =
  String.split_on_char '\n'
    (In_channel.with_open_text fn In_channel.input_all)


(* Resolve [source] (from cmt_sourcefile) to:
     - a project-relative display path  (used in pos_fname)
     - an absolute path for filesystem operations  (avoids CWD dependency)
     - whether to skip the digest check  (true when reading original .ml
       instead of the preprocessed .pp.ml that was compiled) *)
let resolve_source (paths : Paths.t) source =
  let project_root      = Paths.project_root      paths in
  let build_source_root = Paths.build_source_root paths in
  let build_prefix      = build_source_root ^ "/" in
  let strip_build abs =
    let stripped = drop_prefix ~prefix:build_prefix abs in
    if String.length stripped < String.length abs then Some stripped
    else None
  in
  if Filename.check_suffix source ".pp.ml" then begin
    (* The cmt was compiled from a ppx-preprocessed file.  The .pp.ml in
       _build/ may be binary (OCaml binary AST).  Find the original .ml
       in the project source tree instead and skip the digest check. *)
    let rel_pp =
      let r   = drop_prefix ~prefix:(Paths.project_relative_search_root paths) source in
      let abs = Filename.concat project_root r in
      match strip_build abs with
      | Some s -> s
      | None   -> drop_prefix ~prefix:(project_root ^ "/") abs
    in
    let rel_ml = Filename.chop_suffix rel_pp ".pp.ml" ^ ".ml" in
    (rel_ml, Filename.concat project_root rel_ml, true)
  end else begin
    let rel = drop_prefix ~prefix:(Paths.project_relative_search_root paths) source in
    let abs = Filename.concat project_root rel in
    let abs_source =
      match strip_build abs with
      | Some project_rel -> Filename.concat project_root project_rel
      | None -> abs
    in
    let source_rel = drop_prefix ~prefix:(project_root ^ "/") abs_source in
    (source_rel, abs_source, false)
  end

(* Process one cmt file.  Returns [Ok acc] on success (cmt file existed
   and was processable) and [Error ()] when the cmt file is missing
   (project not yet built or partially built). *)
let process_one_cmt acc (paths : Paths.t) handle_event search cmt_path =
  match Cmt_format.read_cmt cmt_path with
  | { Cmt_format.cmt_sourcefile = Some source;
      cmt_source_digest = Some digest; _ } as cmt ->
    let source, abs_source, skip_digest = resolve_source paths source in
    let acc = handle_event acc (Scan_file source) in
    if not (Sys.file_exists abs_source) then Ok acc
    else if (not skip_digest) && digest <> Digest.file abs_source then
      let acc =
        handle_event acc
          (Warning (sprintf "%s does not correspond to %s (ignoring)"
                      cmt_path abs_source))
      in
      Ok acc
    else begin
      let src_lines = Array.of_list (read_lines abs_source) in
      let acc =
        match search cmt ~source ~src_lines with
        | exception exn ->
          handle_event acc
            (Warning (Format.asprintf "error while analysing %s: %a"
                        cmt_path Location.report_exception exn))
        | results ->
          List.fold_left (fun acc r -> handle_event acc (Finding r)) acc results
      in
      Ok acc
    end
  | { cmt_sourcefile = None; _ } | { cmt_source_digest = None; _ } -> Ok acc
  | exception Cmt_format.Error (Cmt_format.Not_a_typedtree _) ->
    let acc =
      handle_event acc
        (Warning (sprintf "error reading cmt file: %s" cmt_path))
    in
    Ok acc
  | exception Sys_error _ ->
    (* cmt file does not exist — project needs (re)building *)
    Error ()

(** Generic incremental search.  [search_fn] is called for each cmt file
    and should return a list of findings.  [handle_event] accumulates state. *)
let incremental_search
    acc
    (paths : Paths.t)
    (cmt_files : string list)
    (handle_event : 'acc -> 'a event -> 'acc)
    (search_fn : Cmt_format.cmt_infos
                 -> source:string
                 -> src_lines:string array
                 -> 'a list)
  : 'acc =
  let total = List.length cmt_files in
  let acc, found =
    List.fold_left
      (fun (acc, found) cmt_path ->
         match process_one_cmt acc paths handle_event search_fn cmt_path with
         | Ok  acc -> (acc, found + 1)
         | Error () -> (acc, found))
      (acc, 0)
      cmt_files
  in
  if found < total then
    let missing = total - found in
    let pct     = (found * 100) / total in
    handle_event acc
      (Warning (sprintf "%d/%d cmt files found (%d%% coverage); \
                         %d missing — run 'dune build @check' to generate them"
                   found total pct missing))
  else
    acc

(* Delegate to Match.search, which handles location extraction and
   pos_fname overriding.  Partial application on [expr] gives the
   callback signature required by [incremental_search]. *)
let make_search_fn expr = Match.search expr

(** High-level search entry point for use by ocaml-lsp and similar tools.

    [search ~root ~query] searches the Dune project rooted at (or
    containing) [root] for OCaml expressions matching [query].

    Returns [Ok (findings, warnings)] on success, or
    [Error message] when a user-facing error prevents the search
    (bad query syntax, project not found, dune not available, etc.). *)
(** Extract the project-relative source filename from a finding.
    Defined here so that [Location] unambiguously refers to the compiler's
    [Location] module rather than any LSP [Location] in the caller's scope. *)
let finding_filename (f : finding) = f.loc.loc_start.pos_fname


  let ( let/ ) x f = match x with Error e -> Error e | Ok v -> f v in
  let/ expr =
    match
      Parse.implementation (Lexing.from_string query)
    with
    | [ { Parsetree.pstr_desc = Pstr_eval (x, _); _ } ] -> Ok x
    | _ -> Error "Can only search for an expression."
    | exception _ -> Error "Could not parse search expression."
  in
  let/ paths = Paths.identify_dune_project ~search_root:root () in
  Paths.init paths;
  let/ ws =
    Dune_workspace.describe ~root:(Paths.project_root paths) ()
  in
  let cmt_files = Dune_workspace.local_cmt_files ws in
  let search_fn = make_search_fn expr in
  let findings  = ref [] in
  let warnings  = ref [] in
  let handle_event () = function
    | Scan_file _  -> ()
    | Finding   f  -> findings := f :: !findings
    | Warning   w  -> warnings := w :: !warnings
  in
  ignore (incremental_search () paths cmt_files handle_event search_fn);
  Ok (List.rev !findings, List.rev !warnings)
