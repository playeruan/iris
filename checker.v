
module main

struct Checker {
  mut: 
  table SymbolTable
  current_scope &Scope = &Scope{}
  ret_type_stack []Type = []Type{}
  span Span
  result CheckedAST
  loop_nesting i32
}

struct CheckedAST {
  mut:
  ast []Stmt
  table SymbolTable
  scopes map[i32]&Scope // map[id]&Scope
  resolved map[i32]Type //map[id]Type
  implicit_casts map[i32]Type //map[id]Type
}

@[noreturn]
fn (c Checker) checker_error(s string) {
  eprintln("${c.span} Checker Error -> \"${s}\"")
	exit(1)
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

fn (mut c Checker) resolve_type(t Type) Type {
  if t is TypeUnresolved {
    if t.name in c.table.enums {
      sym := c.table.enums[t.name]
      return TypeEnum{qualifs: t.qualifs, name: t.name, as: sym.type.as} 
    }
    if t.name in c.table.structs {
      return TypeStruct{qualifs: t.qualifs, name: t.name} 
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
      captured_names: t.captured_names 
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
    ExprLiteralArray { if expr.argv.len > 0 {TypeArray{inner: c.check_expr(expr.argv[0])}} else {TypeArray{inner: TypePrimitive{type: .void}}} }
    ExprGroup {c.check_expr(expr.inner)}
    ExprSizeof {
      t := c.resolve_type(expr.type)
      c.result.resolved[expr.id] = t
      match t {
        TypePrimitive, TypeStruct, TypeEnum {}
        else {c.checker_error("cannot get sizeof ${t}")}
      }
      TypePrimitive{type: .u32}
    }
    ExprLiteralStruct {
      if expr.type.name !in c.table.structs {
        c.checker_error("cannot create instance of undeclared type ${Type(expr.type)}")
      }
      sym := c.table.structs[expr.type.name]
      if expr.argv.len != sym.member_syms.len {
        c.checker_error("type ${Type(expr.type)} requires ${sym.member_syms.len} arguments, got ${expr.argv.len}")
      } 
      for i := 0; i < expr.argv.len; i++ {
        req_t := sym.member_syms[i].type
        t := c.check_expr(expr.argv[i])
        j := join_types(t, req_t) or {
          c.checker_error("cannot implicitly cast value of type ${t} \
                          to ${req_t} for argument ${i+1}")
        }
        c.result.implicit_casts[expr.argv[i].id] = j
      }
      expr.type
    }
    ExprCall {
      callee_typ := c.check_expr(expr.callee)
      if callee_typ is TypeFunc {
        if callee_typ.variadic_type == none && expr.argv.len != callee_typ.arg_types.len {
          c.checker_error("function requires ${callee_typ.arg_types.len} args, got ${expr.argv.len}")
        } else if callee_typ.variadic_type != none && expr.argv.len < callee_typ.arg_types.len {
          c.checker_error("function requires at least ${callee_typ.arg_types.len} args, got ${expr.argv.len}")
        }
        sym := c.table.root_scope.lookup_sym(expr.callee.name) or {
          c.checker_error("calling undeclared function ${expr.callee.name}")
        }
        for i := 0; i < expr.argv.len; i++ {
          t := c.check_expr(expr.argv[i])
          req_t := if i < sym.arg_syms.len {
            sym.arg_syms[i].type
          } else {
            sym.type.variadic_type or {c.checker_error("unreachable (I hope)")}
          }
          j := join_types(t, req_t) or {
            c.checker_error("cannot implicitly cast value of type ${t} \
                          to ${req_t} for argument ${i+1}")
          }
          if !are_types_equal(j, t) {
            c.result.implicit_casts[expr.argv[i].id] = j
          }
        }
        callee_typ.ret
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
      
      if ["<", ">", ">=", "<=", "=="].contains(expr.op) {
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
        c.checker_error("cannot implicitly cast value of type ${vt} \
                          to ${decl_t} for variable ${stmt.sym.name}")
      }
      if !are_types_equal(vt, j) && vt !is TypeArray {
        c.result.implicit_casts[stmt.value.id] = j
      }
      c.register_sym(c.resolve_sym_types(stmt.sym))
    }

    StmtDeclFunc {
      if !stmt.sym.name.is_lower() {
        c.checker_error("function names must be snake case (${stmt.sym.name} -> ${stmt.sym.name.camel_to_snake()})")
      }
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

      for n in stmt.sym.type.captured_names {
        if c.current_scope.lookup_sym(n) == none {
          c.checker_error("cannot capture undeclared symbol ${n}")
        }
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

      c.register_sym(c.resolve_sym_types(stmt.sym))
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
          c.checker_error("cannot implicitly cast default value of type \
                          ${vt} to ${decl_t} for member ${stmt.name}")
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
          c.checker_error("cannot implicitly cast default value of type \
                          ${vt} to const i32 for member ${stmt.name}")
        }
        if !are_types_equal(vt, j) {
          c.result.implicit_casts[stmt.override_value.id] = j
        }
      }
    }

    StmtDeclStruct {
      if c.current_scope.parent != none {
        c.checker_error("structs can only be declared in the global scope")
      }

      if !stmt.sym.name.starts_with_capital() {
        c.checker_error("struct names must be camel case (${stmt.sym.name} -> ${stmt.sym.name.snake_to_camel()})")
      }

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
        c.checker_error("if and elif guards must be of type bool")
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
          if c.check_expr(g) != Type(TypePrimitive{qualifs: [.const], type: .bool}) {
            c.checker_error("if and elif guards must be of type bool")
          }
        }
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

    StmtInclude {}
    StmtDirectiveLink {}

    else {c.checker_error("unimplemented check_stmt() for ${stmt}")}
  }
}

fn Checker.check_program(ast []Stmt) CheckedAST {
  mut c := Checker{
    table: SymbolTable{}, 
    result: CheckedAST{
      ast: ast
    }
  }

  c.result.table = c.table

  c.current_scope = c.table.root_scope
  for stmt in ast {
    c.check_stmt(stmt)
  }

  return c.result
}
