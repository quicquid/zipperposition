
(*
Copyright (c) 2013, Simon Cruanes
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

Redistributions of source code must retain the above copyright notice, this
list of conditions and the following disclaimer.  Redistributions in binary
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

(** {1 Prolog-like Terms}. *)

type location = ParseLocation.t

type t = {
  term : view;
  loc : location option;
}
and view =
  | Var of string                   (** variable *)
  | Int of Z.t                      (** integer *)
  | Rat of Q.t                      (** rational *)
  | Const of Symbol.t               (** constant *)
  | App of t * t list               (** apply term *)
  | Bind of Symbol.t * t list * t   (** bind n variables *)
  | List of t list                  (** special constructor for lists *)
  | Record of (string * t) list * t option  (** extensible record *)
  | Column of t * t                 (** t:t (useful for typing, e.g.) *)

type term = t

let view t = t.term

let __to_int = function
  | Var _ -> 0
  | Int _ -> 1
  | Rat _ -> 2
  | Const _ -> 3
  | App _ -> 4
  | Bind _ -> 5
  | List _ -> 6
  | Record _ -> 7
  | Column _ -> 8

let rec cmp t1 t2 = match t1.term, t2.term with
  | Var s1, Var s2 -> String.compare s1 s2
  | Int i1, Int i2 -> Z.compare i1 i2
  | Rat n1, Rat n2 -> Q.compare n1 n2
  | Const s1, Const s2 -> Symbol.cmp s1 s2
  | App (s1,l1), App (s2, l2) ->
    let c = cmp s1 s2 in
    if c = 0
    then Util.lexicograph cmp l1 l2
    else c
  | Bind (s1, v1, t1), Bind (s2, v2, t2) ->
    let c = Symbol.cmp s1 s2 in
    if c = 0
    then
      let c' = cmp t1 t2 in
      if c' = 0
      then Util.lexicograph cmp v1 v2
      else c'
    else c
  | Column (x1,y1), Column (x2,y2) ->
    let c = cmp x1 x2 in
    if c = 0 then cmp y1 y2 else c
  | _ -> __to_int t1.term - __to_int t2.term

let eq t1 t2 = cmp t1 t2 = 0

let rec hash t = match t.term with
  | Var s -> Hash.hash_string s
  | Int i -> Z.hash i
  | Rat n -> Hash.hash_string (Q.to_string n)  (* TODO: find better *)
  | Const s -> Symbol.hash s
  | App (s, l) ->
    Hash.hash_list hash (hash s) l
  | List l -> Hash.hash_list hash 0x42 l
  | Bind (s,v,t') ->
    let h = Hash.combine (Symbol.hash s) (hash t') in
    Hash.hash_list hash h v
  | Record (l, rest) ->
    Hash.hash_list
      (fun (n,t) -> Hash.combine (Hash.hash_string n) (hash t))
      (match rest with None -> 13 | Some r -> hash r) l
  | Column (x,y) -> Hash.combine (hash x) (hash y)

let __make ?loc view = {term=view; loc;}

let var ?loc ?ty s = match ty with
  | None -> __make ?loc (Var s)
  | Some ty -> __make ?loc (Column (__make (Var s), ty))
let int_ i = __make (Int i)
let of_int i = __make (Int (Z.of_int i))
let rat n = __make (Rat n)
let app ?loc s l = match l with
  | [] -> s
  | _::_ -> __make ?loc (App(s,l))
let const ?loc s = __make ?loc (Const s)
let bind ?loc s v l = match v with
  | [] -> l
  | _::_ -> __make ?loc (Bind(s,v,l))
let list_ ?loc l = __make ?loc (List l)
let nil = list_ []
let record ?loc l ~rest =
  let l = List.sort (fun (n1,_)(n2,_) -> String.compare n1 n2) l in
  __make ?loc (Record (l, rest))
let column ?loc x y = __make ?loc (Column(x,y))
let at_loc ~loc t = {t with loc=Some loc; }

let wildcard = const Symbol.Base.wildcard

let is_var = function
  | {term=Var _} -> true
  | _ -> false

module Set = Sequence.Set.Make(struct
  type t = term
  let compare = cmp
end)
module Map = Sequence.Map.Make(struct
  type t = term
  let compare = cmp
end)

module Tbl = Hashtbl.Make(struct
  type t = term
  let hash = hash
  let equal = eq
end)

module Seq = struct
  let subterms t k =
    let rec iter t =
      k t;
      match t.term with
      | Var _ | Int _ | Rat _ | Const _ -> ()
      | List l
      | App (_, l) -> List.iter iter l
      | Bind (_, v, t') -> List.iter iter v; iter t'
      | Record (l, rest) ->
          begin match rest with | None -> () | Some r -> iter r end;
          List.iter (fun (_,t') -> iter t') l
      | Column(x,y) -> k x; k y
    in iter t

  let vars t = subterms t |> Sequence.filter is_var

  let add_set s seq =
    Sequence.fold (fun set x -> Set.add x set) s seq

  let subterms_with_bound t k =
    let rec iter bound t =
      k (t, bound);
      match t.term with
      | Var _ | Int _ | Rat _ | Const _ -> ()
      | List l
      | App (_, l) -> List.iter (iter bound) l
      | Bind (_, v, t') ->
          (* add variables of [v] to the set *)
          let bound' = List.fold_left
            (fun set v -> add_set set (vars v))
            bound v
          in
          iter bound' t'
      | Record (l, rest) ->
          begin match rest with | None -> () | Some r -> iter bound r end;
          List.iter (fun (_,t') -> iter bound t') l
      | Column(x,y) -> k (x, bound); k (y, bound)
    in iter Set.empty t

  let free_vars t =
    subterms_with_bound t
      |> Sequence.fmap (fun (v,bound) ->
          if is_var v && not (Set.mem v bound)
          then Some v
          else None)

  let symbols t = subterms t
      |> Sequence.fmap (function
        | {term=Const s} -> Some s
        | {term=Bind (s, _, _)} -> Some s
        | _ -> None)
end

let ground t = Seq.vars t |> Sequence.is_empty

let close_all s t =
  let vars = Seq.free_vars t
    |> Seq.add_set Set.empty
    |> Set.elements
  in
  bind s vars t

let rec pp buf t = match t.term with
  | Var s -> Buffer.add_string buf s
  | Int i -> Buffer.add_string buf (Z.to_string i)
  | Rat i -> Buffer.add_string buf (Q.to_string i)
  | Const s -> Symbol.pp buf s
  | List l ->
      Buffer.add_char buf '[';
      Util.pp_list ~sep:"," pp buf l;
      Buffer.add_char buf ']'
  | App (s, l) ->
      pp buf s;
      Buffer.add_char buf '(';
      Util.pp_list ~sep:"," pp buf l;
      Buffer.add_char buf ')'
  | Bind (s, vars, t') ->
      Symbol.pp buf s;
      Buffer.add_char buf '[';
      Util.pp_list ~sep:"," pp buf vars;
      Buffer.add_string buf "]:";
      pp buf t'
  | Record (l, None) ->
    Buffer.add_char buf '{';
    Util.pp_list (fun buf (s,t') -> Printf.bprintf buf "%s:%a" s pp t') buf l;
    Buffer.add_char buf '}'
  | Record (l, Some r) ->
    Buffer.add_char buf '{';
    Util.pp_list (fun buf (s,t') -> Printf.bprintf buf "%s:%a" s pp t') buf l;
    Printf.bprintf buf " | %a}" pp r
  | Column(x,y) ->
      pp buf x;
      Buffer.add_char buf ':';
      pp buf y

let to_string = Util.on_buffer pp
let fmt fmt t = Format.pp_print_string fmt (to_string t)

(** {2 Visitor} *)

class virtual ['a] visitor = object (self)
  method virtual var : ?loc:location -> string -> 'a
  method virtual int_ : ?loc:location -> Z.t -> 'a
  method virtual rat_ : ?loc:location -> Q.t -> 'a
  method virtual const : ?loc:location -> Symbol.t -> 'a
  method virtual app : ?loc:location -> 'a -> 'a list -> 'a
  method virtual bind : ?loc:location -> Symbol.t -> 'a list -> 'a -> 'a
  method virtual list_ : ?loc:location -> 'a list -> 'a
  method virtual record : ?loc:location -> (string*'a) list -> 'a option -> 'a
  method virtual column : ?loc:location -> 'a -> 'a -> 'a
  method visit t =
    let loc = t.loc in
    match t.term with
    | Var s -> self#var ?loc s
    | Int n -> self#int_ ?loc n
    | Rat n -> self#rat_ ?loc n
    | Const s -> self#const ?loc s
    | App(f,l) -> self#app ?loc (self#visit f) (List.map self#visit l)
    | Bind (s, vars,t') ->
        self#bind ?loc s (List.map self#visit vars) (self#visit t')
    | List l -> self#list_ ?loc (List.map self#visit l)
    | Record (l, rest) ->
        let rest = Monad.Opt.map rest self#visit in
        let l = List.map (fun (n,t) -> n, self#visit t) l in
        self#record ?loc l rest
    | Column (a,b) -> self#column ?loc (self#visit a) (self#visit b)
end

class id_visitor = object
  inherit [t] visitor
  method var ?loc s = var ?loc s
  method int_ ?loc i = int_ i
  method rat_ ?loc n = rat n
  method const ?loc s = const ?loc s
  method app ?loc f l = app ?loc f l
  method bind ?loc s vars t = bind ?loc s vars t
  method list_ ?loc l = list_ ?loc l
  method record ?loc l rest = record ?loc l ~rest
  method column ?loc a b = column ?loc a b
end (** Visitor that maps the subterms into themselves *)

(** {2 TPTP} *)

module TPTP = struct
  let true_ = const Symbol.Base.true_
  let false_ = const Symbol.Base.false_

  let var = var
  let bind = bind
  let const = const
  let app = app

  let and_ ?loc l = app ?loc (const Symbol.Base.and_) l
  let or_ ?loc l = app ?loc (const Symbol.Base.or_) l
  let not_ ?loc a = app ?loc (const Symbol.Base.not_) [a]
  let equiv ?loc a b = app ?loc (const Symbol.Base.equiv) [a;b]
  let xor ?loc a b = app ?loc (const Symbol.Base.xor) [a;b]
  let imply ?loc a b = app ?loc (const Symbol.Base.imply) [a;b]
  let eq ?loc ?(ty=wildcard) a b = app ?loc (const Symbol.Base.eq) [ty;a;b]
  let neq ?loc ?(ty=wildcard) a b = app ?loc (const Symbol.Base.neq) [ty;a;b]
  let forall ?loc vars f = bind ?loc Symbol.Base.forall vars f
  let exists ?loc vars f = bind ?loc Symbol.Base.exists vars f
  let lambda ?loc vars f = bind ?loc Symbol.Base.lambda vars f

  let rec mk_fun_ty l ret = match l with
    | [] -> ret
    | a::l' -> app (const Symbol.Base.arrow) [a; mk_fun_ty l' ret]
  let tType = const Symbol.Base.tType
  let forall_ty vars t = bind Symbol.Base.forall_ty vars t

  let rec pp buf t = match t.term with
    | Var s -> Buffer.add_string buf s
    | Int i -> Buffer.add_string buf (Z.to_string i)
    | Rat i -> Buffer.add_string buf (Q.to_string i)
    | Const s -> Symbol.pp buf s
    | List l ->
        Buffer.add_char buf '[';
        Util.pp_list ~sep:"," pp buf l;
        Buffer.add_char buf ']'
    | App ({term=Const (Symbol.Conn Symbol.And)}, l) ->
      Util.pp_list ~sep:" & " pp_surrounded buf l
    | App ({term=Const (Symbol.Conn Symbol.Or)}, l) ->
      Util.pp_list ~sep:" | " pp_surrounded buf l
    | App ({term=Const (Symbol.Conn Symbol.Not)}, [a]) ->
      Printf.bprintf buf "~%a" pp_surrounded a
    | App ({term=Const (Symbol.Conn Symbol.Imply)}, [a;b]) ->
      Printf.bprintf buf "%a => %a" pp_surrounded a pp_surrounded b
    | App ({term=Const (Symbol.Conn Symbol.Xor)}, [a;b]) ->
      Printf.bprintf buf "%a <~> %a" pp_surrounded a pp_surrounded b
    | App ({term=Const (Symbol.Conn Symbol.Equiv)}, [a;b]) ->
      Printf.bprintf buf "%a <=> %a" pp_surrounded a pp_surrounded b
    | App ({term=Const (Symbol.Conn Symbol.Eq)}, [_;a;b]) ->
      Printf.bprintf buf "%a = %a" pp_surrounded a pp_surrounded b
    | App ({term=Const (Symbol.Conn Symbol.Neq)}, [_;a;b]) ->
      Printf.bprintf buf "%a != %a" pp_surrounded a pp_surrounded b
    | App ({term=Const (Symbol.Conn Symbol.Arrow)}, [ret;a]) ->
      Printf.bprintf buf "%a > %a" pp a pp ret
    | App ({term=Const (Symbol.Conn Symbol.Arrow)}, ret::l) ->
      Printf.bprintf buf "(%a) > %a" (Util.pp_list ~sep:" * " pp) l pp_surrounded ret
    | App (s, l) ->
        pp buf s;
        Buffer.add_char buf '(';
        Util.pp_list ~sep:"," pp buf l;
        Buffer.add_char buf ')'
    | Bind (s, vars, t') ->
        Symbol.TPTP.pp buf s;
        Buffer.add_char buf '[';
        Util.pp_list ~sep:"," pp_typed_var buf vars;
        Buffer.add_string buf "]:";
        pp_surrounded buf t'
    | Record _ -> failwith "cannot print records in TPTP"
    | Column(x,y) ->
        pp buf x;
        Buffer.add_char buf ':';
        pp buf y
  and pp_typed_var buf t = match t.term with
    | Column ({term=Var s}, {term=Const (Symbol.Conn Symbol.TType)})
    | Var s -> Buffer.add_string buf s
    | Column ({term=Var s}, ty) ->
      Printf.bprintf buf "%s:%a" s pp ty
    | _ -> assert false
  and pp_surrounded buf t = match t.term with
    | App ({term=Const (Symbol.Conn _)}, _::_::_)
    | Bind _ -> Buffer.add_char buf '('; pp buf t; Buffer.add_char buf ')'
    | _ -> pp buf t

  let to_string = Util.on_buffer pp
  let fmt fmt t = Format.pp_print_string fmt (to_string t)
end
