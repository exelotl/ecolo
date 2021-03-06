import macros

type
  Script* = proc():pointer {.nimcall.}
    ## A single part of a script (returns a pointer to the next part)

proc resume*(s: var Script) =
  ## Execute part of a script.
  s = cast[Script](s())

proc yieldScript*() = discard
  ## Yield from within a script.
  ## i.e. Return from the script and allow it to be resumed at this point at a later stage.


proc fixVars(node: NimNode): NimNode =
  ## Because `var foo = 10` fails to set foo to 10 on the second time it's encountered,
  ## we must break it up into `var foo: int; foo = 10`
  ## 
  ## Since this also has the effect of cloning the whole tree, we don't need to do it later.
  
  case node.kind
  of nnkVarSection:
    let decls = nnkVarSection.newTree()
    let asgns = newStmtList()
    for defs in node:
      var typ = defs[defs.len-2]
      var val = defs[defs.len-1]
      if val.kind != nnkEmpty:
        if typ.kind == nnkEmpty: typ = getType(val)      # infer type
      else:
        val = quote do:  # get the zero value (breaks if we use let, see NOTE below)
          var tmp: `typ`
          tmp
      let newDefs = defs.copy()
      newDefs[defs.len-2] = typ
      newDefs[defs.len-1] = newEmptyNode() # remove the assignment from the def
      decls.add(newDefs)
      asgns.add(newAssignment(defs[defs.len-3], val))  # queue the assignment
    result = newStmtList(decls, asgns)
  
  else:
    if node.len == 0:
      result = node
    else:
      result = copyNimNode(node)
      for child in node:
        # if child.kind == nnkVarSection:
          #   NOTE: this happens way too many times, which seems really suspicious
          #   (like, it's re-processing the newly created VarSections?)
          # echo "Recursing: ", child.kind, " ", child.len, " ", node.len, " ", result.len
        result.add(fixVars(child))


macro script*(nameIdent:untyped):untyped =
  ## Forward-declare a script.
  let scriptName = nameIdent.strVal
  let firstProc = ident("script" & scriptName & "Fn0")
  quote do:
    proc `firstProc`(): Script {.nimcall.}
    const `nameIdent`* = cast[Script](`firstProc`)

macro scriptImpl(nameIdent:untyped, body:typed):untyped =
  expectKind(nameIdent, nnkIdent)
  expectKind(body, nnkBlockStmt)
  
  let scriptName = nameIdent.strVal
  
  let procDefs = newStmtList()
  
  var procId = 0
  template newId():int =
    let id = procId
    inc(procId)
    id
  template newProcIdent():NimNode =
    ident("script" & scriptName & "Fn" & $newId())
  
  proc hasYields(node:NimNode):bool =
    ## Check if a tree contains any calls to yieldScript()
    if node.kind == nnkCall and node[0].strVal == "yieldScript":
      return true
    for child in node:
      if hasYields(child):
        return true
    return false
  
  proc mkProcDef(procIdent:NimNode, stmtList:NimNode, startIndex:int):NimNode =
    
    proc walkStmts(stmtList:NimNode, startIndex:int):NimNode =
      result = newStmtList()
      
      for i in startIndex..<stmtList.len:
        
        let node = stmtList[i].copy()
        # echo "Node ", $i, ": ", treerepr(node)
        
        if not hasYields(node):
          result.add(node)
          continue
        
        case node.kind
        of nnkCall:
          # When yieldScript() is encountered
          # - create a new proc which contains all subsequent nodes
          # - make this proc return a reference to the new proc
          # - break so that we stop adding stuff to this proc
          if node[0].strVal == "yieldScript":
            let nextProcIdent = newProcIdent()
            let nextProcDef = mkProcDef(nextProcIdent, stmtList, i+1)
            result.add quote do:
              return cast[Script](`nextProcIdent`)
            break
          else:
            result.add(node)
        
        of nnkStmtList:
          # When a stmtList is encountered
          # - copy all subsequent nodes into it, then recurse
          # - break so that we don't process the subsequent nodes twice
          for j in (i+1)..<stmtList.len:
            node.add(stmtList[j].copy())
          result.add(walkStmts(node, 0))
          break
        
        of nnkIfStmt:
          # When an ifStmt is encountered
          # - all subsequent nodes go into a new procedure
          # - the new procedure should be invoked at the end of each branch, unless the branch already returns somewhere (which could happen if it was generated by a while loop)
          # - recurse into each branch
          # - also this procedure should invoke the new procedure, in case none of the branches were executed.
          let nextProcIdent = newProcIdent()
          let nextProcDef = mkProcDef(nextProcIdent, stmtList, i+1)
          for branch in node:
            let k = (if branch.kind == nnkElse: 0 else: 1) # index of the body of the branch node
            if branch[k].kind != nnkStmtList:
              branch[k] = newStmtList(branch[k].copy())
            if branch[k].last.kind != nnkReturnStmt:
              branch[k].add(quote do: return `nextProcIdent`())
            branch[k] = walkStmts(branch[k], 0)
          result.add(node)
          result.add(quote do: return `nextProcIdent`())
          break
        
        of nnkWhileStmt:
          let whileProcIdent = newProcIdent()
          let nextProcIdent = newProcIdent()
          var whileCond = node[0].copy()
          var whileBody = node[1].copy()
          var whileStmts = (quote do:
            if `whileCond`:
              `whileBody`
              return `whileProcIdent`()
            return `nextProcIdent`()
          )
          # forward declare
          procDefs.add(quote do:
            proc `whileProcIdent`():Script {.nimcall.}
          )
          let nextProcDef = mkProcDef(nextProcIdent, stmtList, i+1)
          let whileProcDef = mkProcDef(whileProcIdent, whileStmts, 0)
          result.add(quote do: return `whileProcIdent`())
          break
          
        else:
          error("yieldScript() is not allowed in " & $node.kind, node)
        
      # end walkStmts
    
    let stmts = walkStmts(fixVars(stmtList), startIndex)
    # let stmts = walkStmts(stmtList, startIndex)
    
    if stmts.len == 0:
      stmts.add(nnkDiscardStmt.newTree(newEmptyNode()))
    
    result = quote do:
      proc `procIdent`():Script {.nimcall.} =
        `stmts`
    
    expectKind(result, nnkProcDef)
    procDefs.add(result)
  
  let firstProcDef = mkProcDef(newProcIdent(), body, 0)
  let firstProc = firstProcDef.name
  
  result = quote do:
    `procDefs`
    when not declared(`nameIdent`):
      const `nameIdent`* = cast[Script](`firstProc`)
  
  # echo repr(result)
  # echo "\n\n----------------\n"

macro script*(nameIdent:untyped, body:untyped): untyped =
  quote do:
    scriptImpl(`nameIdent`):
      block:
        `body`