
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
}

struct GenericDecl {
  type_params []string
  decl Stmt
}

struct MonomorphCache {
  mut:
  funcs map[string]StmtDeclFunc
  structs map[string]StmtDeclStruct
}

@[noreturn]
fn (c Checker) checker_error(s string) {
  eprintln("${c.span} Checker Error -> \"${s}\"")
	exit(1)
}


fn (mut c Checker) next_id() i32 {
  c.last_id++
  return c.last_id
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
    ExprGroup          { ExprGroup{...e,           id: c.next_id(), inner: c.clone_expr(e.inner)} }
    ExprCall           { ExprCall{...e,            id: c.next_id(), callee: c.clone_expr(e.callee), argv: e.argv.map(c.clone_expr(it))} }
    ExprIndex          { ExprIndex{...e,           id: c.next_id(), indexee: c.clone_expr(e.indexee), idx: c.clone_expr(e.idx)} }
    ExprAccess         { ExprAccess{...e,          id: c.next_id(), accessee: c.clone_expr(e.accessee)} }
    ExprRef            { ExprRef{...e,             id: c.next_id(), inner: c.clone_expr(e.inner)} }
    ExprDeref          { ExprDeref{...e,           id: c.next_id(), inner: c.clone_expr(e.inner)} }
    ExprUnary          { ExprUnary{...e,           id: c.next_id(), operand: c.clone_expr(e.operand)} }
    ExprBinary         { ExprBinary{...e,          id: c.next_id(), left: c.clone_expr(e.left), right: c.clone_expr(e.right)} }
    ExprCast           { ExprCast{...e,            id: c.next_id(), castee: c.clone_expr(e.castee)} }
    ExprType           { ExprType{...e,            id: c.next_id()} }
    ExprSizeof         { ExprSizeof{...e,          id: c.next_id()} }
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

fn (mut c Checker) register_sym(s Symbol) {
  if s.name in c.current_scope.syms {
    c.checker_error("redefinition of symbol ${s.name}")
  }
  c.current_scope.syms[s.name] = c.resolve_sym_types(s)
}

fn (mut c Checker) register_generic(name string, type_params []string, decl Stmt) {
  if name in c.generic_decls {
    c.checker_error("redefinition of generic ${name}")
  }
  c.generic_decls[name] = GenericDecl {
    type_params: type_params
    decl: decl
  }
}

fn (mut c Checker) begin_instantiation(gdecl GenericDecl, subst map[string]Type) (map[string]Type, []string) {
  old_subst := c.generic_subst.clone()
  old_params := c.generic_params.clone()
  c.generic_subst = subst.clone()
  c.generic_params = gdecl.type_params
  return old_subst, old_params
}

fn (mut c Checker) end_instantiation(old_subst map[string]Type, old_params []string) {
  c.generic_subst = old_subst.clone()
  c.generic_params = old_params
}

fn (mut c Checker) instantiate_func(name string, subst map[string]Type) !StmtDeclFunc {
  mangled := mangle_monomorph_name(name, subst)
  if mangled in c.mono_cache.funcs {
    return c.mono_cache.funcs[mangled]
  }

  gdecl := c.generic_decls[name] or {return error("no generic decl for ${name}")}
  mut cloned := c.clone_stmt(gdecl.decl) as StmtDeclFunc

  cloned = StmtDeclFunc{...cloned, sym: SymbolFunc{...(cloned.sym as SymbolFunc), name: mangled}}
  old_subst, old_params := c.begin_instantiation(gdecl, subst)
  cloned = StmtDeclFunc{...cloned, sym: c.resolve_sym_types(cloned.sym)}

  c.check_stmt(cloned)
  c.end_instantiation(old_subst, old_params)

  c.result.monomorph_decls << cloned
  c.mono_cache.funcs[mangled] = cloned
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
  old_subst, old_params := c.begin_instantiation(gdecl, subst)

  c.table.structs[mangled] = cloned.sym as SymbolStruct
  c.mono_cache.structs[mangled] = cloned

  cloned = StmtDeclStruct{...cloned, sym: c.resolve_sym_types(cloned.sym)}

  c.table.structs[mangled] = cloned.sym as SymbolStruct
  c.mono_cache.structs[mangled] = cloned

  c.result.monomorph_decls << cloned

  c.check_stmt(cloned)
  c.end_instantiation(old_subst, old_params)

  c.mono_cache.structs[mangled] = cloned
  return cloned 
}

fn (mut c Checker) resolve_type(t Type) Type {
  if t is TypeGeneric {
    if t.name in c.generic_subst {
      return c.generic_subst[t.name] or {c.checker_error("unreachable ${@LINE}")}
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
        return c.generic_subst[t.name] or { c.checker_error("unreachable ${@LINE}") }
      }
      return TypeGeneric{name: t.name}
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

// checking expressions

fn (mut c Checker) check_expr(expr Expr) Type {
  assert(expr.id != 0)
  return match expr {
    ExprLiteralNullptr {TypePointer{inner: TypePrimitive{type: .void}}}
    ExprType {TypePrimitive{type: .type}}
    ExprLiteralPrimitive {expr.type} // no need to resolve because it's always known here
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
        ExprVar {
          is_type := expr.expr.name in c.generic_params
            || expr.expr.name in c.table.structs
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

    ExprLiteralStruct {
      struct_name := if expr.generic_args.len > 0 {
        resolved_args := expr.generic_args.map(c.resolve_type(it))
        gdecl := c.generic_decls[expr.type.name] or {
          c.checker_error("${expr.type.name} is not a generic type")
        }
        mut subst := map[string]Type{}
        for i, p in gdecl.type_params { subst[p] = resolved_args[i] }
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
          subst := infer_type_args(gdecl.type_params, callee_typ.arg_types, arg_types) or {
            c.checker_error("could not infer generic type args for ${expr.callee.name}: ${err}")
          }
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
            j := join_types(t, req_t) or {
              c.checker_error("cannot implicitly cast between type ${t} and ${req_t} for argument ${i+1}")
            }
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
      if expr.name in c.table.enums {
        return c.table.enums[expr.name].type
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

      } else if lt is TypeEnum {
        if lt.name !in c.table.enums {
          c.checker_error("undeclared type ${Type(lt)}")
        }
        lt
      } else {
        c.checker_error("cannot access from type ${lt}")
        TypePrimitive{type: .void}
      }
      //rt := c.check_expr(expr.member)
    }
    ExprIndex {
      lt := c.check_expr(expr.indexee)
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
        lt.inner
      } else {
        c.checker_error("cannot dereference non-pointer type ${lt}")
      }
    }
    ExprCast {
      what := c.check_expr(expr.castee)
      if cast_types(what, c.resolve_type(expr.type)) == none {
        c.checker_error("cannot cast ${what} to ${expr.type}")
      }
      c.result.resolved[expr.id] = c.resolve_type(expr.type)
      c.resolve_type(expr.type)
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
      if decl_t is TypePrimitive {
        if decl_t.type == .void {
          c.checker_error("cannot declare variable ${stmt.sym.name} of type void")
        } else if decl_t.type == .any {
          c.checker_error("type any can only be used for variadic function arguments")
        }
      }

      if decl_t is TypeFunc {
        c.checker_error("function type variables are not yet implemented")
      }

      vt := c.check_expr(stmt.value)

      j := join_types(decl_t, vt) or {
        c.checker_error("cannot implicitly cast value of type ${vt} to ${decl_t} for variable ${stmt.sym.name}")
      }

      if decl_t is TypeStruct && vt is TypeStruct && !are_types_equal(decl_t, vt) {
        c.checker_error("cannot implicitly cast value of type ${Type(vt)} to ${Type(decl_t)} for variable ${stmt.sym.name} (use explicit type args e.g. 3@i32)")
      }
      if !are_types_equal(vt, j) && !(decl_t is TypeStruct) && vt !is TypeArray {
        c.result.implicit_casts[stmt.value.id] = j
      }

      c.register_sym(c.resolve_sym_types(stmt.sym))
    }

    StmtDeclFunc {
      if !stmt.sym.name.is_lower() {
        c.checker_error("function names must be snake case (${stmt.sym.name} -> ${stmt.sym.name.camel_to_snake()})")
      }
      
      c.register_sym(c.resolve_sym_types(stmt.sym))

      c.push_scope(&stmt)

      func_t := stmt.sym.type as TypeFunc

      if func_t.variadic_type != none && !stmt.sym.qualifs.contains(.extern) {
        c.checker_error("variadic args are only allowed in extern qualified functions right now")
      }

      c.ret_type_stack << c.resolve_type(func_t.ret)

      for i := 0; i < stmt.sym.type.arg_types.len; i++ {
        n := stmt.sym.type.arg_names[i]
        t := c.resolve_type(stmt.sym.type.arg_types[i])
        c.register_sym(SymbolVar{name: n, type: t})
      }

      c.check_stmt_block(stmt.block)

      mut returns := false 
      for s in stmt.block.stmts {
        returns = returns || c.does_stmt_always_return(s)
      }

      if !stmt.sym.qualifs.contains(.extern) && func_t.ret != Type(TypePrimitive{type: .void}) && !returns {
        c.checker_error("a non-void function must return a value in all paths")
      }

      c.pop_scope()

      c.ret_type_stack.pop()

    }

    StmtDeclMember {
      if !stmt.name.is_lower() {
        c.checker_error("member names must be snake case (${stmt.name} -> ${stmt.name.camel_to_snake()})")
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
        dump(c.current_scope)
        c.checker_error("structs can only be declared in the global scope")
      }
      
      c.table.structs[stmt.sym.name] = stmt.sym as SymbolStruct

      for m in stmt.members {
        c.check_stmt(m)
      }

      c.table.structs[stmt.sym.name] = c.resolve_sym_types(stmt.sym) as SymbolStruct

    }

    StmtDeclEnum {
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
          if !are_types_equal(c.check_expr(g), Type(TypePrimitive{qualifs: [.const], type: .bool})) {
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
      if jt != lt {
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
      c.register_generic(sym.name, stmt.type_params, stmt.decl)
      c.generic_params = stmt.type_params
      c.register_sym(c.resolve_sym_types(sym))
      c.generic_params = []
    }

    StmtInclude {}
    StmtDirectiveLink {}

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


  c.current_scope = c.table.root_scope
  for stmt in parsed.ast {
    c.check_stmt(stmt)
  }

  c.result.table = c.table

  return c.result
}
