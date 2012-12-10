(*
Zipperposition: a functional superposition prover for prototyping
Copyright (C) 2012 Simon Cruanes

This is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version.

This is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA
02110-1301 USA.
*)

(** Recognition of theories *)

open Types
open Symbols

(* ----------------------------------------------------------------------
 * recognize some shapes of clauses
 * ---------------------------------------------------------------------- *)

val is_RR_horn_clause : hclause -> bool
  (** Recognized whether the clause is a Range-Restricted Horn clause *)

val is_definition : hclause -> (term * term) option
  (** Check whether the clause defines a symbol, e.g.
      subset(X,Y) = \forall Z(Z in X -> Z in Y). It means the LHS
      is a flat symbol with variables, and all variables in RHS
      are also in LHS *)

val is_rewrite_rule : hclause -> (term * term) list
  (** More general than definition. It means the clause is an
      equality where all variables in RHS are also in LHS. It
      can return two rewrite rules if the clause can be oriented
      in both ways, e.g. associativity axiom. *)

val is_pos_eq : hclause -> (term * term) option
  (** Recognize whether the clause is a positive unit equality. *)


val is_functional_symbol : hclause -> [ `Functional of symbol | `None ]
  (** detect whether the clause is "p(x,y,z) & p(x,y,z') => z=z'", and
      returns p in this case *)

val is_total_symbol : hclause -> [ `Total of (symbol * symbol) | `None ]
  (** detect whether the clause is "p(x,y,f(x,y))", and returns (p,f)
      in this case *)

(* ----------------------------------------------------------------------
 * add some axioms when detecting some axioms
 * ---------------------------------------------------------------------- *)

val detect_total_relations : ord:ordering -> hclause list -> hclause list
  (** adds axioms for all total functional relations:
      if  p(x,y,f(x,y))  and  p(x,y,z) & p(x,y,z') => z=z
      we add  p(x,y,z) <=> (z = f(x,y))  as a definition of p *)
