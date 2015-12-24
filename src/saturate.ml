
(* This file is free software, part of Zipperposition. See file "license" for more details. *)

(** {1 Main saturation algorithm.}
    It uses inference rules and simplification rules from Superposition. *)

open Logtk

module C = Clause
module O = Ordering
module PS = ProofState
module Sup = Superposition
module Sel = Selection

let stat_redundant_given = Util.mk_stat "redundant given clauses"
let stat_processed_given = Util.mk_stat "processed given clauses"

let section = Const.section

(** the status of a state *)
type szs_status =
  | Unsat of Proof.t
  | Sat
  | Unknown
  | Error of string
  | Timeout

let check_timeout = function
  | None -> false
  | Some timeout -> Unix.gettimeofday () > timeout

module type S = sig
  module Env : Env.S

  val given_clause_step : ?generating:bool -> int -> szs_status
  (** Perform one step of the given clause algorithm.
      It performs generating inferences only if [generating] is true (default);
      other parameters are the iteration number and the environment *)

  val given_clause :
    ?generating:bool -> ?steps:int -> ?timeout:float ->
    unit -> szs_status * int
  (** run the given clause until a timeout occurs or a result
      is found. It returns a tuple (new state, result, number of steps done).
      It performs generating inferences only if [generating] is true (default) *)

  (** Interreduction of the given state, without generating inferences. Returns
      the number of steps done for presaturation, with status of the set. *)
  val presaturate : unit -> szs_status * int
end

module Make(E : Env.S) = struct
  module Env = E

  (** One iteration of the main loop ("given clause loop") *)
  let given_clause_step ?(generating=true) num =
    Util.debugf ~section 4 "@[env for next given loop: %a@]" (fun k->k Env.pp ());
    E.step_init();
    (* select next given clause *)
    match Env.next_passive () with
    | None ->
        (* final check: might generate other clauses *)
        let clauses = Env.do_generate() in
        let clauses = clauses
                      |> Sequence.filter_map
                        (fun c ->
                           let _, c = Env.simplify c in
                           if Env.is_trivial c || Env.is_active c || Env.is_passive c
                           then None
                           else Some c
                        )
                      |> Sequence.to_list
        in
        if clauses=[]
        then Sat
        else (
          Util.debugf 2 ~section "@[<2>inferred new clauses@ @[<v>%a@]@]"
            (fun k->k (CCFormat.list Env.C.pp) clauses);
          Env.add_passive (Sequence.of_list clauses);
          Unknown
        )
    | Some c ->
        begin match Env.all_simplify c with
          | [] ->
              Util.incr_stat stat_redundant_given;
              Util.debugf ~section 2 "@[<2>given clause @[%a@]@ is redundant@]" (fun k->k Env.C.pp c);
              Unknown
          | l when List.exists Env.C.is_empty l ->
              (* empty clause found *)
              let proof = Env.C.proof (List.find Env.C.is_empty l) in
              Unsat proof
          | c :: l' ->
              (* put clauses of [l'] back in passive set *)
              Env.add_passive (Sequence.of_list l');
              (* process the clause [c] *)
              let new_clauses = CCVector.create () in
              assert (not (Env.is_redundant c));
              (* process the given clause! *)
              Util.incr_stat stat_processed_given;
              Util.debugf ~section 2 "@[================= step %5d  ===============@]"(fun k->k num);
              Util.debugf ~section 1 "@[<2>given: @[%a@]@]" (fun k->k Env.C.pp c);
              (* find clauses that are subsumed by given in active_set *)
              let subsumed_active = Env.C.CSet.to_seq (Env.subsumed_by c) in
              Env.remove_active subsumed_active;
              Env.remove_simpl subsumed_active;
              Env.remove_orphans subsumed_active; (* orphan criterion *)
              (* add given clause to simpl_set *)
              Env.add_simpl (Sequence.singleton c);
              (* simplify active set using c *)
              let simplified_actives, newly_simplified = Env.backward_simplify c in
              let simplified_actives = Env.C.CSet.to_seq simplified_actives in
              (* the simplified active clauses are removed from active set and
                 added to the set of new clauses. Their descendants are also removed
                 from passive set *)
              Env.remove_active simplified_actives;
              Env.remove_simpl simplified_actives;
              Env.remove_orphans simplified_actives;
              CCVector.append_seq new_clauses newly_simplified;
              (* add given clause to active set *)
              Env.add_active (Sequence.singleton c);
              (* do inferences between c and the active set (including c),
                 if [generate] is set to true *)
              let inferred_clauses = if generating
                then Env.generate c
                else Sequence.empty in
              (* simplification of inferred clauses w.r.t active set; only the non-trivial ones
                 are kept (by list-simplify) *)
              let inferred_clauses = Sequence.fmap
                  (fun c ->
                     let c = Env.forward_simplify c in
                     (* keep clauses  that are not redundant *)
                     if Env.is_trivial c || Env.is_active c || Env.is_passive c
                     then (
                       Util.debugf ~section 5 "clause %a is trivial, dump" (fun k->k Env.C.pp c);
                       None
                     ) else
                       Some c)
                  inferred_clauses
              in
              CCVector.append_seq new_clauses inferred_clauses;
              Util.debugf ~section 2 "@[<2>inferred new clauses:@ @[<v>%a@]@]"
                (fun k->k (CCFormat.seq Env.C.pp) (CCVector.to_seq new_clauses));
              (* add new clauses (including simplified active clauses) to passive set and simpl_set *)
              Env.add_passive (CCVector.to_seq new_clauses);
              (* test whether the empty clause has been found *)
              match Env.get_some_empty_clause () with
              | None -> Unknown
              | Some c -> Unsat (Env.C.proof c)
        end

  let given_clause ?(generating=true) ?steps ?timeout () =
    let rec do_step num =
      if check_timeout timeout then Timeout, num
      else match steps with
        | Some i when num >= i -> Unknown, num
        | _ ->
            begin
              (* some cleanup from time to time *)
              if num mod 1000 = 0 then (
                Util.debug ~section 1 "perform cleanup of passive set";
                Env.clean_passive ();
              );
              (* do one step *)
              let status = given_clause_step ~generating num in
              match status with
              | Sat | Unsat _ | Error _ -> status, num (* finished *)
              | Timeout -> assert false
              | Unknown -> do_step (num+1)
            end
    in
    do_step 0

  let presaturate () =
    given_clause ?steps:None ?timeout:None ~generating:false ()
end
