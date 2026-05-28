
module main

struct Checker {
  mut: 
  table SymbolTable
  current_scope &Scope = &Scope{}
  current_ret_type ?Type = ?Type(none)
  span Span
}

@[noreturn]
fn (c Checker) checker_error(s string) {
  eprintln("${c.span} Checker Error -> \"${s}\"")
	exit(1)
}

fn (mut c Checker) push_scope() {
  c.current_scope = &Scope{parent: c.current_scope}
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
  c.current_scope.syms[s.name] = s
}

// checking expressions

fn (mut c Checker) check_expr(expr Expr) Type {
  return match expr {
    ExprType {expr.type}
    ExprLiteralPrimitive {expr.type}
    ExprLiteralArray {expr.of_type}
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
      lt
    }
    else {c.checker_error("unimplemented check_expr() for ${expr}")}
  }
}

// checking statements

fn (mut c Checker) check_stmt_block(block StmtBlock) {
	c.push_scope()
	for s in block.stmts {
		c.check_stmt(s)
	}
	c.pop_scope()
}

fn (mut c Checker) check_stmt(stmt Stmt) {
  c.span = stmt.span
  match stmt {
    StmtExpr {c.check_expr(stmt.expr)} 
    StmtDeclVar {
      if !stmt.sym.name.is_lower() {
        c.checker_error("variable names must be snake case (${stmt.sym.name} -> ${stmt.sym.name.camel_to_snake()})")
      }
      decl_t := stmt.sym.type
      if decl_t is TypePrimitive && decl_t.type == .void {
        c.checker_error("cannot declare variable ${stmt.sym.name} of type void")
      }
      
      vt := c.check_expr(stmt.value)

      if join_types(decl_t, vt) == none {
        c.checker_error("cannot implicitly cast value of type ${vt} \
                          to ${decl_t} for variable ${stmt.sym.name}")
      }

      c.register_sym(stmt.sym)
    }

    StmtDeclFunc {
      if !stmt.sym.name.is_lower() {
        c.checker_error("function names must be snake case (${stmt.sym.name} -> ${stmt.sym.name.camel_to_snake()})")
      }
      c.push_scope()

      func_t := stmt.sym.type as TypeFunc
      c.current_ret_type = func_t.ret

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

      c.register_sym(stmt.sym)
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

      c.table.structs[stmt.sym.name] = stmt.sym as SymbolStruct
    }

    StmtDeclEnum {

    }
    
    StmtBlock {
      c.check_stmt_block(stmt) 
    }

    StmtBranch {
      if c.check_expr(stmt.if_guard) != Type(TypePrimitive{qualifs: [.const], type: .bool}) {
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
      if c.current_ret_type != none {
        if join_types(c.current_ret_type, expr_t) == none { 
          c.checker_error("expected return of type ${c.current_ret_type} but got ${expr_t}")
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

    StmtContinue, StmtBreak {} //TODO: check if inside while or for

    else {c.checker_error("unimplemented check_stmt() for ${stmt}")}
  }
}

fn Checker.check_program(ast []Stmt) {
  mut c := Checker{table: SymbolTable{}}
  c.current_scope = c.table.root_scope
  for stmt in ast {
    c.check_stmt(stmt)
  }
  //println(c.table)
}
