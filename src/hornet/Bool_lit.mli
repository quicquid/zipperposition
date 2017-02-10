
(* This file is free software, part of Zipperposition. See file "license" for more details. *)

(** {1 Bool Literals} *)

(** The goal is to encapsulate objects into boolean literals that can be
    handled by the SAT solver *)

open Hornet_types

(** {2 Basics} *)

type atom = Hornet_types.bool_atom
type t = Hornet_types.bool_lit
type proof = Hornet_types.proof

include Msat.Formula_intf.S with type t := t and type proof := proof

type view =
  | Fresh of int
  | Box_clause of clause * bool_box_clause
  | Select_lit of clause * clause_idx * bool_select
  | Ground_lit of lit * bool_ground (* must be ground and positive *)

val atom : t -> atom
val view : t -> view
val sign : t -> bool

include Interfaces.PRINT with type t := t
include Interfaces.HASH with type t := t

(** {2 Constructors} *)

type state
(** A mutable state that is used to allocate fresh literals *)

val create_state: unit -> state

val of_atom : ?sign:bool -> atom -> t

val fresh : state -> t
val select_lit : state -> clause -> clause_idx -> t
val box_clause : state -> clause -> t
val ground : state -> lit -> t

(** {2 Boolean Clauses} *)

type bool_clause = t list

val pp_clause : bool_clause CCFormat.printer

(** {2 Boolean Trails} *)

type bool_trail = Hornet_types.bool_trail

val pp_trail : bool_trail CCFormat.printer

(** {2 Containers} *)

module Tbl : CCHashtbl.S with type key = t
