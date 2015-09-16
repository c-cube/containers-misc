# Containers-misc

Random stuff too experimental for containers

**not released yet**

## Build

Use opam, for instance:

    opam pin add -k git containers-misc https://github.com/c-cube/containers-misc.git

and

    opam install containers-misc

## Use

The library contains a pack module `Containers_misc`, with the following modules:

- `AbsSet`, an abstract Set data structure, a bit like `LazyGraph`.
- `Automaton`, `CSM`, state machine abstractions
- `Bij`, a GADT-based bijection language used to serialize/deserialize your data structures
- `Hashset`, a polymorphic imperative set on top of `PHashtbl`
- `LazyGraph`, a lazy graph structure on arbitrary (hashable+eq) types, with basic graph functions that work even on infinite graphs, and printing to DOT.
- `PHashtbl`, a polymorphic hashtable (with open addressing)
- `RoseTree`, a tree with an arbitrary number of children and its associated zipper
- `SmallSet`, a sorted list implementation behaving like a set.
- `UnionFind`, a functorial imperative Union-Find structure
- `Univ`, a universal type encoding with affectation
