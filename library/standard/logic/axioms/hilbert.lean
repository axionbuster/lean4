-- Copyright (c) 2014 Microsoft Corporation. All rights reserved.
-- Released under Apache 2.0 license as described in the file LICENSE.
-- Authors: Leonardo de Moura, Jeremy Avigad

import logic.classes.inhabited logic.connectives.eq logic.connectives.quantifiers
import data.subtype data.sum

using subtype

-- logic.axioms.hilbert
-- ====================

-- Follows Coq.Logic.ClassicalEpsilon (but our definition of "inhabited" is the
-- constructive one).

axiom strong_indefinite_description {A : Type} (P : A → Prop) (H : nonempty A) :
  {x : A | (∃x : A, P x) → P x}

-- In the presence of classical logic, we could prove this from the weaker
-- axiom indefinite_description {A : Type} {P : A->Prop} (H : ∃x, P x) : { x : A | P x }

theorem nonempty_imp_inhabited {A : Type} (H : nonempty A) : inhabited A :=
let u : {x : A | nonempty A → true} := strong_indefinite_description (λa, true) H in
inhabited_intro (elt_of u)

theorem inhabited_exists {A : Type} {P : A → Prop} (H : ∃x, P x) : inhabited A :=
nonempty_imp_inhabited (obtain w Hw, from H, exists_intro w trivial)


-- the Hilbert epsilon function
-- ----------------------------

definition epsilon {A : Type} {H : inhabited A} (P : A → Prop) : A :=
let u : {x : A | (∃y, P y) → P x} :=
  strong_indefinite_description P (inhabited_imp_nonempty H) in
elt_of u

theorem epsilon_spec_aux {A : Type} (H : inhabited A) (P : A → Prop) (Hex : ∃y, P y) :
    P (@epsilon A H P) :=
let u : {x : A | (∃y, P y) → P x} :=
  strong_indefinite_description P (inhabited_imp_nonempty H) in
has_property u Hex

theorem epsilon_spec {A : Type} {P : A → Prop} (Hex : ∃y, P y) :
    P (@epsilon A (inhabited_exists Hex) P) :=
epsilon_spec_aux (inhabited_exists Hex) P Hex

theorem epsilon_singleton {A : Type} (a : A) : @epsilon A (inhabited_intro a) (λ x, x = a) = a :=
epsilon_spec (exists_intro a (refl a))


-- the axiom of choice
-- -------------------

theorem axiom_of_choice {A : Type} {B : A → Type} {R : Πx, B x → Prop} (H : ∀x, ∃y, R x y) :
  ∃f, ∀x, R x (f x) :=
let f [inline] := λx, @epsilon _ (inhabited_exists (H x)) (λy, R x y),
    H [inline] := take x, epsilon_spec (H x)
in exists_intro f H

theorem skolem {A : Type} {B : A → Type} {P : Πx, B x → Prop} :
  (∀x, ∃y, P x y) ↔ ∃f, (∀x, P x (f x)) :=
iff_intro
  (assume H : (∀x, ∃y, P x y), axiom_of_choice H)
  (assume H : (∃f, (∀x, P x (f x))),
    take x, obtain (fw : ∀x, B x) (Hw : ∀x, P x (fw x)), from H,
      exists_intro (fw x) (Hw x))
