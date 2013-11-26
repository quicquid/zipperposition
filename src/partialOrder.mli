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

(** {1 Partial Ordering}

A dense partial ordering on objects, implemented with a matrix. It allows
one to combine partial orders, to complete it using a total order, to
compute its transitive closure...
*)

module type S = sig
  type elt
    (** Elements that can be compared *)

  type t
    (** the partial order on elements of type [elt] *)

  val create : elt list -> t
    (** build an empty partial order for the list of elements *)

  val copy : t -> t
    (** Copy of the partial order *)

  val extend : t -> elt list -> t
    (** Add new elements to the ordering, creating a new ordering.
        They will not be ordered at all w.r.t previous elements. *)

  val is_total : t -> bool
    (** Is the ordering total (i.e. each pair of elements it contains
        is ordered)? *)

  val enrich : t -> (elt -> elt -> Comparison.t) -> unit
    (** Compare unordered pairs with the given partial order function. *)

  val complete : t -> (elt -> elt -> int) -> unit
    (** [complete po f] completes [po] using the function [f]
        elements to compare still unordered pairs. If [f x y] returns 0
        then [x] and [y] are still incomparable in [po] afterwards.
        If the given comparison function is not total, the ordering may still
        not be complete. The comparison function [f] is assumed to be such
        that [transitive_closure f] is a partial order. *)

  val compare : t -> elt -> elt -> Comparison.t
    (** compare two elements in the ordering. *)

  val elements : t -> elt list
    (** Elements of the partial order. If the ordering is total,
        they will be sorted by decreasing order (maximum first) *)
end

(** {2 Functor Implementation} *)

module type ELEMENT = sig
  type t

  val eq : t -> t -> bool
    (** Equality function on elements *)

  val hash : t -> int
    (** Hashing on elements *)
end

module Make(E : ELEMENT) : S with type elt = E.t
