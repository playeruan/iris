
module main

struct Checker {
  mut: 
  table SymbolTable
  current_scope &Scope = &Scope{}
  ret_type_stack []Type = []Type{}
  span Span
  result CheckedAST
  loop_nesting i32
  generic_decls map[string]GenericDecl // map[name]Unresolved Generic Decl
  generic_subst map[string]Type // current generic substitutions
  generic_params []string // current valid generic types
  mono_cache MonomorphCache
  last_id i32
  last_type_id i32
}

struct CheckedAST {
  mut:
  ast []Stmt
  table SymbolTable
  scopes map[i32]&Scope // map[id]&Scope
  resolved map[i32]Type //map[id]Type
  implicit_casts map[i32]Type //map[id]Type
  monomorph_decls []Stmt //[]Decl
  resolved_calls map[i32]string
  resolved_structs map[i32]string
  enum_accesses []i32 // array of ids for accesses that have to be generated without the accessee
  type_id_map map[string]i32 // map[type name]type id
}

struct GenericDecl {
  type_params []string
  constraints []string
  decl Stmt
}

struct MonomorphCache {
  mut:
  funcs map[string]StmtDeclFunc
  structs map[string]StmtDeclStruct
}

@[noreturn]
fn (c Checker) checker_error(s string) {
  eprintln("${c.span} Checker Error -> ${s}")
	exit(1)
}

fn (mut c Checker) next_id() i32 {
  c.last_id++
  return c.last_id
}

fn (mut c Checker) next_type_id() i32 {
  c.last_type_id++
  return c.last_type_id
}

fn (mut c Checker) push_scope(stmt &Stmt) {
  c.result.scopes[stmt.id] = &Scope{parent: c.current_scope}
  c.current_scope = c.result.scopes[stmt.id] or {panic("wtf")}
}

fn (mut c Checker) pop_scope() {
  if c.current_scope.parent != none {
    c.current_scope = c.current_scope.parent
  } else {
    c.checker_error("trying to exit the root Scope")
  }
}

fn (mut c Checker) clone_stmt(s Stmt) Stmt {
  return match s {
    // saperlo prima che si poteva fare così
    StmtDeclFunc   { StmtDeclFunc{...s,   id: c.next_id(), block: c.clone_block(s.block)} }
    StmtDeclStruct { StmtDeclStruct{...s, id: c.next_id(), members: s.members.map(c.clone_stmt(it) as StmtDeclMember)} }
    StmtDeclMember { StmtDeclMember{...s, id: c.next_id()} }
    StmtDeclVar    { StmtDeclVar{...s,    id: c.next_id(), value: c.clone_expr(s.value)} }
    StmtReturn     { StmtReturn{...s,     id: c.next_id(), expr: c.clone_expr(s.expr)} }
    StmtExpr       { StmtExpr{...s,       id: c.next_id(), expr: c.clone_expr(s.expr)} }
    StmtAssign     { StmtAssign{...s,     id: c.next_id(), assignee: c.clone_expr(s.assignee), val: c.clone_expr(s.val)} }
    StmtBranch     {
      StmtBranch{...s, id: c.next_id(),
        if_guard:    c.clone_expr(s.if_guard),
        if_block:    c.clone_block(s.if_block),
        elif_guards: if s.elif_guards != none { s.elif_guards.map(c.clone_expr(it)) } else { none },
        elif_blocks: if s.elif_blocks != none { s.elif_blocks.map(c.clone_block(it)) } else { none },
        else_block:  if s.else_block  != none { c.clone_block(s.else_block) }          else { none },
      }
    }
    StmtWhile      { StmtWhile{...s, id: c.next_id(), guard: c.clone_expr(s.guard), block: c.clone_block(s.block)} }
    StmtBlock      { c.clone_block(s) }
    else           { s } // StmtNoop, StmtInclude, StmtDirectiveLink ec. 
  }
}

fn (mut c Checker) clone_block(b StmtBlock) StmtBlock {
  return StmtBlock{...b, id: c.next_id(), stmts: b.stmts.map(c.clone_stmt(it))}
}

fn (mut c Checker) clone_expr(e Expr) Expr {
  return match e {
    ExprVar            { ExprVar{...e,            id: c.next_id()} }
    ExprLiteralPrimitive { ExprLiteralPrimitive{...e, id: c.next_id()} }
    ExprLiteralNullptr { ExprLiteralNullptr{      id: c.next_id()} }
    ExprLiteralStruct  { ExprLiteralStruct{...e,  id: c.next_id(), argv: e.argv.map(c.clone_expr(it))} }
    ExprLiteralArray   { ExprLiteralArray{...e,   id: c.next_id(), argv: e.argv.map(c.clone_expr(it))} }
    ExprLiteralString  { ExprLiteralString{...e,  id: c.next_id() } }
    ExprGroup          { ExprGroup{...e,          id: c.next_id(), inner: c.clone_expr(e.inner)} }
    ExprCall           { ExprCall{...e,           id: c.next_id(), callee: c.clone_expr(e.callee), argv: e.argv.map(c.clone_expr(it)), generic_args: e.generic_args} }
    ExprIndex          { ExprIndex{...e,          id: c.next_id(), indexee: c.clone_expr(e.indexee), idx: c.clone_expr(e.idx)} }
    ExprAccess         { ExprAccess{...e,         id: c.next_id(), accessee: c.clone_expr(e.accessee)} }
    ExprRef            { ExprRef{...e,            id: c.next_id(), inner: c.clone_expr(e.inner)} }
    ExprDeref          { ExprDeref{...e,          id: c.next_id(), inner: c.clone_expr(e.inner)} }
    ExprUnary          { ExprUnary{...e,          id: c.next_id(), operand: c.clone_expr(e.operand)} }
    ExprBinary         { ExprBinary{...e,         id: c.next_id(), left: c.clone_expr(e.left), right: c.clone_expr(e.right)} }
    ExprCast           { ExprCast{...e,           id: c.next_id(), castee: c.clone_expr(e.castee)} }
    ExprType           { ExprType{...e,           id: c.next_id()} }
    ExprSizeof         { ExprSizeof{...e, id: c.next_id(), expr: c.clone_expr(e.expr)} }
    ExprTypeof         { ExprTypeof{...e, id: c.next_id(), expr: c.clone_expr(e.expr)} }
    ExprTypename       { ExprTypename{...e, id: c.next_id(), expr: c.clone_expr(e.expr)} }
  }
}

