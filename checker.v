
module main

struct Checker {
  mut: 
  table SymbolTable
  current_scope &Scope = &Scope{}
  ret_type_stack []Type = []Type{}
  span Span
  result CheckedAST
}

struct CheckedAST {
  mut:
  ast []Stmt
  table SymbolTable
  scopes map[i32]&Scope // map[id]&Scope
  casts_resolved map[i32]Type //map[id]Type
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
    ExprType {c.resolve_type(expr.type)}
    ExprLiteralPrimitive {expr.type} // no need to resolve because it's always known here
    ExprLiteralArray { if expr.argv.len > 0 {c.check_expr(expr.argv[0])} else {TypePrimitive{type: .void}} }
    ExprGroup {c.check_expr(expr.inner)}
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
        if join_types(t, req_t) == none {
        c.checker_error("cannot implicitly cast value of type ${t} \
                          to ${req_t} for argument ${i+1}")
        }
      }
      expr.type
    }
    ExprCall {
      callee_typ := c.check_expr(expr.callee)
      if callee_typ is TypeFunc {
        if expr.argv.len != callee_typ.arg_types.len {
          c.checker_error("function requires ${callee_typ.arg_types.len} args, got ${expr.argv.len}")
        }
        sym := c.table.root_scope.lookup_sym(expr.callee.name) or {
          c.checker_error("calling undeclared function ${expr.callee.name}")
        }
        for i := 0; i < expr.argv.len; i++ {
          t := c.check_expr(expr.argv[i])
          req_t := sym.arg_syms[i].type
          if join_types(t, req_t) == none {
          c.checker_error("cannot implicitly cast value of type ${t} \
                          to ${req_t} for argument ${i+1}")
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
      if join_types(lt, rt) == none {
        c.checker_error("cannot implicitly cast between types ${lt} and ${rt}")
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
      c.result.casts_resolved[expr.id] = c.resolve_type(expr.type)
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
  assert(stmt.id != 0)
  c.span = stmt.span
  match stmt {
    StmtExpr {c.check_expr(stmt.expr)} 
    StmtDeclVar {
      if !stmt.sym.name.is_lower() {
        c.checker_error("variable names must be snake case (${stmt.sym.name} -> ${stmt.sym.name.camel_to_snake()})")
      }
      decl_t := c.resolve_type(stmt.sym.type)
      if decl_t is TypePrimitive && decl_t.type == .void {
        c.checker_error("cannot declare variable ${stmt.sym.name} of type void")
      }
      
      vt := c.check_expr(stmt.value)

      if join_types(decl_t, vt) == none {
        c.checker_error("cannot implicitly cast value of type ${vt} \
                          to ${decl_t} for variable ${stmt.sym.name}")
      }
      c.register_sym(c.resolve_sym_types(stmt.sym))
    }

    StmtDeclFunc {
      if !stmt.sym.name.is_lower() {
        c.checker_error("function names must be snake case (${stmt.sym.name} -> ${stmt.sym.name.camel_to_snake()})")
      }
      c.push_scope(&stmt)

      func_t := stmt.sym.type as TypeFunc
      c.ret_type_stack << c.resolve_type(func_t.ret)

      for i := 0; i < stmt.sym.type.arg_types.len; i++ {
        n := stmt.sym.type.arg_names[i]
        t := stmt.sym.type.arg_types[i]
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

      if func_t.ret != Type(TypePrimitive{type: .void}) && !returns {
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
        if join_types(decl_t, vt) == none {
          c.checker_error("cannot implicitly cast default value of type \
                          ${vt} to ${decl_t} for member ${stmt.name}")
        }
      }
    }
    
    StmtDeclEnumMember {
      if !stmt.name.is_upper() {
        c.checker_error("enum member names must be upper case (${stmt.name} -> ${stmt.name.to_upper()})")
      }

      if stmt.override_value != none {
        vt := c.check_expr(stmt.override_value)
        if join_types(TypePrimitive{type: .i32}, vt) == none {
          c.checker_error("cannot implicitly cast default value of type \
                          ${vt} to const i32 for member ${stmt.name}")
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
      if join_types(c.check_expr(stmt.if_guard), Type(TypePrimitive{type: .bool})) == none {
        c.checker_error("if and elif guards must be of type bool")
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
        if join_types(current_ret, expr_t) == none { 
          c.checker_error("expected return of type ${current_ret} but got ${expr_t}")
        }
      } else {
        c.checker_error("cannot return if not inside a function")
      }
    }

    StmtAssign {
      c.check_expr(stmt.assignee)
      _ := c.check_expr(stmt.val)
      // TODO: check types are coercible right to left

    }

    StmtWhile {
      gt := c.check_expr(stmt.guard)
      if join_types(gt, TypePrimitive{type: .bool}) == none {
        c.checker_error("while guard should be of type bool")
      }
      c.check_stmt_block(stmt.block) 
    }

    StmtContinue, StmtBreak {} //TODO: check if inside while or for

    StmtInclude {}

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
