
(* This file is free software, part of Zipperposition. See file "license" for more details. *)

(** {1 Manipulate proofs} *)

open Libzipperposition

module Loc = ParseLocation
module Hash = CCHash

type form = TypedSTerm.t
type 'a sequence = ('a -> unit) -> unit

let section = Util.Section.make ~parent:Const.section "proof"

type rule_info =
  | I_subst of Substs.t
  | I_pos of Position.t
  | I_comment of string

type rule = {
  rule_name: string;
  rule_info: rule_info list;
}

let mk_rule ?(subst=[]) ?(pos=[]) ?(comment=[]) name =
  let rec map_append f l1 l2 = match l1 with
    | [] -> l2
    | x :: l1' -> map_append f l1' (f x :: l2)
  in
  { rule_name=name;
    rule_info=
      []
      |> map_append (fun x->I_subst x) subst
      |> map_append (fun x->I_pos x) pos
      |> map_append (fun x->I_comment x) comment;
  }

(** Classification of proof steps *)
type kind =
  | Inference of rule
  | Simplification of rule
  | Esa of rule
  | Assert of StatementSrc.t
  | Goal of StatementSrc.t
  | Trivial (** trivial, or trivial within theories *)

type 'clause result =
  | Form of form
  | Clause of 'clause

(** A proof step, without the conclusion *)
type +'a t = {
  id: int; (* unique ID *)
  kind: kind;
  parents: 'a of_ list;
}

(** Proof Step with its conclusion *)
and +'a of_ = {
  step: 'a t;
  result : 'a result
}

type 'a proof = 'a of_

let result p = p.result
let step p = p.step
let kind p = p.kind
let parents p = p.parents

let result_as_clause p = match p.result with
  | Clause c -> c
  | Form _ -> invalid_arg "result_as_clause"

let result_as_form p = match p.result with
  | Clause _ -> invalid_arg "result_as_form"
  | Form f -> f

(** {2 Constructors and utils} *)

let id_ = ref 0
let get_id_ () =
  let n = !id_ in
  incr id_;
  n

let mk_trivial = {id=get_id_(); parents=[]; kind=Trivial; }

let mk_step_ kind parents =
  { id=get_id_(); kind; parents; }

let mk_assert src = mk_step_ (Assert src) []

let mk_goal src = mk_step_ (Goal src) []

let mk_assert' ?loc ~file ~name () =
  let src = StatementSrc.make ?loc ~name file in
  mk_assert src

let mk_goal' ?loc ~file ~name () =
  let src = StatementSrc.make ?loc ~name file in
  mk_goal src

let mk_inference ~rule parents =
  mk_step_ (Inference rule) parents

let mk_simp ~rule parents =
  mk_step_ (Simplification rule) parents

let mk_esa ~rule parents =
  mk_step_ (Esa rule) parents

let mk_f_ step res = {step; result=Form res; }

let mk_f_trivial = mk_f_ mk_trivial

let mk_f_inference ~rule f parents =
  let step = mk_inference ~rule parents in
  mk_f_ step f

let mk_f_simp ~rule f parents =
  let step = mk_simp ~rule parents in
  mk_f_ step f

let mk_f_esa ~rule f parents =
  let step = mk_esa ~rule parents in
  mk_f_ step f

let mk_c step c = {step; result=Clause c; }

let adapt_c p c =
  { p with result=Clause c; }

let adapt_f p f =
  { p with result=Form f; }

let is_trivial = function
  | {kind=Trivial; _} -> true
  | _ -> false

let rule p = match p.kind with
  | Trivial
  | Assert _
  | Goal _-> None
  | Esa rule
  | Simplification rule
  | Inference rule -> Some rule

let is_assert p = match p.kind with Assert _ -> true | _ -> false
let is_goal p = match p.kind with Goal _ -> true  | _ -> false

let equal p1 p2 = p1.id=p2.id
let compare p1 p2 = CCInt.compare p1.id p2.id
let hash p = p.id