fn (mut c Checker) does_stmt_always_return(s Stmt) bool {
  return match s {
    StmtReturn {true}
    StmtBlock {
      mut always := false
      for s_ in s.stmts {
        always = always || c.does_stmt_always_return(s_)
      }
      always
    }
    StmtBranch {
      mut always := true
      always = always && c.does_stmt_always_return(s.if_block)
      if s.elif_guards != none {
        for elif_b in s.elif_blocks {
          always = always && c.does_stmt_always_return(elif_b)
        }
      }
      if s.else_block != none {
        always = always && c.does_stmt_always_return(s.else_block)
      } else {
        always = false
      }
      always
    }
    else {false}
  }
}

fn (mut c Checker) expr_only_contains_pure_functions(e Expr) (bool, string) {
  return match e {
    ExprCall {
      sym := c.current_scope.lookup_sym(e.callee.name) or {c.checker_error("undeclared function ${e.callee.name}")}
      for arg in e.argv {
        only, name := c.expr_only_contains_pure_functions(arg)
        if !only {return false, name}
      }
      if !sym.type.qualifs.contains(.pure) {
        return false, e.callee.name
      }
      return true, ""
    }
    ExprLiteralArray, ExprLiteralStruct {
      for arg in e.argv {
        only, name := c.expr_only_contains_pure_functions(arg)
        if !only {return false, name}
      }
      true, ""
    }
    ExprBinary {
      mut only, mut name := c.expr_only_contains_pure_functions(e.left)
      if !only {return false, name} 
      only, name = c.expr_only_contains_pure_functions(e.right)
      if !only {return false, name} 
      true, ""
    }
    ExprUnary {
      c.expr_only_contains_pure_functions(e.operand) 
    }
    ExprRef, ExprDeref, ExprGroup {
      c.expr_only_contains_pure_functions(e.inner) 
    }
    ExprSizeof {
      c.expr_only_contains_pure_functions(e.expr) 
    }
    ExprAccess {
      c.expr_only_contains_pure_functions(e.accessee) 
    }
    ExprIndex {
      c.expr_only_contains_pure_functions(e.indexee) 
    }
    ExprCast {
      c.expr_only_contains_pure_functions(e.castee) 
    }
    else {true, ""}
  }
}

fn (mut c Checker) stmt_only_calls_pure_functions(s Stmt) (bool, string) {
  return match s {
    StmtReturn, StmtExpr {c.expr_only_contains_pure_functions(s.expr)}
    StmtBlock {
      for s_ in s.stmts {
        only, name := c.stmt_only_calls_pure_functions(s_)
        if !only {return false, name}
      }
      true, ""
    }
    StmtDeclFunc {
      c.stmt_only_calls_pure_functions(s.block)
    }
    StmtDeclVar{
      c.expr_only_contains_pure_functions(s.value)
    }
    StmtAssign {
      c.expr_only_contains_pure_functions(s.val)
    }
    StmtWhile {
      mut only, mut name := c.expr_only_contains_pure_functions(s.guard)
      if !only {return false, name}
      only, name = c.stmt_only_calls_pure_functions(s.block)
      if !only {return false, name}
      true, ""
    }
    StmtFor {
      c.checker_error("unimplemented ${@LINE}")
    }
    StmtBranch {
      mut only, mut name := c.expr_only_contains_pure_functions(s.if_guard)
      if !only {return false, name}
      only, name = c.stmt_only_calls_pure_functions(s.if_block)
      if !only {return false, name}

      if s.elif_guards != none {
        for elif_g in s.elif_guards {
          only, name = c.expr_only_contains_pure_functions(elif_g)
          if !only {return false, name}
        }
        for elif_b in s.elif_blocks {
          only, name = c.stmt_only_calls_pure_functions(elif_b)
          if !only {return false, name}
        }
      }
      if s.else_block != none {
        only, name = c.stmt_only_calls_pure_functions(s.else_block)
        if !only {return false, name}
      }
      true, ""
    }
    else {true, ""}
  }
}

fn (mut c Checker) register_sym(s Symbol) {
  if s.name in c.current_scope.syms {
    c.checker_error("redefinition of symbol ${s.name}")
  }
  c.current_scope.syms[s.name] = c.resolve_sym_types(s)
}

