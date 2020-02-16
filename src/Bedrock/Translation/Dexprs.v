Require Import Coq.Lists.List.
Require Import bedrock2.WeakestPreconditionProperties.
Require Import coqutil.Word.Interface.
Require Import Crypto.Util.ListUtil.
Import ListNotations.

(* Proofs about [WeakestPrecondition.dexprs] *)
(* TODO: add to bedrock2? *)
(* TODO: some of these may be unused *)
Section Dexprs.
  Context {p : Semantics.parameters} {ok : @Semantics.parameters_ok p}.

  Local Ltac propers_step :=
      match goal with
      | H : WeakestPrecondition.literal ?v _
        |- WeakestPrecondition.literal ?v _ =>
        eapply Proper_literal
      | H : WeakestPrecondition.get ?l ?x _
        |- WeakestPrecondition.get ?l ?x _ =>
        eapply Proper_get
      | H : WeakestPrecondition.load ?s ?m ?a _
        |- WeakestPrecondition.load ?s ?m ?a _ =>
        eapply Proper_load
      | H : WeakestPrecondition.store ?s ?m ?a ?v _
        |- WeakestPrecondition.store ?s ?m ?a ?v _ =>
        eapply Proper_store
      | H : WeakestPrecondition.expr ?m ?l ?e _
        |- WeakestPrecondition.expr ?m ?l ?e _ =>
        eapply Proper_expr
      | H : WeakestPrecondition.list_map ?f ?xs _
        |- WeakestPrecondition.list_map ?f ?xs _ =>
        eapply Proper_list_map
      | H : WeakestPrecondition.cmd ?call ?c ?t ?m ?l _
        |- WeakestPrecondition.cmd ?call ?c ?t ?m ?l _ =>
        eapply Proper_cmd
      | H : WeakestPrecondition.cmd ?call ?c ?t ?m ?l _
        |- WeakestPrecondition.cmd ?call ?c ?t ?m ?l _ =>
        eapply Proper_cmd
      end; [ repeat intro .. | eassumption ]; cbv beta in *.

    Local Ltac propers :=
      propers_step;
      match goal with
      | _ => solve [propers]
      | H : _ |- _ => apply H; solve [eauto]
      | _ => congruence
      end.

    Local Ltac peel_expr :=
      progress (
          repeat
            progress match goal with
                     | H : WeakestPrecondition.expr ?m ?l ?e _ |- _ =>
                       match goal with
                       | |- WeakestPrecondition.expr m l e _ => idtac
                       | _ =>
                         apply expr_sound with (mc:=MetricLogging.EmptyMetricLog) in H;
                         destruct H as [? [_ [_ H] ] ]
                       end
                     end).
    
    Lemma expr_comm m l x1 :
      forall x2 post,
        WeakestPrecondition.expr
          m l x1 (fun y : Semantics.word => WeakestPrecondition.expr m l x2 (post y)) ->
        WeakestPrecondition.expr
          m l x2 (fun y : Semantics.word => WeakestPrecondition.expr m l x1 (fun y2 => post y2 y)).
    Proof.
      induction x1;
        cbn [WeakestPrecondition.expr WeakestPrecondition.expr_body]; intros;
          repeat match goal with
                 | _ => progress cbv [WeakestPrecondition.literal dlet.dlet] in *
                 | _ => solve [eauto]
                 | H: WeakestPrecondition.get _ _ _ |- _ =>
                   inversion H; destruct_head'_and; clear H
                 | H: WeakestPrecondition.load _ _ _ _ |- _ =>
                   inversion H; destruct_head'_and; clear H
                 | |- WeakestPrecondition.get _ _ _ =>
                   eexists; split; [ eassumption | ]
                 | |- WeakestPrecondition.load _ _ _ _ =>
                   eexists; split; [ eassumption | ]
                 | IH : _ |- WeakestPrecondition.expr _ _ _ _ => eapply IH
                 | |- WeakestPrecondition.expr _ _ _ _ => propers_step
                 end.
    Qed.

    Lemma dexprs_cons_iff m l :
      forall e es v vs,
        WeakestPrecondition.dexprs m l (e :: es) (v :: vs) <->
        (WeakestPrecondition.expr m l e (eq v)
         /\ WeakestPrecondition.dexprs m l es vs).
    Proof.
      cbv [WeakestPrecondition.dexprs].
      induction es; split; intros;
        repeat match goal with
               | _ => progress cbn [WeakestPrecondition.list_map
                                      WeakestPrecondition.list_map_body] in *
               | _ => progress cbv beta in *
               | H : _ :: _ = _ :: _ |- _ => inversion H; clear H; subst
               | |- _ /\ _ => split
               | _ => progress destruct_head'_and
               | _ => reflexivity
               | _ => solve [propers]
               | _ => peel_expr
               end.
      eapply IHes with (vs := tl vs).
      propers_step. peel_expr.
      destruct vs; cbn [tl]; propers.
    Qed.

    Lemma dexprs_cons_nil m l e es :
      WeakestPrecondition.dexprs m l (e :: es) [] -> False.
    Proof.
      cbv [WeakestPrecondition.dexprs].
      induction es; intros;
        repeat match goal with
               | _ => progress cbn [WeakestPrecondition.list_map
                                      WeakestPrecondition.list_map_body] in *
               | _ => congruence 
               | _ => solve [propers]
               | _ => apply IHes
               | _ => peel_expr
               end.
      propers_step. peel_expr. propers.
    Qed.

    Lemma dexprs_app_l m l es1 :
      forall es2 vs,
        WeakestPrecondition.dexprs m l (es1 ++ es2) vs ->
        (WeakestPrecondition.dexprs m l es1 (firstn (length es1) vs)) /\
        (WeakestPrecondition.dexprs m l es2 (skipn (length es1) vs)).
    Proof.
      induction es1; intros.
      { cbn [Datatypes.length skipn firstn]; rewrite app_nil_l in *.
        split; eauto; reflexivity. }
      { destruct vs; rewrite <-app_comm_cons in *;
          [ match goal with H : _ |- _ => apply dexprs_cons_nil in H; tauto end | ].
        cbn [Datatypes.length skipn firstn].
        rewrite !dexprs_cons_iff in *.
        destruct_head'_and.
        repeat split; try eapply IHes1; eauto. }
    Qed.

    Lemma dexprs_length m l :
      forall vs es,
        WeakestPrecondition.dexprs m l es vs ->
        length es = length vs.
    Proof.
      induction vs; destruct es; intros;
        repeat match goal with
               | _ => progress cbn [Datatypes.length]
               | _ => progress destruct_head'_and
               | H : _ |- _ => apply dexprs_cons_nil in H; tauto
               | H : _ |- _ => apply dexprs_cons_iff in H
               | _ => reflexivity
               | _ => congruence
               end.
      rewrite IHvs; auto.
    Qed.
End Dexprs.