(** {2 Proof traversal} *)

module Tbl = CCHashtbl.Make(CCInt)

let traverse_depth ?(traversed=Tbl.create 16) proof k =
  let depth = ref 0 in
  let current, next = ref [proof], ref [] in
  while !current <> [] do
    (* exhaust the current layer of proofs to explore *)
    while !current <> [] do
      let proof = List.hd !current in
      current := List.tl !current;
      if Tbl.mem traversed proof.id then ()
      else (
        Tbl.add traversed proof.id ();
        (* traverse premises first *)
        List.iter (fun proof' -> next := proof'.step :: !next) proof.parents;
        (* yield proof *)
        k (proof, !depth);
      )
    done;
    (* explore next layer *)
    current := !next;
    next := [];
    incr depth;
  done

let traverse ?traversed proof k =
  traverse_depth ?traversed proof (fun (p, _depth) -> k p)

let distance_to_goal p =
  let best_distance = ref None in
  traverse_depth p
    (fun (p', depth) ->
       if is_goal p'
       then
         let new_best = match !best_distance with
           | None -> depth
           | Some depth' -> max depth depth'
         in
         best_distance := Some new_best);
  !best_distance

let to_seq proof = Sequence.from_iter (fun k -> traverse proof k)

(* Depth of a proof, ie max distance between the root and any axiom *)
let depth proof =
  let explored = Tbl.create 11 in
  let depth = ref 0 in
  let q = Queue.create () in
  Queue.push (proof, 0) q;
  while not (Queue.is_empty q) do
    let (p, d) = Queue.pop q in
    if Tbl.mem explored proof.id then () else begin
      Tbl.add explored proof.id ();
      begin match p.kind with
        | Assert _ | Goal _ | Trivial -> depth := max d !depth
        | Inference _ | Esa _ | Simplification _ -> ()
      end;
      (* explore parents *)
      List.iter (fun p' -> Queue.push (p'.step, d+1) q) p.parents
    end
  done;
  !depth

(** {2 IO} *)

let pp_rule out r =
  let pp_info out = function
    | I_subst s -> Format.fprintf out " with @[%a@]" Substs.pp s
    | I_pos p -> Format.fprintf out " at @[%a@]" Position.pp p
    | I_comment s -> Format.fprintf out " %s" s
  in
  let pp_list pp = Util.pp_list ~sep:"" pp in
  Format.fprintf out
    "@[%s%a@]" r.rule_name (pp_list pp_info) r.rule_info

let pp_kind_tstp out k =
  match k with
  | Assert src
  | Goal src ->
      let file = src.StatementSrc.file in
      begin match src.StatementSrc.name with
      | None -> Format.fprintf out "file('%s')" file
      | Some name -> Format.fprintf out "file('%s', '%s')" file name
      end
  | Inference rule ->
      Format.fprintf out "inference(%a, [status(thm)])" pp_rule rule
  | Simplification rule ->
      Format.fprintf out "inference(%a, [status(thm)])" pp_rule rule
  | Esa rule ->
      Format.fprintf out "inference(%a, [status(esa)])" pp_rule rule
  | Trivial ->
      Format.fprintf out "trivial([status(thm)])"

let pp_kind out k =
  match k with
  | Assert src
  | Goal src ->
      let is_goal = match k with Goal _ -> true | _ -> false in
      let file = src.StatementSrc.file in
      begin match src.StatementSrc.name with
      | None ->
          Format.fprintf out "'%s'%s" file (if is_goal then " (goal)" else "")
      | Some name ->
          Format.fprintf out "'%s' in '%s'%s" name file
            (if is_goal then " (goal)" else "")
      end
  | Inference rule ->
      Format.fprintf out "inf %a" pp_rule rule
  | Simplification rule ->
      Format.fprintf out "simp %a" pp_rule rule
  | Esa rule ->
      Format.fprintf out "esa %a" pp_rule rule
  | Trivial -> CCFormat.string out "trivial"