fn (mut c Checker) register_generic(name string, type_params []string, constraints []string, decl Stmt) {
  if name in c.generic_decls {
    c.checker_error("redefinition of generic ${name}")
  }
  c.generic_decls[name] = GenericDecl {
    type_params: type_params
    constraints: constraints
    decl: decl
  }
}

fn (mut c Checker) enforce_constraints(name string, substitution map[string]Type) bool {
  gdecl := c.generic_decls[name] or {c.checker_error("undefined generic decl ${name}")} 
  for g_name, replacement in substitution {
    idx := gdecl.type_params.index(g_name)
    if idx == -1 {
      c.checker_error("unreachable @LINE")
    }
    constr_name := gdecl.constraints[idx] or {c.checker_error("unreachable @LINE")}
    if constr_name == "any" {continue}
    constr := c.table.constraints[constr_name]
    if !constr.contains(replacement) {
      c.checker_error("cannot replace generic ${g_name} with type ${Type(replacement)} that is not in constraint ${constr_name}")
    }
  }
  return false
}

fn (mut c Checker) begin_instantiation(gdecl GenericDecl, subst map[string]Type) (map[string]Type, []string, &Scope) {
  old_subst  := c.generic_subst.clone()
  old_params := c.generic_params.clone()
  old_scope  := c.current_scope
  c.generic_subst  = subst.clone()
  c.generic_params = gdecl.type_params
  c.current_scope  = c.table.root_scope
  return old_subst, old_params, old_scope
}

fn (mut c Checker) end_instantiation(old_subst map[string]Type, old_params []string, old_scope &Scope) {
  c.generic_subst  = old_subst.clone()
  c.generic_params = old_params
  c.current_scope  = old_scope
}

fn (mut c Checker) instantiate_func(name string, subst map[string]Type) !StmtDeclFunc {
  mangled := mangle_monomorph_name(name, subst)
  if mangled in c.mono_cache.funcs {
    return c.mono_cache.funcs[mangled]
  }

  gdecl := c.generic_decls[name] or {return error("no generic decl for ${name}")}
  mut cloned := c.clone_stmt(gdecl.decl) as StmtDeclFunc

  cloned = StmtDeclFunc{...cloned, sym: SymbolFunc{...(cloned.sym as SymbolFunc), name: mangled}}
  old_subst, old_params, old_scope := c.begin_instantiation(gdecl, subst)
  cloned = StmtDeclFunc{...cloned, sym: c.resolve_sym_types(cloned.sym)}
  
  c.mono_cache.funcs[mangled] = cloned
  
  c.check_stmt(cloned)
  c.end_instantiation(old_subst, old_params, old_scope)

  c.result.monomorph_decls << cloned
  return cloned 
}

fn (mut c Checker) instantiate_struct(name string, subst map[string]Type) !StmtDeclStruct {
  mangled := mangle_monomorph_name(name, subst)
  if mangled in c.mono_cache.structs {
    return c.mono_cache.structs[mangled]
  }

  gdecl := c.generic_decls[name] or {return error("no generic decl for ${name}")}
  mut cloned := c.clone_stmt(gdecl.decl) as StmtDeclStruct

  cloned = StmtDeclStruct{...cloned, sym: SymbolStruct{...(cloned.sym as SymbolStruct), name: mangled, type: TypeStruct{name: mangled}}}
  old_subst, old_params, old_scope := c.begin_instantiation(gdecl, subst)

  c.table.structs[mangled] = cloned.sym as SymbolStruct
  c.mono_cache.structs[mangled] = cloned

  cloned = StmtDeclStruct{...cloned, sym: c.resolve_sym_types(cloned.sym)}

  c.table.structs[mangled] = cloned.sym as SymbolStruct
  c.mono_cache.structs[mangled] = cloned

  c.result.monomorph_decls << cloned

  c.mono_cache.structs[mangled] = cloned
  c.check_stmt(cloned)
  c.end_instantiation(old_subst, old_params, old_scope)

  return cloned 
}

fn (mut c Checker) resolve_type(t Type) Type {
  if t is TypeGeneric {
    if t.name in c.generic_subst {
      sub := c.generic_subst[t.name] or {c.checker_error("unreachable ${@LINE}")}
      mut both_qualifs := sub.qualifs.clone()
      both_qualifs << t.qualifs
      return sub.with_qualifs(both_qualifs)
    }
    return TypeGeneric{name: t.name} 
  }

  if t is TypeUnresolved {
    if t.name in c.table.enums {
      sym := c.table.enums[t.name]
      return TypeEnum{qualifs: t.qualifs, name: t.name, as: sym.type.as}
    }
    if t.name in c.table.structs || t.name in c.generic_decls {
      if t.generic_args.len > 0 {
        resolved_args := t.generic_args.map(c.resolve_type(it))
        gdecl := c.generic_decls[t.name] or { c.checker_error("${t.name} is not a generic type") }
        mut subst := map[string]Type{}
        for i, p in gdecl.type_params { subst[p] = resolved_args[i] }
        mangled := mangle_monomorph_name(t.name, subst)
        if resolved_args.all(!it.is_generic()) && mangled !in c.table.structs {
          c.instantiate_struct(t.name, subst) or { c.checker_error("could not instantiate ${t.name}: ${err}") }
        }
        return TypeStruct{qualifs: t.qualifs, name: mangled, generic_args: resolved_args, generic_base: t.name}
      }
      return TypeStruct{qualifs: t.qualifs, name: t.name}
    }
    if t.name in c.generic_params {
      if t.name in c.generic_subst {
        sub := c.generic_subst[t.name] or {c.checker_error("unreachable ${@LINE}")}
        mut both_qualifs := sub.qualifs.clone()
        both_qualifs << t.qualifs
        return sub.with_qualifs(both_qualifs)
      }
      return TypeGeneric{qualifs: t.qualifs, name: t.name}
    }
    c.checker_error("type ${Type(t)} could not be resolved")
  }
  
  if t is TypeArray {
    return TypeArray {
      qualifs: t.qualifs
      inner: c.resolve_type(t.inner)
    }
  }
  if t is TypePointer {
    return TypePointer {
      qualifs: t.qualifs
      inner: c.resolve_type(t.inner)
    }
  }
  if t is TypeFunc {
    return TypeFunc {
      qualifs: t.qualifs 
      arg_types: t.arg_types.map(c.resolve_type(it))
      arg_names: t.arg_names
      variadic_type: t.variadic_type
      ret: c.resolve_type(t.ret)
    }
  }
  return t
}

