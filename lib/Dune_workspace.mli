(** Structured access to the output of [dune describe workspace].

    Requires the [dune] command in PATH.

    This provides the locations of build assets (.ml, .cmt, ...) so
    that they can be scanned after a build.  Files are listed based on
    dune's source and build rules; they may or may not exist depending
    on the build state.

    Building all cmt files can be done with:
    {[
      dune build @check
    ]}
    which is slightly faster than a full [dune build].
*)

(** A module described by dune.  [impl], [intf], [cmt], [cmti] are
    encoded as [string option] because dune uses a 0-or-1-element list
    in its csexp output. *)
type module_ =
  { name : string;
    impl : string option;
    intf : string option;
    cmt  : string option;
    cmti : string option
  }

(** A [(library ...)] entry from the workspace description. *)
type library =
  { name        : string;
    uid         : string;
    local        : bool;
        (** [true] for libraries defined in this project,
            [false] for external dependencies. *)
    requires    : string list;
    source_dir  : string;
    modules     : module_ list;
    include_dirs : string list
  }

(** An [(executables ...)] entry. *)
type executables =
  { names       : string list;
    requires    : string list;
    modules     : module_ list;
    include_dirs : string list
  }

(** A digested view of the workspace. *)
type t =
  { root          : string;
    build_context : string;
    libraries     : library list;
    executables   : executables list
  }

(** [describe ?context ?root ()] runs
    {[
      dune describe workspace --format=csexp --lang 0.1
    ]}
    and parses the output.

    The [--lang 0.1] pin is dune's stability contract: the format is
    kept stable across dune versions; new top-level entry types in a
    future [--lang] are silently ignored.

    @param context build context to describe (default: [default]).
    @param root    force the project root instead of inferring it. *)
val describe :
  ?context:string ->
  ?root:string ->
  unit -> (t, string) result

(** Every cmt path declared by dune for project-local modules across
    all libraries ([local = true]) and all executables.
    Paths are as dune emits them — typically relative to the project
    root under [_build/<context>/...]. *)
val local_cmt_files : t -> string list
