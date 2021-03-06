open StdLabels

let default_rng = let open Gsl.Rng in
  env_setup ();
  make (default ())


(** FIXME(superbobry): remove this once gsl-1.14.0 is out. *)
module Combi = struct
  open Bigarray

  type t = {
    n    : int;
    k    : int;
    data : (int, int_elt, c_layout) Bigarray.Array1.t
  }

  external _init_first : t -> unit = "ml_gsl_combination_init_first"
  external _init_last  : t -> unit = "ml_gsl_combination_init_last"

  let make n k =
    let c = { n; k; data = Array1.create int c_layout k } in begin
      _init_first c;
      c
    end

  let to_array { data; _ } =
    let len = Array1.dim data in
    Array.init len ~f:(Array1.get data)

  external prev : t -> unit = "ml_gsl_combination_prev"
  external next : t -> unit = "ml_gsl_combination_next"

  external _valid : t -> bool = "ml_gsl_combination_valid"

  let valid c =
    let open Gsl in
    try _valid c
    with Error.Gsl_exn (Error.FAILURE, _) -> false
end

let sqr x = x *. x
let cube x = x *. x *. x

let is_nan (x : float) = x <> x
let is_not_nan (x : float) = x = x

let round x = int_of_float (floor (x +. 0.5))

let invalid_arg s = raise (Invalid_argument s)


module Array = struct
  include Array

  let sort_index ~cmp vs =
    let n     = length vs in
    let order = Array.make n 0 in begin
      for i = 0 to n - 1 do
        Array.unsafe_set order i i
      done;

      sort ~cmp:(fun i j -> cmp (unsafe_get vs i) (unsafe_get vs j)) order;
      order
    end

  let count ~f =
    fold_left ~f:(fun acc v -> acc + if f v then 1 else 0) ~init:0

  let exists ~f vs =
    let rec loop i =
      if i < 0
      then false
      else f (unsafe_get vs i) || loop (pred i)
    in loop (length vs - 1)

  let for_all ~f vs =
    let rec loop i =
      if i < 0
      then true
      else f (unsafe_get vs i) && loop (pred i)
    in loop (length vs - 1)

  let partition ~f vs =
    let (l, r) = fold_left vs
        ~init:([], [])
        ~f:(fun (l, r) x -> if f x then (x :: l, r) else (l, x :: r))
    in (Array.of_list l, Array.of_list r)
end

module Matrix_flat = struct
  include Gsl.Matrix_flat

  let exists m ~f =
    let (nrow, ncol) = dims m in
    let rec loop_columns i j =
      if j < 0
      then false
      else f (get m i j) || loop_columns i (pred j)
    and loop_rows i =
      if i < 0
      then false
      else loop_columns i (ncol - 1) || loop_rows (pred i)
    in loop_rows (nrow - 1)

  let map m ~f =
    let (nrow, ncol) = dims m in begin
      for i = 0 to nrow - 1 do
        for j = 0 to ncol - 1 do
          set m i j (f (get m i j))
        done
      done
    end

  let row_sums m =
    let (nrow, ncol) = dims m in
    let res = create ~init:0. 1 nrow in begin
      for i = 0 to nrow - 1 do
        for j = 0 to ncol - 1 do
          set res 0 i (get res 0 i +. get m i j)
        done
      done; res
    end
  and col_sums m =
    let (nrow, ncol) = dims m in
    let res = create ~init:0. 1 ncol in begin
      for j = 0 to ncol - 1 do
        for i = 0 to nrow - 1 do
          set res 0 j (get res 0 j +. get m i j)
        done
      done; res
    end

  let sum m =
    let (nrow, ncol) = dims m in
    let acc = ref 0. in begin
      for i = 0 to nrow - 1 do
        for j = 0 to ncol - 1 do
          acc := !acc +. get m i j
        done
      done; ! acc
    end

  let power m =
    let open Gsl.Blas_flat in
    let mul a b =
      assert (dims a = dims b);
      let (w, h) = dims a in
      let res = create ~init:0. w h in begin
        gemm ~ta:NoTrans ~tb:NoTrans ~alpha:1. ~beta:1. ~a ~b ~c:res;
        res
      end
    in

    let rec go m = function
      | 1 -> m
      | k ->
        let m2 = go m (k / 2) in
        let mm = mul m2 m2 in
        if k mod 2 = 0
        then mm
        else mul mm m
    in go m
end