fn (mut c Checker) resolve_sym_types(s Symbol) Symbol {
  return match s {
    SymbolVar {
      SymbolVar {
        qualifs: s.qualifs
        name: s.name
        type: c.resolve_type(s.type)
      }
    }
    SymbolFunc {
      SymbolFunc {
        qualifs: s.qualifs 
        name: s.name
        ext_name: s.ext_name
        type: c.resolve_type(s.type)
        arg_syms: s.arg_syms.map(c.resolve_sym_types(it))
      }
    }
    SymbolStruct {
      SymbolStruct {
        qualifs: s.qualifs 
        name: s.name
        type: c.resolve_type(s.type)
        member_syms: s.member_syms.map(c.resolve_sym_types(it))
      }
    }
    SymbolEnum {
      SymbolEnum {
        qualifs: s.qualifs 
        name: s.name
        type: c.resolve_type(s.type)
        member_syms: s.member_syms.map(c.resolve_sym_types(it))
      }
    }
  }
}

fn (mut c Checker) check_assignment(from Type, to Type, name string) Type {
  for q in from.qualifs {
    if !q.valid_for_type(from) {c.checker_error("qualifier ${q} not valid for type ${from.unqual()}")}
  }
  for q in to.qualifs {
    if !q.valid_for_type(to) {c.checker_error("qualifier ${q} not valid for type ${to.unqual()}")}
  }
  j := join_types(from, to) or {
    c.checker_error("cannot implicitly cast ${from} to ${to} for ${name}")
  }
  if !is_type_compatible(from, to) {
    c.checker_error("qualifier mismatch assigning ${from} to ${to} for ${name}")
  }
  return j
}

// checking expressions

