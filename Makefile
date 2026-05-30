
# Build the project.
# '@check' is for producing cmt files so we can run ocamlgrep on its codebase.
.PHONY: build
build:
	dune build

.PHONY: demo
demo:
	dune build @check
	dune exec -- ocamlgrep '(__ : Location.t)'

.PHONY: test
test:
	dune build @check
	dune exec -- ocamlgrep '__' --strict

# Install opam dependencies
.PHONY: setup
setup:
	opam install --deps-only --with-test --with-doc \
	  ./ocamlgrep-lib.opam ./ocamlgrep.opam
