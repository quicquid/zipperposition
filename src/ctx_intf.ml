(*
Zipperposition: a functional superposition prover for prototyping
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

open Logtk

module type S = sig
  val ord : unit -> Ordering.t
  (** current ordering on terms *)

  val selection_fun : unit -> Selection.t
  (** selection function for clauses *)

  val set_selection_fun : Selection.t -> unit

  val set_ord : Ordering.t -> unit

  val skolem : Skolem.ctx

  val signature : unit -> Signature.t
  (** Current signature *)

  val complete : unit -> bool
  (** Is completeness preserved? *)

  val renaming : Substs.Renaming.t

  (** {2 Utils} *)

  val compare : FOTerm.t -> FOTerm.t -> Comparison.t
  (** Compare two terms *)

  val select : Selection.t

  val renaming_clear : unit  -> Substs.Renaming.t
  (** Obtain the global renaming. The renaming is cleared before
      it is returned. *)

  val lost_completeness : unit -> unit
  (** To be called when completeness is not preserved *)

  val is_completeness_preserved : unit -> bool
  (** Check whether completeness was preserved so far *)

  val add_signature : Signature.t -> unit
  (** Merge  the given signature with the context's one *)

  val find_signature : Symbol.t -> Type.t option
  (** Find the type of the given symbol *)

  val find_signature_exn : Symbol.t -> Type.t
  (** Unsafe version of {!find_signature}.
      @raise Not_found for unknown symbols *)

  val update_prec : Symbol.t Sequence.t -> unit
  (** Update the precedence of the ordering {!ord} *)

  val declare : Symbol.t -> Type.t -> unit
  (** Declare the type of a symbol (updates signature) *)

  val on_new_symbol : (Symbol.t * Type.t) Signal.t
  val on_signature_update : Signature.t Signal.t

  val ad_hoc_symbols : unit -> Symbol.Set.t
  (** Current set of ad-hoc symbols *)

  val add_ad_hoc_symbols : Symbol.t Sequence.t -> unit
  (** Declare that some symbols are "ad hoc", ie they are not really
      polymorphic and should not be considered as such *)

  val add_constr : int -> Precedence.Constr.t -> unit
  (** XXX caution, dangerous: add a new constraint to the precedence.
      If you don't know what you are doing, it might change the precedence
      into an incompatible one. *)

  (** {2 Literals} *)

  module Lit : sig
    val from_hooks : unit -> Literal.Conv.hook_from list
    val add_from_hook : Literal.Conv.hook_from -> unit

    val to_hooks : unit -> Literal.Conv.hook_to list
    val add_to_hook : Literal.Conv.hook_to -> unit

    val of_form : Formula.FO.t -> Literal.t
      (** @raise Invalid_argument if the formula is not atomic *)

    val to_form : Literal.t -> Formula.FO.t
  end

  (** {2 Theories} *)

  module Theories : sig
    module AC : sig
      val on_add : Theories.AC.t Signal.t

      val add : ?proof:Proof.t list -> ty:Type.t -> Symbol.t -> unit

      val is_ac : Symbol.t -> bool

      val find_proof : Symbol.t -> Proof.t list
        (** Recover the proof for the AC-property of this symbol.
            @raise Not_found if the symbol is not AC *)

      val symbols : unit -> Symbol.Set.t
        (** set of AC symbols *)

      val symbols_of_terms : FOTerm.t Sequence.t -> Symbol.Set.t
        (** set of AC symbols occurring in the given term *)

      val symbols_of_forms : Formula.FO.t Sequence.t -> Symbol.Set.t
        (** Set of AC symbols occurring in the given formula *)

      val proofs : unit -> Proof.t list
        (** All proofs for all AC axioms *)

      val exists_ac : unit -> bool
        (** Is there any AC symbol? *)
    end

    module TotalOrder : sig
      val on_add : Theories.TotalOrder.t Signal.t

      val is_less : Symbol.t -> bool

      val is_lesseq : Symbol.t -> bool

      val find : Symbol.t -> Theories.TotalOrder.t
        (** Find the instance that corresponds to this symbol.
            @raise Not_found if the symbol is not part of any instance. *)

      val find_proof : Theories.TotalOrder.t -> Proof.t list
        (** Recover the proof for the given total ordering
            @raise Not_found if the instance cannot be found*)

      val is_order_symbol : Symbol.t -> bool
        (** Is less or lesseq of some instance? *)

      val axioms : less:Symbol.t -> lesseq:Symbol.t -> PFormula.t list
        (** Axioms that correspond to the given symbols being a total ordering.
            The proof of the axioms will be "axiom" *)

      val exists_order : unit -> bool
        (** Are there some known ordering instances? *)

      val add : ?proof:Proof.t list ->
                less:Symbol.t -> lesseq:Symbol.t -> ty:Type.t ->
                Theories.TotalOrder.t * [`New | `Old]
        (** Pair of symbols that constitute an ordering.
            @return the corresponding instance and a flag to indicate
              whether the instance was already present. *)

      val add_tstp : unit -> Theories.TotalOrder.t * [`New | `Old]
        (** Specific version of {!add_order} for $less and $lesseq *)
    end
  end

  (** {2 Induction} *)

  module Induction : sig
    (** {6 Inductive Types} *)

    type bool_lit = BBox_intf.bool_lit

    type constructor = Symbol.t * Type.t
    (** Constructor for an inductive type *)

    type inductive_type = private {
      pattern : Type.t;  (* type, possibly with free variables *)
      constructors : constructor list;
    }
    (** An inductive type, along with its covering,disjoint constructors *)

    val on_new_inductive_ty : inductive_type Signal.t
    (** Triggered every time a new inductive type is declared *)

    val inductive_ty_seq : inductive_type Sequence.t
    (** Sequence of all inductive types declared so far *)

    val declare_ty : Type.t -> constructor list -> inductive_type
    (** Declare the given inductive type.
        @raise Failure if the type is already declared
        @raise Invalid_argument if the list of constructors is empty. *)

    val is_inductive_type : Type.t -> bool
    (** [is_inductive_type ty] holds iff [ty] is an instance of some
        registered type (registered with {!declare_ty}). *)

    val is_constructor_sym : Symbol.t -> bool
    (** true if the symbol is an inductive constructor (zero, successor...) *)

    val contains_inductive_types : FOTerm.t -> bool
    (** [true] iff the term contains at least one subterm with
        an inductive type *)

    (** {6 Inductive Constants} *)

    type cst = private FOTerm.t
    (** A ground term of an inductive type. It must correspond to a
        term built with the corresponding {!inductive_type} only.
        For instance, a constant of type [nat] should be equal to
        [s^n(0)] in any model. *)

    module Cst : BBox_intf.TERM with type t = cst

    type case = private FOTerm.t
    (** A member of a coverset *)

    module Case : BBox_intf.TERM with type t = case

    type sub_cst = private FOTerm.t
    (** A subterm of some {!case} that has the same (inductive) type *)

    module Sub : BBox_intf.TERM with type t = sub_cst

    val is_blocked : FOTerm.t -> bool
    (** Some terms that could be inductive constants are {b blocked}. In
        particular, constructors, but also skolem constants introduced by
        calls to {!cover_set}. *)

    val set_blocked : FOTerm.t -> unit
    (** Declare that the given term cannot be candidate for induction *)

    val declare : FOTerm.t -> unit
    (** Check whether the  given term can be an inductive constant,
        and if possible, adds it to the set of inductive constants.
        Requirements: it must be ground, and its type must be a
        known {!inductive type}.

        @raise Invalid_argument if the parent isn't inductive or the
          term is non-ground *)

    val on_new_inductive : cst Signal.t
    (** Triggered with new inductive constants *)

    val as_inductive : FOTerm.t -> cst option
    val is_inductive : FOTerm.t -> bool
    (** Check whether the given constant is ready for induction, and
        downcast it if it's the case *)

    val is_inductive_symbol : Symbol.t -> bool
    (** Head symbol of some inductive (ground) term?*)

    module SubCstSet : Set.S with type elt = sub_cst

    type cover_set = {
      cases : case list; (* all cases *)
      rec_cases : case list; (* recursive cases *)
      base_cases : case list;  (* non-recursive (base) cases *)
      sub_constants : SubCstSet.t;  (* leaves of recursive cases *)
    }

    val as_sub_constant : FOTerm.t -> sub_cst option
    val is_sub_constant : FOTerm.t -> bool
    (** Is the term a constant that was created within a cover set? *)

    val is_sub_constant_of : FOTerm.t -> cst -> bool
    val as_sub_constant_of : FOTerm.t -> cst -> sub_cst option
    (** downcasts iff [t] is a sub-constant of [cst] *)

    val is_case : FOTerm.t -> bool
    val as_case : FOTerm.t -> case option

    val dominates : Symbol.t -> Symbol.t -> bool
    (** [dominates s1 s2] true iff s2 is one of the sub-cases of s1 *)

    val inductive_cst_of_sub_cst : sub_cst -> cst * case
    (** [inductive_cst_of_sub_cst t] finds a pair [c, t'] such
        that [c] is an inductive const, [t'] belongs to a coverset
        of [c], and [t] is a sub-constant within [t'].
        @raise Not_found if [t] isn't an inductive constant *)

    val cases : ?which:[`Rec|`Base|`All] -> cover_set -> case Sequence.t
    (** Cases of the cover set *)

    val sub_constants : cover_set -> sub_cst Sequence.t
    (** All sub-constants of a given inductive constant *)

    val sub_constants_case : case -> sub_cst Sequence.t
    (** All sub-constants that are subterms of a specific case *)

    val cover_set : ?depth:int -> cst -> cover_set * [`New|`Old]
    (** [cover_set t] gives a set of ground terms [[t1,...,tn]] with fresh
        constants inside (that are not declared as inductive!) such that
        [bigor_{i in 1...n} t=ti] is the skolemized version of the
        exhaustivity axiom on [t]'s type.
        @param depth (default 1) depth of cover terms; the deeper, the more
          covering terms there will be. *)

    val cover_sets : cst -> cover_set Sequence.t
    (** All current cover sets of [cst] *)

    val on_new_cover_set : (cst * cover_set) Signal.t
    (** triggered with [t, set] when [set] is a new cover set for [t] *)

    module Set : Sequence.Set.S with type elt = cst
    (** Set of constants *)

    module Seq : sig
      val ty : inductive_type Sequence.t
      val cst : cst Sequence.t

      val constructors : Symbol.t Sequence.t
      (** All known constructors *)
    end
  end

  (** {2 Booleans Literals} *)

  module BoolLit
    : BBox.S
    with module I = Induction.Cst
    and module Sub = Induction.Sub
    and module Case = Induction.Case
end