fn (mut c Checker) check_expr(expr Expr) Type {
  assert(expr.id != 0)
  return match expr {
    ExprLiteralNullptr {TypePointer{inner: TypePrimitive{type: .void}}}
    ExprType {
      res := c.resolve_type(expr.type)
      result := TypeType{name: res.typename_str()}
      c.result.resolved[expr.id] = res 
      result
    }
    ExprLiteralPrimitive {expr.type} // no need to resolve because it's always known here
    ExprLiteralString {
      TypeArray {
        inner: TypePrimitive {
          type: .i8
        }
      }
    }
    ExprLiteralArray {
      mut elem_t := Type(TypePrimitive{type: .void})
      for argv in expr.argv {
        t := c.check_expr(argv)
        if elem_t is TypePrimitive && elem_t.type == .void {
          elem_t = t
        } else {
          j := join_types(elem_t, t) or { c.checker_error("inconsistent types in array literal (${elem_t} and ${t})") }
          elem_t = j
        } 
      }
      c.result.resolved[expr.id] = TypeArray{inner: elem_t}
      return TypeArray{inner: elem_t}
    } 
    ExprGroup {c.check_expr(expr.inner)}

    ExprSizeof {
      match expr.expr {
        ExprType {
          resolved := c.resolve_type(expr.expr.type)
          // if it's a generic struct, instantiate it
          if resolved is TypeStruct && resolved.generic_args.len > 0 {
            base := resolved.generic_base or { c.checker_error("unreachable ${@LINE}") }
            mut subst := map[string]Type{}
            gdecl := c.generic_decls[base] or { c.checker_error("${base} is not a generic type") }
            for i, tp in gdecl.type_params { subst[tp] = resolved.generic_args[i] }
              c.instantiate_struct(base, subst) or { c.checker_error("could not instantiate ${base}: ${err}") }
            }
            c.result.resolved[expr.id] = resolved
            return TypePrimitive{type: .u32}
          }
        ExprVar {
          is_type := expr.expr.name in c.generic_params
            || expr.expr.name in c.table.structs
            || expr.expr.name in c.table.enums
            || expr.expr.name in c.generic_decls
            || is_builtin_type(expr.expr.name)
          if is_type {
            resolved := c.resolve_type(TypeUnresolved{name: expr.expr.name})
            c.result.resolved[expr.id] = resolved
            return TypePrimitive{type: .u32}
          }
          c.check_expr(expr.expr)
        }
        else { c.check_expr(expr.expr) }
      }
      return TypePrimitive{type: .u32}
    }

    ExprTypeof {
      t := c.check_expr(expr.expr)
      c.result.resolved[expr.expr.id] = t
      TypeType {
        name: t.typename_str() 
      }
    }

    ExprTypename {
      t := c.check_expr(expr.expr)
      if t !is TypeType {
        c.checker_error("typename argument must be compile-time type (literal type or typeof expr) ")
      }
      c.result.resolved[expr.expr.id] = t
      TypePointer{inner: TypePrimitive{type: .i8}}
    }

    ExprLiteralStruct {
      struct_name := if expr.generic_args.len > 0 {
        resolved_args := expr.generic_args.map(c.resolve_type(it))
        gdecl := c.generic_decls[expr.type.name] or {
          c.checker_error("${expr.type.name} is not a generic type")
        }
        mut subst := map[string]Type{}
        for i, p in gdecl.type_params { subst[p] = resolved_args[i] }
        c.enforce_constraints(expr.type.name, subst)
        mangled := mangle_monomorph_name(expr.type.name, subst)
        if mangled !in c.table.structs {
          c.instantiate_struct(expr.type.name, subst) or {
            c.checker_error("could not instantiate ${expr.type.name}: ${err}")
          }
        }
        mangled
      } else {
        expr.type.name
      }
      if struct_name !in c.table.structs {
        c.checker_error("cannot create instance of undeclared type ${struct_name}")
      }
      sym := c.table.structs[struct_name]
      if expr.argv.len != sym.member_syms.len {
        c.checker_error("type ${struct_name} requires ${sym.member_syms.len} arguments, got ${expr.argv.len}")
      }
      for i := 0; i < expr.argv.len; i++ {
        req_t := sym.member_syms[i].type
        t := c.check_expr(expr.argv[i])
        j := join_types(t, req_t) or {
          c.checker_error("cannot implicitly cast value of type ${t} to ${req_t} for argument ${i+1}")
        }
        c.result.implicit_casts[expr.argv[i].id] = j
      }
      c.result.resolved[expr.id] = TypeStruct{name: struct_name}
      TypeStruct{name: struct_name}
    }
    
    ExprCall {
      callee_typ := c.check_expr(expr.callee)
      if callee_typ is TypeFunc {
        if callee_typ.variadic_type == none && expr.argv.len != callee_typ.arg_types.len {
          c.checker_error("function requires ${callee_typ.arg_types.len} args, got ${expr.argv.len}")
        } else if callee_typ.variadic_type != none && expr.argv.len < callee_typ.arg_types.len {
          c.checker_error("function requires at least ${callee_typ.arg_types.len} args, got ${expr.argv.len}")
        }

        if expr.callee is ExprVar && expr.callee.name in c.generic_decls {
          eprint("") // workaround: V compiler has some issue with "in" checks, not sure why
          // ^ if you remove this, it will trigger the unreachable checker error below here
          gdecl := c.generic_decls[expr.callee.name] or { c.checker_error("unreachable ${@LINE}") }
          mut arg_types := []Type{}
          for argv in expr.argv {
            arg_types << c.check_expr(argv)
          }
          subst := if expr.generic_args.len > 0 {
            // explicit type args
            if expr.generic_args.len != gdecl.type_params.len {
              c.checker_error("${expr.callee.name} expects ${gdecl.type_params.len} type args, got ${expr.generic_args.len}")
            }
            mut s := map[string]Type{}
            for i, tp in gdecl.type_params {
              s[tp] = c.resolve_type(expr.generic_args[i])
            }
            s
          } else {
            // inferred type args
            infer_type_args(gdecl.type_params, callee_typ.arg_types, arg_types) or {
              c.checker_error("could not infer generic type args for ${expr.callee.name}: ${err}" )
            }
          }

          for i, arg_t in arg_types {
            if i < callee_typ.arg_types.len {
              param_t := substitute_type(callee_typ.arg_types[i], subst)
              c.check_assignment(arg_t, param_t, "argument ${i + 1} of ${expr.callee.name}")
            }
          }

          c.enforce_constraints(expr.callee.name, subst)
          mono := c.instantiate_func(expr.callee.name, subst) or {
            c.checker_error("could not instantiate generic function ${expr.callee.name}: ${err}")
          }
          c.result.resolved_calls[expr.id] = mono.sym.name
          c.result.resolved[expr.id] = mono.sym.type.ret
          mono.sym.type.ret
        } else {
          for i := 0; i < expr.argv.len; i++ {
            t := c.check_expr(expr.argv[i])
            req_t := if i < callee_typ.arg_types.len {
              callee_typ.arg_types[i]
            } else {
              callee_typ.variadic_type or { c.checker_error("unreachable ${@LINE}") }
            }
            arg_name := if i < callee_typ.arg_names.len {
              "argument " + callee_typ.arg_names[i]
            } else {
              "variadic argument ${i}"
            }
            j := c.check_assignment(t, req_t, arg_name)
            
            if !are_types_equal(j, t) {
              c.result.implicit_casts[expr.argv[i].id] = j
            }
          }
          callee_typ.ret
          }
      } else {
        c.checker_error("tried to call an expression of type ${callee_typ}")
      }
    }
    ExprVar {
      if expr.name in c.generic_subst {
        t := c.generic_subst[expr.name] or {c.checker_error("unreachable ${@LINE}")}
        c.result.resolved[expr.id] = t 
        return TypeType{name: Type(t).typename_str()}
      } 
      if expr.name in c.table.structs {
        sym_ := c.table.structs[expr.name] or {c.checker_error("unreachable ${@LINE}")}
        c.result.resolved[expr.id] = sym_.type 
        return TypeType{name: Type(sym_.type).typename_str()}
      }
      if expr.name in c.table.enums {
        sym_ := c.table.enums[expr.name] or {c.checker_error("unreachable ${@LINE}")}
        c.result.resolved[expr.id] = sym_.type 
        return TypeType{name: Type(sym_.type).typename_str()}
      }
      if expr.name in c.generic_decls && c.generic_decls[expr.name].decl is StmtDeclStruct {
        decl := c.generic_decls[expr.name] or {c.checker_error("unreachable ${@LINE}")}
        decl_inner := decl.decl as StmtDeclStruct
        c.result.resolved[expr.id] = decl_inner.sym.type
        return TypeType{name: Type(decl_inner.sym.type).typename_str()}
      }
      if is_builtin_type(expr.name) {
        t := BuiltinType.from_string(expr.name)
        c.result.resolved[expr.id] = TypePrimitive{type: t}
        return TypeType{name: Type(TypePrimitive{type: t}).typename_str()}
      }
      sym := c.current_scope.lookup_sym(expr.name) or {
        c.checker_error("undeclared symbol ${expr.name}")
      }
      sym.type
    }
    ExprUnary {
      // TODO: check op is valid
      c.check_expr(expr.operand)
    }
    ExprBinary {  
      lt := c.check_expr(expr.left)
      rt := c.check_expr(expr.right)
      mut pointer_arith := false
      if lt is TypePointer && rt is TypePrimitive && rt.type.is_int() {
        pointer_arith = true
        if expr.op != "+" {
          c.checker_error("pointer arithmetic is only possible with + operator")
        }
      }

      j := join_types(lt, rt) or {
        if pointer_arith{
          lt
        } else {
          c.checker_error("cannot implicitly cast between types ${lt} and ${rt}")
        }
      }
      if !pointer_arith{
        if lt != j {
          c.result.implicit_casts[expr.left.id] = j
        }
        if rt != j {
          c.result.implicit_casts[expr.right.id] = j
        }
      }
      
      if ["<", ">", ">=", "<=", "==", "!="].contains(expr.op) {
        TypePrimitive{type: .bool}
      } else {
        lt
      }
    }
    ExprAccess {
      lt := c.check_expr(expr.accessee)
      if lt is TypeStruct {
        if lt.name !in c.table.structs {
          c.checker_error("undeclared type ${Type(lt)}")
        }
        sym := c.table.structs[lt.name]
        for m in sym.member_syms {
          if expr.member.name == m.name  {
            return m.type
          }
        }
        c.checker_error("member ${expr.member.name} doesn't exist in ${Type(lt)}")
      } else if lt is TypeType {
        if lt.name in c.table.enums {
          c.result.enum_accesses << expr.id
          esym := c.table.enums[lt.name]
          esym.type
        } else {
          c.checker_error("cannot get member from non-enum type ${Type(lt)}")
        }
      } else {
        c.checker_error("cannot access from var of type ${lt}")
      }
    }
    ExprIndex {
      lt := c.check_expr(expr.indexee)
      c.check_expr(expr.idx)
      if lt is TypeArray {
        lt.inner
      } else if lt is TypePointer {
        lt.inner
      } else {
        c.checker_error("cannot index from non-array type ${lt}")
      }
    }
    ExprRef {
      it := c.resolve_type(c.check_expr(expr.inner))
      TypePointer{inner: it}
    }
    ExprDeref {
      lt := c.check_expr(expr.inner)
      if lt is TypePointer {
        if lt.inner is TypePrimitive && lt.inner.type == .void {
          c.checker_error("cannot dereference void pointer")
        }
        lt.inner
      } else {
        c.checker_error("cannot dereference non-pointer type ${lt}")
      }
    }
    ExprCast {
      what := c.check_expr(expr.castee)
      resolved := c.resolve_type(expr.type)
      if cast_types(what, resolved) == none {
        c.checker_error("cannot cast ${what} to ${resolved}")
      }
      c.result.resolved[expr.id] = resolved
      resolved
    }
    //else {c.checker_error("unimplemented check_expr() for ${expr}")}
  }
}

