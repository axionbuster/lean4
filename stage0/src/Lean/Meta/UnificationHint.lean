/-
Copyright (c) 2020 Microsoft Corporation. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Leonardo de Moura
-/
import Lean.Meta.DiscrTree
import Lean.Meta.LevelDefEq

namespace Lean.Meta

structure UnificationHintEntry where
  keys        : Array DiscrTree.Key
  val         : Name

structure UnificationHints where
  discrTree       : DiscrTree Name := DiscrTree.empty

instance : Inhabited UnificationHints where
  default := {}

def UnificationHints.add (hints : UnificationHints) (e : UnificationHintEntry) : UnificationHints :=
  { hints with discrTree := hints.discrTree.insertCore e.keys e.val }

builtin_initialize unificationHintExtension : SimplePersistentEnvExtension UnificationHintEntry UnificationHints ←
  registerSimplePersistentEnvExtension {
    name          := `unifHints
    addEntryFn    := UnificationHints.add
    addImportedFn := fun es => (mkStateFromImportedEntries UnificationHints.add {} es)
  }

structure UnificationConstraint where
  lhs : Expr
  rhs : Expr

structure UnificationHint where
  pattern     : UnificationConstraint
  constraints : List UnificationConstraint

private partial def decodeUnificationHint (e : Expr) : ExceptT MessageData Id UnificationHint := do
  unless e.isAppOfArity `Lean.UnificationHint.mk 2 do
    throw m!"invalid unification hint, unexpected term{indentExpr e}"
  return {
    pattern     := (← decodeConstraint (e.getArg! 1))
    constraints := (← decodeConstraints (e.getArg! 0))
  }
where
  decodeConstraint (c : Expr) := do
    unless c.isAppOfArity `Lean.UnificationConstraint.mk 3 do
      throw m!"invalid unification hint constraint, unexpected term{indentExpr c}"
    return { lhs := c.getArg! 1, rhs := c.getArg! 2 }
  decodeConstraints (cs : Expr) := do
    if cs.isAppOfArity `List.nil 1 then
      return []
    else if cs.isAppOfArity `List.cons 3 then
      return (← decodeConstraint (cs.getArg! 1)) :: (← decodeConstraints (cs.getArg! 2))
    else
      throw m!"invalid unification hint constraints, unexpected list term{indentExpr cs}"

private partial def validateHint (declName : Name) (hint : UnificationHint) : MetaM Unit := do
  hint.constraints.forM fun c => do
    unless (← isDefEq c.lhs c.rhs) do
      throwError! "invalid unification hint '{declName}', failed to unify constraint left-hand-side{indentExpr c.lhs}\nwith right-hand-side{indentExpr c.rhs}"
  unless (← isDefEq hint.pattern.lhs hint.pattern.rhs) do
    throwError! "invalid unification hint '{declName}', failed to unify pattern left-hand-side{indentExpr hint.pattern.lhs}\nwith right-hand-side{indentExpr hint.pattern.rhs}"

def addUnificationHint (declName : Name) : MetaM Unit := do
  let info ← getConstInfo declName
  -- check type
  forallTelescopeReducing info.type fun _ type =>
    unless type.isConstOf `Lean.UnificationHint do
      throwError! "invalid unification hint '{declName}', unexpected type{indentExpr type}"
  match info.value? with
  | none => throwError! "invalid unification hint '{declName}', it must be a definition"
  | some val =>
    let (_, _, body) ← lambdaMetaTelescope val
    match decodeUnificationHint body with
    | Except.error msg => throwError msg
    | Except.ok hint =>
      validateHint declName hint
      let keys ← DiscrTree.mkPath hint.pattern.lhs
      modifyEnv fun env => unificationHintExtension.addEntry env { keys := keys, val := declName }

builtin_initialize
  registerBuiltinAttribute {
    name  := `unificationHint
    descr := "unification hint"
    add   := fun declName args persistent => do
      if args.hasArgs then throwError "invalid attribute 'unificationHint', unexpected argument"
      unless persistent do throwError "invalid attribute 'unificationHint', must be persistent"
      addUnificationHint declName |>.run
      pure ()
  }

def tryUnificationHints (t s : Expr) : MetaM Bool := do
  unless (← read).config.unificationHints do
    return false
  if t.isMVar then
    return false
  let hints := unificationHintExtension.getState (← getEnv)
  let candidates ← hints.discrTree.getMatch t
  for candidate in candidates do
    if (← tryCandidate candidate) then
      return true
  return false
where
  isDefEqPattern p e :=
    withReducible <| Meta.isExprDefEqAux p e

  tryCandidate candidate : MetaM Bool := commitWhen do
    trace[Meta.isDefEq.hint]! "trying hint {candidate} at {t} =?= {s}"
    let cinfo ← getConstInfo candidate
    let hint? ← withConfig (fun cfg => { cfg with unificationHints := false }) do
      let us ← cinfo.lparams.mapM fun _ => mkFreshLevelMVar
      let val := cinfo.instantiateValueLevelParams us
      let (_, _, body) ← lambdaMetaTelescope val
      match decodeUnificationHint body with
      | Except.error _ => return none
      | Except.ok hint =>
        if (← isDefEqPattern hint.pattern.lhs t <&&> isDefEqPattern hint.pattern.rhs s) then
          return some hint
        else
          return none
    match hint? with
    | none      => return false
    | some hint =>
      trace[Meta.isDefEq.hint]! "{candidate} succeeded, applying constraints"
      for c in hint.constraints do
        unless (← Meta.isExprDefEqAux c.lhs c.rhs) do
          return false
      return true

end Lean.Meta
