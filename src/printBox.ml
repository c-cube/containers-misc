
(*
copyright (c) 2013-2014, simon cruanes
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

(** {1 Pretty-Printing of Boxes} *)

type position = { x:int ; y: int }

let _cmp pos1 pos2 =
  match Pervasives.compare pos1.y pos2.y with
  | 0 -> Pervasives.compare pos1.x pos2.x
  | x -> x

let origin = {x=0; y=0;}

let _move pos x y = {x=pos.x + x; y=pos.y + y}
let _add pos1 pos2 = _move pos1 pos2.x pos2.y
let _minus pos1 pos2 = _move pos1 (- pos2.x) (- pos2.y)
let _move_x pos x = _move pos x 0
let _move_y pos y = _move pos 0 y

let _string_len = ref Bytes.length

let set_string_len f = _string_len := f

(** {2 Output: where to print to} *)

module Output = struct
  type t = {
    put_char : position -> char -> unit;
    put_string : position -> string -> unit;
    put_sub_string : position -> string -> int -> int -> unit;
    flush : unit -> unit;
  }

  let put_char out pos c = out.put_char pos c
  let put_string out pos s = out.put_string pos s
  let put_sub_string out pos s s_i s_len = out.put_sub_string pos s s_i s_len

  (** Internal multi-line buffer suitable for unicode strings.
      It is a map from start position to a printable entity (string or character)
      All printable sequences are supposed to *NOT* introduce new lines *)
  module M = Map.Make(struct type t = position let compare = _cmp end)

  type printable =
    | Char of char
    | String of string

  type buffer = {
    mutable map : printable M.t
  }

  (* Note: we trust the user not to mess things up relating to
     strings overlapping because of bad positions *)
  let _buf_put_char buf pos c =
    buf.map <- M.add pos (Char c) buf.map

  let _buf_put_string buf pos s =
    buf.map <- M.add pos (String s) buf.map

  let _buf_put_sub_string buf pos s s_i s_len =
    buf.map <- M.add pos (String (String.sub s s_i s_len)) buf.map

  let make_buffer () =
    let buf  = { map = M.empty } in
    let buf_out = {
      put_char = _buf_put_char buf;
      put_string = _buf_put_string buf;
      put_sub_string = _buf_put_sub_string buf;
      flush = (fun () -> ());
    } in
    buf, buf_out

  let rec buf_out_aux ?(indent=0) buf start_pos p curr_pos =
    assert (_cmp curr_pos start_pos <= 0);
    (* Go up to the expected location *)
    for i = curr_pos.y to start_pos.y - 1 do
      Buffer.add_char buf '\n';
      for j = 1 to indent do
        Buffer.add_char buf ' '
      done
    done;
    for i = curr_pos.x to start_pos.x - 1 do
      Buffer.add_char buf ' '
    done;
    (* Print the interesting part *)
    match p with
    | Char c ->
      Buffer.add_char buf c;
      _move_x start_pos 1
    | String s ->
      Buffer.add_string buf s;
      (* We could use Bytes.unsafre_of_string as long as !string_len
         does not try to mutate the string (which it should have no
         reason to do), but just to be safe... *)
      let l = !_string_len (Bytes.of_string s) in
      _move_x start_pos l

  let buf_out ?(indent=0) buf b =
    for i = 1 to indent do Buffer.add_char buf ' ' done;
    let _pos = M.fold (buf_out_aux ~indent buf) b.map origin in ()

  let buf_to_lines ?indent b =
    let buf = Buffer.create 42 in
    buf_out ?indent buf b;
    Buffer.contents buf

  let buf_output ?indent oc b =
    let buf = Buffer.create 42 in
    buf_out ?indent buf b;
    Buffer.output_buffer oc buf

end

(* find [c] in [s], starting at offset [i] *)
let rec _find s c i =
  if i >= String.length s then None
  else if s.[i] = c then Some i
  else _find s c (i+1)

(* sequence of lines *)
let rec _lines s i k = match _find s '\n' i with
  | None ->
      if i<String.length s then k (String.sub s i (String.length s-i))
  | Some j ->
      let s' = String.sub s i (j-i) in
      k s';
      _lines s (j+1) k

module Box = struct
  type grid_shape =
    | GridNone
    | GridBars

  type 'a shape =
    | Empty
    | Text of string list  (* list of lines *)
    | Frame of 'a
    | Pad of position * 'a (* vertical and horizontal padding *)
    | Grid of grid_shape * 'a array array
    | Tree of int * 'a * 'a array

  type t = {
    shape : t shape;
    size : position lazy_t;
  }

  let size box = Lazy.force box.size

  let shape b = b.shape

  let _array_foldi f acc a =
    let acc = ref acc in
    Array.iteri (fun i x -> acc := f !acc i x) a;
    !acc

  let _dim_matrix m =
    if Array.length m = 0 then {x=0;y=0}
    else {y=Array.length m; x=Array.length m.(0); }

  let _map_matrix f m =
    Array.map (Array.map f) m

  (* height of a line composed of boxes *)
  let _height_line a =
    _array_foldi
      (fun h i box ->
        let s = size box in
        max h s.y
      ) 0 a

  (* how large is the [i]-th column of [m]? *)
  let _width_column m i =
    let acc = ref 0 in
    for j = 0 to Array.length m - 1 do
      acc := max !acc (size m.(j).(i)).x
    done;
    !acc

  (* width and height of a column as an array *)
  let _dim_vertical_array a =
    let w = ref 0 and h = ref 0 in
    Array.iter
      (fun b ->
        let s = size b in
        w := max !w s.x;
        h := !h + s.y
      ) a;
    {x= !w; y= !h;}

  (* from a matrix [m] (line,column), return two arrays [lines] and [columns],
    with [col.(i)] being the start offset of column [i] and
    [lines.(j)] being the start offset of line [j].
    Those arrays have one more slot to indicate the end position.
    @param bars if true, leave space for bars between lines/columns *)
  let _size_matrix ~bars m =
    let dim = _dim_matrix m in
    (* +1 is for keeping room for the vertical/horizontal line/column *)
    let additional_space = if bars then 1 else 0 in
    (* columns *)
    let columns = Array.make (dim.x + 1) 0 in
    for i = 0 to dim.x - 1 do
      columns.(i+1) <- columns.(i) + (_width_column m i) + additional_space
    done;
    (* lines *)
    let lines = Array.make (dim.y + 1) 0 in
    for j = 1 to dim.y do
      lines.(j) <- lines.(j-1) + (_height_line m.(j-1)) + additional_space
    done;
    (* no trailing bars, adjust *)
    columns.(dim.x) <- columns.(dim.x) - additional_space;
    lines.(dim.y) <- lines.(dim.y) - additional_space;
    lines, columns

  let _size = function
    | Empty -> origin
    | Text l ->
        let width = List.fold_left
          (fun acc line -> max acc (!_string_len (Bytes.unsafe_of_string line))) 0 l
        in
        { x=width; y=List.length l; }
    | Frame t ->
        let {x;y} = size t in
        { x=x+2; y=y+2; }
    | Pad (dim, b') ->
        let {x;y} = size b' in
        { x=x+2*dim.x; y=y+2*dim.y; }
    | Grid (style,m) ->
        let bars = match style with
          | GridBars -> true
          | GridNone -> false
        in
        let dim = _dim_matrix m in
        let lines, columns = _size_matrix ~bars m in
        { y=lines.(dim.y); x=columns.(dim.x)}
    | Tree (indent, node, children) ->
        let dim_children = _dim_vertical_array children in
        let s = size node in
        { x=max s.x (dim_children.x+3+indent)
        ; y=s.y + dim_children.y
        }

  let _make shape =
    { shape; size=(lazy (_size shape)); }
end

let empty = Box._make Box.Empty

let line s =
  assert (_find s '\n' 0 = None);
  Box._make (Box.Text [s])

let text s =
  let acc = ref [] in
  _lines s 0 (fun x -> acc := x :: !acc);
  Box._make (Box.Text (List.rev !acc))

let sprintf format =
  let buffer = Buffer.create 64 in
  Printf.kbprintf
    (fun fmt -> text (Buffer.contents buffer))
    buffer
    format

let lines l =
  assert (List.for_all (fun s -> _find s '\n' 0 = None) l);
  Box._make (Box.Text l)

let int_ x = line (string_of_int x)
let float_ x = line (string_of_float x)
let bool_ x = line (string_of_bool x)

let frame b =
  Box._make (Box.Frame b)

let pad' ~col ~lines b =
  assert (col >=0 || lines >= 0);
  if col=0 && lines=0
    then b
    else Box._make (Box.Pad ({x=col;y=lines}, b))

let pad b = pad' ~col:1 ~lines:1 b

let hpad col b = pad' ~col ~lines:0 b
let vpad lines b = pad' ~col:0 ~lines b

let grid ?(pad=fun b->b) ?(bars=true) m =
  let m = Box._map_matrix pad m in
  Box._make (Box.Grid ((if bars then Box.GridBars else Box.GridNone), m))

let init_grid ?bars ~line ~col f =
  let m = Array.init line (fun j-> Array.init col (fun i -> f ~line:j ~col:i)) in
  grid ?bars m

let vlist ?pad ?bars l =
  let a = Array.of_list l in
  grid ?pad ?bars (Array.map (fun line -> [| line |]) a)

let hlist ?pad ?bars l =
  grid ?pad ?bars [| Array.of_list l |]

let hlist_map ?bars f l = hlist ?bars (List.map f l)
let vlist_map ?bars f l = vlist ?bars (List.map f l)
let grid_map ?bars f m = grid ?bars (Array.map (Array.map f) m)

let grid_text ?(pad=fun x->x) ?bars m =
  grid_map ?bars (fun x -> pad (text x)) m

let transpose m =
  let dim = Box._dim_matrix m in
  Array.init dim.x
    (fun i -> Array.init dim.y (fun j -> m.(j).(i)))

let tree ?(indent=1) node children =
  let children =
    List.filter
    (function
      | {Box.shape=Box.Empty; _} -> false
      | _ -> true
    ) children
  in
  match children with
  | [] -> node
  | _::_ ->
    let children = Array.of_list children in
    Box._make (Box.Tree (indent, node, children))

let mk_tree ?indent f root =
  let rec make x = match f x with
    | b, [] -> b
    | b, children -> tree ?indent b (List.map make children)
  in
  make root

(** {2 Rendering} *)

let _write_vline ~out pos n =
  for j=0 to n-1 do
    Output.put_char out (_move_y pos j) '|'
  done

let _write_hline ~out pos n =
  for i=0 to n-1 do
    Output.put_char out (_move_x pos i) '-'
  done

(* render given box on the output, starting with upper left corner
    at the given position. [expected_size] is the size of the
    available surrounding space. [offset] is the offset of the box
    w.r.t the surrounding box *)
let rec _render ?(offset=origin) ?expected_size ~out b pos =
  match Box.shape b with
    | Box.Empty -> ()
    | Box.Text l ->
        List.iteri
          (fun i line ->
            Output.put_string out (_move_y pos i) line
          ) l
    | Box.Frame b' ->
        let {x;y} = Box.size b' in
        Output.put_char out pos '+';
        Output.put_char out (_move pos (x+1) (y+1)) '+';
        Output.put_char out (_move pos 0 (y+1)) '+';
        Output.put_char out (_move pos (x+1) 0) '+';
        _write_hline ~out (_move_x pos 1) x;
        _write_hline ~out (_move pos 1 (y+1)) x;
        _write_vline ~out (_move_y pos 1) y;
        _write_vline ~out (_move pos (x+1) 1) y;
        _render ~out b' (_move pos 1 1)
    | Box.Pad (dim, b') ->
        let expected_size = Box.size b in
        _render ~offset:(_add dim offset) ~expected_size ~out b' (_add pos dim)
    | Box.Grid (style,m) ->
        let dim = Box._dim_matrix m in
        let bars = match style with
          | Box.GridNone -> false
          | Box.GridBars -> true
        in
        let lines, columns = Box._size_matrix ~bars m in

        (* write boxes *)
        for j = 0 to dim.y - 1 do
          for i = 0 to dim.x - 1 do
            let expected_size = {
              x=columns.(i+1)-columns.(i);
              y=lines.(j+1)-lines.(j);
            } in
            let pos' = _move pos (columns.(i)) (lines.(j)) in
            _render ~expected_size ~out m.(j).(i) pos'
          done;
        done;

        let len_hlines, len_vlines = match expected_size with
          | None -> columns.(dim.x), lines.(dim.y)
          | Some {x;y} -> x,y
        in

        (* write frame if needed *)
        begin match style with
        | Box.GridNone -> ()
        | Box.GridBars ->
          for j=1 to dim.y - 1 do
            _write_hline ~out (_move pos (-offset.x) (lines.(j)-1)) len_hlines
          done;
          for i=1 to dim.x - 1 do
            _write_vline ~out (_move pos (columns.(i)-1) (-offset.y)) len_vlines
          done;
          for j=1 to dim.y - 1 do
            for i=1 to dim.x - 1 do
              Output.put_char out (_move pos (columns.(i)-1) (lines.(j)-1)) '+'
            done
          done
        end
    | Box.Tree (indent, n, a) ->
        _render ~out n pos;
        (* star position for the children *)
        let pos' = _move pos indent (Box.size n).y in
        Output.put_char out (_move_x pos' ~-1) '`';
        assert (Array.length a > 0);
        let _ = Box._array_foldi
          (fun pos' i b ->
            Output.put_string out pos' "+- ";
            if i<Array.length a-1
              then (
                _write_vline ~out (_move_y pos' 1) ((Box.size b).y-1)
              );
            _render ~out b (_move_x pos' 2);
            _move_y pos' (Box.size b).y
          ) pos' a
        in
        ()

let render out b =
  _render ~out b origin

let to_string b =
  let buf, out = Output.make_buffer () in
  render out b;
  Output.buf_to_lines buf

let output ?indent oc b =
  let buf, out = Output.make_buffer () in
  render out b;
  Output.buf_output ?indent oc buf;
  flush oc

(** {2 Simple Structural Interface} *)

type 'a ktree = unit -> [`Nil | `Node of 'a * 'a ktree list]

module Simple = struct
  type t =
    [ `Empty
    | `Pad of t
    | `Text of string
    | `Vlist of t list
    | `Hlist of t list
    | `Table of t array array
    | `Tree of t * t list
    ]

  let rec to_box = function
    | `Empty -> empty
    | `Pad b -> pad (to_box b)
    | `Text t -> text t
    | `Vlist l -> vlist (List.map to_box l)
    | `Hlist l -> hlist (List.map to_box l)
    | `Table a -> grid (Box._map_matrix to_box a)
    | `Tree (b,l) -> tree (to_box b) (List.map to_box l)

  let rec of_ktree t = match t () with
    | `Nil -> `Empty
    | `Node (x, l) -> `Tree (x, List.map of_ktree l)

  let rec map_ktree f t = match t () with
    | `Nil -> `Empty
    | `Node (x, l) -> `Tree (f x, List.map (map_ktree f) l)

  let sprintf format =
    let buffer = Buffer.create 64 in
    Printf.kbprintf
      (fun fmt -> `Text (Buffer.contents buffer))
      buffer
      format

  let render out x = render out (to_box x)
  let to_string x = to_string (to_box x)
  let output ?indent out x = output ?indent out (to_box x)
end