// checking statements

fn (mut c Checker) check_stmt_block(block StmtBlock) {
  assert(block.id != 0)
	c.push_scope(&block)
	for s in block.stmts {
		c.check_stmt(s)
	}
	c.pop_scope()
}

fn (mut c Checker) check_stmt(stmt Stmt) {
  if stmt.id == 0 {
    c.checker_error("statement ${stmt} at has ID 0")
  }
  c.span = stmt.span
  match stmt {
    StmtExpr {c.check_expr(stmt.expr)} 
    StmtDeclVar {
      if !stmt.sym.type.qualifs.contains(.const) && !stmt.sym.name.is_lower() {
        c.checker_error("variable names must be snake case (${stmt.sym.name} -> ${stmt.sym.name.camel_to_snake()})")
      } else if stmt.sym.type.qualifs.contains(.const) && !stmt.sym.name.is_upper() {
        c.checker_error("constant names must be upper case (${stmt.sym.name} -> ${stmt.sym.name.to_upper()})")
      }
      decl_t := c.resolve_type(stmt.sym.type)
      if !decl_t.is_complete_type() {
        c.checker_error("cannot create variable of incomplete type ${decl_t}")
      }
      if decl_t is TypePrimitive && decl_t.type == .any {
        c.checker_error("type any can only be used for variadic function arguments")
      }
      
      for q in stmt.sym.qualifs {
        if !q.valid_for_decl(stmt) {c.checker_error("qualifier ${q} not valid for variable")}
      }

      if decl_t is TypeFunc {
        c.checker_error("function type variables are not yet implemented")
      }

      vt := c.check_expr(stmt.value)

      j := c.check_assignment(vt, decl_t, stmt.sym.name)

      if !are_types_equal(decl_t, j) {
        c.result.implicit_casts[stmt.value.id] = decl_t 
      }

      c.register_sym(c.resolve_sym_types(stmt.sym))
    }

    StmtDeclFunc {
      if !stmt.sym.name.is_lower() {
        c.checker_error("function names must be snake case (${stmt.sym.name} -> ${stmt.sym.name.camel_to_snake()})")
      }

      only_pure, unpure_name := c.stmt_only_calls_pure_functions(stmt)
      if stmt.sym.type.qualifs.contains(.pure) && !only_pure {
        c.checker_error("function ${stmt.sym.name} is declared as pure but calls unpure function ${unpure_name}")
      }
      
      c.register_sym(c.resolve_sym_types(stmt.sym))

      c.push_scope(&stmt)

      func_t := stmt.sym.type as TypeFunc
      
      for q in func_t.qualifs {
        if !q.valid_for_type(func_t) {c.checker_error("qualifier ${q} not valid for type ${Type(func_t).unqual()}")}
      }
      
      for q in stmt.sym.qualifs {
        if !q.valid_for_decl(stmt) {c.checker_error("qualifier ${q} not valid for function")}
      }

      for q in func_t.ret.qualifs {
        if !q.valid_for_type(func_t.ret) {c.checker_error("qualifier ${q} not valid for type ${func_t.ret.unqual()}")}
      }

      if func_t.variadic_type != none && !stmt.sym.qualifs.contains(.extern) {
        c.checker_error("variadic args are only allowed in extern qualified functions right now")
      }

      c.ret_type_stack << c.resolve_type(func_t.ret)

      for i := 0; i < stmt.sym.type.arg_types.len; i++ {
        n := stmt.sym.type.arg_names[i]
        t := c.resolve_type(stmt.sym.type.arg_types[i])
        if !t.is_complete_type() {
          c.checker_error("cannot have argument ${n} of incomplete type ${t}")
        }
        if t.qualifs.contains(.const) && !n.is_upper() {
          c.checker_error("constant names must be upper case (${n} -> ${n.to_upper()})")
        }
        c.register_sym(SymbolVar{name: n, type: t})
      }

      c.check_stmt_block(stmt.block)

      returns := c.does_stmt_always_return(stmt.block)

      if !stmt.sym.qualifs.contains(.extern) && func_t.ret != Type(TypePrimitive{type: .void}) && !returns {
        c.checker_error("${func_t.ret} returning function ${stmt.sym.name} is expected to return a value in all paths")
      }

      c.pop_scope()

      c.ret_type_stack.pop()

    }

    StmtDeclMember {
      if !stmt.type.qualifs.contains(.const) && !stmt.name.is_lower() {
        c.checker_error("variable names must be snake case (${stmt.name} -> ${stmt.name.camel_to_snake()})")
      } else if stmt.type.qualifs.contains(.const) && !stmt.name.is_upper() {
        c.checker_error("constant names must be upper case (${stmt.name} -> ${stmt.name.to_upper()})")
      }
      decl_t := stmt.type
      if decl_t is TypePrimitive && decl_t.type == .void {
        c.checker_error("cannot declare variable ${stmt.name} of type void")
      }

      if stmt.default_value != none {
        vt := c.check_expr(stmt.default_value)
        j := join_types(decl_t, vt) or {
          c.checker_error("cannot implicitly cast default value of type ${vt} to ${decl_t} for member ${stmt.name}")
        }
        if !are_types_equal(vt, j) {
          c.result.implicit_casts[stmt.default_value.id] = j
        }
      }
    }
    
    StmtDeclEnumMember {
      if !stmt.name.is_upper() {
        c.checker_error("enum member names must be upper case (${stmt.name} -> ${stmt.name.to_upper()})")
      }

      if stmt.override_value != none {
        vt := c.check_expr(stmt.override_value)
        j := join_types(TypePrimitive{type: .i32}, vt) or {
          c.checker_error("cannot implicitly cast default value of type ${vt} to const i32 for member ${stmt.name}")
        }
        if !are_types_equal(vt, j) {
          c.result.implicit_casts[stmt.override_value.id] = j
        }
      }
    }

    StmtDeclStruct {

      if !stmt.sym.name.starts_with_capital() {
        c.checker_error("struct names must be camel case (${stmt.sym.name} -> ${stmt.sym.name.snake_to_camel()})")
      }

      if c.current_scope.parent != none && stmt.sym.name !in c.table.structs {
        c.checker_error("structs can only be declared in the global scope")
      }

      for q in stmt.sym.qualifs {
        if !q.valid_for_decl(stmt) {c.checker_error("qualifier ${q} not valid for struct")}
      }
      
      c.table.structs[stmt.sym.name] = stmt.sym as SymbolStruct

      for m in stmt.members {
        c.check_stmt(m)
      }

      c.table.structs[stmt.sym.name] = c.resolve_sym_types(stmt.sym) as SymbolStruct

    }

    StmtDeclEnum {

      if stmt.members.len == 0 {
        c.checker_error("empty enums aren't allowed")
      }

      for m in stmt.members {
        c.check_stmt(m)
      }

      c.table.enums[stmt.sym.name] = stmt.sym as SymbolEnum
    }
    
    StmtBlock {
      c.check_stmt_block(stmt) 
    }

    StmtBranch {
      guard_t := c.check_expr(stmt.if_guard)
      j := join_types(guard_t, Type(TypePrimitive{type: .bool})) or {
        c.checker_error("if guards must be of type bool, got ${guard_t}")
      }
      if !are_types_equal(guard_t, j) {
        c.result.implicit_casts[stmt.if_guard.id] = j
      }

      c.check_stmt_block(stmt.if_block)

      if stmt.elif_guards != none && stmt.elif_blocks != none {
        for i := 0; i < stmt.elif_guards.len; i++ {
          g := stmt.elif_guards[i]
          b := stmt.elif_blocks[i]

          c.check_stmt_block(b)
          if !are_types_equal(c.check_expr(g), Type(TypePrimitive{type: .bool})) {
            c.checker_error("elif guards must be of type bool, got ${c.check_expr(g)}")
          }
        }
      }
      if stmt.else_block != none {
        c.check_stmt_block(stmt.else_block)
      }
    }

    StmtReturn {
      expr_t := c.check_expr(stmt.expr)
      if c.ret_type_stack.len > 0 {
        current_ret := c.ret_type_stack[c.ret_type_stack.len-1]
        j := join_types(current_ret, expr_t) or { 
          c.checker_error("expected return of type ${current_ret} but got ${expr_t}")
        }
        if !are_types_equal(expr_t, j) {
          c.result.implicit_casts[stmt.expr.id] = j
        }
      } else {
        c.checker_error("cannot return if not inside a function")
      }
    }

    StmtAssign {
      lt := c.check_expr(stmt.assignee)
      rt := c.check_expr(stmt.val)
      jt := join_types(lt, rt) or {c.checker_error("cannot cast between ${rt} and ${lt}")}
      if lt.qualifs.contains(.const) {
        c.checker_error("cannot reassign to 'const' qualified symbol of type ${lt}")
      }
      if !are_types_equal(lt, jt) {
        c.checker_error("cannot implicitly cast ${rt} to ${lt}")
      }
      if !are_types_equal(rt, jt) {
        c.result.implicit_casts[stmt.val.id] = jt
      }
    }

    StmtWhile {
      c.loop_nesting++
      gt := c.check_expr(stmt.guard)
      j := join_types(gt, TypePrimitive{type: .bool}) or {
        c.checker_error("while guard should be of type bool")
      }
      if !are_types_equal(gt, j) {
        c.result.implicit_casts[stmt.guard.id] = j
      }
      c.check_stmt_block(stmt.block) 
      c.loop_nesting--
    }

    StmtContinue, StmtBreak {
      if c.loop_nesting < 1 {
        c.checker_error("continue and break may only be inside while and for loops")
      }
    }

    StmtGeneric {
      if stmt.decl !is StmtDeclFunc && stmt.decl !is StmtDeclStruct {
        c.checker_error("only functions and structs can be declared with generics")
      }
      
      sym := match stmt.decl {
        StmtDeclFunc    {stmt.decl.sym}
        StmtDeclStruct  {stmt.decl.sym}
        else            {c.checker_error("unreachable ${@LINE}")}
      }

      if sym.qualifs.contains(.extern) {
        c.checker_error("cannot use generic for extern symbols")
      }
      
      c.register_generic(sym.name, stmt.type_params, stmt.constraints, stmt.decl)
      c.generic_params = stmt.type_params
      c.register_sym(c.resolve_sym_types(sym))
      c.generic_params = []
    }

    StmtDeclConstraint {
        
      if !stmt.name.starts_with_capital() {
        c.checker_error("struct names must be camel case (${stmt.name} -> ${stmt.name.snake_to_camel()})")
      }

      if stmt.name in c.table.constraints {
        c.checker_error("redefinition of constraint ${stmt.name}")
      }
      res_types := stmt.types.map(c.resolve_type(it))
      c.table.constraints[stmt.name] = res_types
    }

    StmtInclude {}
    StmtDirectiveLink {}
    StmtDirectiveCInclude {} // TODO: check header exists

    else {c.checker_error("unimplemented check_stmt() for ${stmt}")}
  }
}

fn Checker.check_program(parsed ParserResult) CheckedAST {
  mut c := Checker{
    table: SymbolTable{}, 
    result: CheckedAST{
      ast: parsed.ast 
    }
    last_id: parsed.last_id
  }

  for t in all_builtins {
    c.result.type_id_map[t.str()] = c.next_type_id()
  }


  c.current_scope = c.table.root_scope
  for stmt in parsed.ast {
    c.check_stmt(stmt)
  }

  for name, _ in c.table.structs {
    c.result.type_id_map[name] = c.next_type_id()
  }
  
  for name, _ in c.table.enums {
    c.result.type_id_map[name] = c.next_type_id()
  }

  c.result.table = c.table

  return c.result
}
