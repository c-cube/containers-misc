
(*
copyright (c) 2013-2014, Simon Cruanes, Emmanuel Surleau
all rights reserved.

redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

redistributions of source code must retain the above copyright notice, this
list of conditions and the following disclaimer.  redistributions in binary
form must reproduce the above copyright notice, this list of conditions and the
following disclaimer in the documentation and/or other materials provided with
the distribution.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
*)


type +'a t = [`Node of 'a * 'a t list]

type 'a tree = 'a t

type 'a sequence = ('a -> unit) -> unit
type 'a printer = Format.formatter -> 'a -> unit

let rec fold ~f init_acc (`Node (value, children)) =
  let acc = f value init_acc in
  List.fold_left (fun acc' child_node -> fold ~f acc' child_node) acc children

let to_seq t yield =
  let rec iter (`Node (value, children)) =
    yield value;
    List.iter iter children
  in
  iter t

let split_at_length_minus_1 l =
  let rev_list = List.rev l in
  match rev_list with
  | []          -> (l, None)
  | [item]      -> ([], Some item)
  | item::items -> (List.rev items, Some item)

let print pp_val formatter tree =
  let rec print_children children indent_string =
    let non_last_children, maybe_last_child =
      split_at_length_minus_1 children
    in
    print_non_last_children non_last_children indent_string;
    match maybe_last_child with
    | Some last_child -> print_last_child last_child indent_string;
    | None            -> ();
  and print_non_last_children non_last_children indent_string =
    List.iter (fun (`Node (child_value, grandchildren)) ->
        Format.pp_print_string formatter indent_string;
        Format.pp_print_string formatter "|- ";
        pp_val formatter child_value;
        Format.pp_force_newline formatter ();
        let indent_string' = indent_string ^ "|  " in
        print_children grandchildren indent_string'
      ) non_last_children;
  and print_last_child (`Node (last_child_value, last_grandchildren)) indent_string =
    Format.pp_print_string formatter indent_string;
    Format.pp_print_string formatter "'- ";
    pp_val formatter last_child_value;
    Format.pp_force_newline formatter ();
    let indent_string' = indent_string ^ "   " in
    print_children last_grandchildren indent_string'
  in
  let print_root (`Node (root_value, root_children)) =
    pp_val formatter root_value;
    Format.pp_force_newline formatter ();
    print_children root_children ""
  in
  print_root tree;
  Format.pp_print_flush formatter ()

module Zipper = struct

  type 'a parent = {
    left_siblings: ('a tree) list ;
    value: 'a ;
    right_siblings: ('a tree) list ;
  }

  type 'a t = {
    tree: 'a tree ;
    lefts: ('a tree) list ;
    rights: ('a tree) list ;
    parents: ('a parent) list ;
  }

  let zipper tree = { tree = tree ; lefts = []; rights = []; parents = [] }

  let tree zipper = zipper.tree

  let left_sibling zipper =
    match zipper.lefts with
    | []    -> None
    | next_left::farther_lefts ->
      Some {
        tree = next_left ;
        lefts = farther_lefts;
        rights = zipper.tree::zipper.rights ;
        parents = zipper.parents
      }

  let right_sibling zipper =
    match zipper.rights with
    | []                  -> None
    | next_right::farther_rights ->
      Some {
        tree = next_right ;
        lefts = zipper.tree::zipper.lefts ;
        rights = farther_rights ;
        parents = zipper.parents ;
      }

  let parent zipper =
    match zipper.parents with
    | []                    -> None
    | { left_siblings ; value ; right_siblings }::other_parents ->
      Some {
        tree = `Node (value, List.rev_append zipper.lefts [zipper.tree] @ zipper.rights) ;
        lefts = left_siblings ;
        rights = right_siblings ;
        parents = other_parents ;
      }

  let rec root zipper =
    let maybe_parent_zipper = parent zipper in
    match maybe_parent_zipper with
    | None                -> zipper
    | Some parent_zipper  -> root parent_zipper

  let parent_seq zipper yield =
    let rec iter zp =
      (* includes the current zipper *)
      yield zp;
      match parent zipper with
      | None -> ()
      | Some pzp -> iter pzp in
    iter zipper

  let children_seq zipper yield =
    match tree zipper with
    | `Node (_, []) -> ()
    | `Node (value, left::rest) ->
      let first =
        { tree = left;
          lefts = [];
          rights = rest;
          parents =
            {left_siblings=zipper.lefts; value; right_siblings=zipper.rights}
            ::zipper.parents
        } in
      let rec go_from sibling =
        match right_sibling sibling with
        | None -> ()
        | Some zp -> yield zp; go_from zp in
      go_from first

  let nth_child n ({ tree = `Node (value, children) ; _ } as zipper ) =
    let lefts, maybe_child, rev_rights, _counter = List.fold_left (
        fun (lefts, maybe_child, rev_rights, counter) tree ->
          let lefts', maybe_child', rev_rights' =
            match counter with
            | _ when counter == n -> (lefts, Some tree, [])
            | _ when counter < n ->
              (tree::lefts, None, [])
            | _                   ->
              (lefts, maybe_child, tree::rev_rights)
          in
          (lefts', maybe_child', rev_rights', counter+1)
      ) ([], None, [], 0) children
    in
    begin match maybe_child with
      | Some child  ->
        Some {
          tree = child ;
          lefts = lefts;
          rights = List.rev rev_rights ;
          parents = {
            left_siblings = zipper.lefts ;
            value = value ;
            right_siblings = zipper.rights ;
          }::zipper.parents ;
        }
      | None        -> None
    end

  let append_child tree ({ tree = `Node (value, children) ; _ } as zipper ) =
    {
      tree ;
      lefts = children ;
      rights = [] ;
      parents = {
        left_siblings = zipper.lefts ;
        value = value ;
        right_siblings = zipper.rights ;
      }::zipper.parents ;
    }

  let insert_left_sibling tree zipper =
    match zipper.parents with
    | []  -> None
    | _   -> Some { zipper with tree ; rights = zipper.tree::zipper.rights }

  let insert_right_sibling tree zipper =
    match zipper.parents with
    | []  -> None
    | _   -> Some { zipper with tree ; lefts = zipper.tree::zipper.lefts }

  let replace tree zipper =
    { zipper with tree }

  let delete ({ tree = `Node (_value, _children) ; _ } as zipper ) =
    match zipper with
    | { lefts = next_left::farther_lefts ; _  }     ->
      Some { zipper with tree = next_left ; lefts = farther_lefts }
    | { rights = next_right::farther_rights ; _ }  ->
      Some { zipper with tree = next_right ; rights = farther_rights }
    | { parents = { left_siblings ; value ; right_siblings }::other_parents ; _ } ->
      Some {
        tree = `Node (value, List.rev_append zipper.lefts zipper.rights) ;
        lefts = left_siblings ;
        rights = right_siblings ;
        parents = other_parents ;
      }
    | _ -> None

  let at_leaf zipper = match zipper.tree with
    | `Node (_, []) -> true
    | _ -> false

  let parent_fold f start (zipper:'a t) =
    let rec aux (acc, zp) = match parent zp with
      | None -> acc
      | Some pzp -> aux (f acc zp, pzp) in
    aux (start, zipper)

  let address zipper =
    let f ilist zp = List.length zp.lefts :: ilist in
    parent_fold f [] zipper

  let zip_down addr zipper =
    (* relative address, no short-circuit *)
    let f maybe_zip i = match maybe_zip with
      | None -> None
      | Some zip -> nth_child i zip in
    List.fold_left f (Some zipper) addr

  let zip_to addr zipper =
    zip_down addr (root zipper)

end
