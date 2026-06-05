module main

import strings

struct Generator {
  checked_ast CheckedAST
  mut:
  current_scope &Scope 
  tabs int 
  gend_includes strings.Builder
  gend_fn_decl strings.Builder
  gend_struct_decl strings.Builder
  gend_main strings.Builder

}

@[noreturn]
fn (g Generator) gen_error(s string) {
  eprintln("Generation Error -> \"${s}\"")
	exit(1)
}

fn (mut g Generator) write_tabbed(s string) {
  g.gend_main.writeln("\t".repeat(g.tabs)+s)
}

fn (mut g Generator) gen_type(t Type) string {
  return match t {
    TypePrimitive {
      match t.type {
        .i32 {"int"} 
        .f32 {"float"}
        .bool {"bool"}
        .string {"char*"}
        .void {"void"}
        else {g.gen_error("unimplemented type ${t.type}")}
      }
    }
    TypePointer {"${g.gen_type(t.inner)}*"}
    TypeArray   {"${g.gen_type(t.inner)}*"}
    TypeStruct  {"struct ${t.name}"}
    TypeEnum    {"enum ${t.name}"}
    else        {g.gen_error("something went wrong here")}
  }
}

fn (mut g Generator) gen_expr(e Expr) string {
  unsafe {
    return match e {
      ExprLiteralPrimitive {
        s := match e.type.type {
          .i32 {e.value.i64.str()}
          .f32 {e.value.f64.str()}
          .bool {e.value.bool.str()}
          .string {"\"${e.value.string}\""}
          .type {g.gen_error("unimplemented type type")}
          .void {""}
        }
        s
      }
      ExprVar {e.name}
      ExprBinary {"(${g.gen_expr(e.left)}${e.op}${g.gen_expr(e.right)})"}
      ExprUnary  {"(${e.op}${g.gen_expr(e.operand)})"}
      else {g.gen_error("unimplemented expr ${e}")}
    }
  }
}

fn (mut g Generator) gen_stmt(s Stmt) {
  match s {
    StmtExpr {g.write_tabbed(g.gen_expr(s.expr))}
    StmtBlock {
      g.tabs++
      if &s in g.checked_ast.scopes {
        g.current_scope = g.checked_ast.scopes[&s] or {g.gen_error("scope not found")}
      }
      for s_ in s.stmts {
        g.gen_stmt(s_)
      }
      g.tabs--
    }
    StmtDeclVar {
      dump(g.current_scope)
      sym := g.current_scope.lookup_sym(s.sym.name) or {g.gen_error("forgot to register a symbol")}
      g.write_tabbed("${g.gen_type(sym.type)} ${s.sym.name} = ${g.gen_expr(s.value)};")
    }
    StmtDeclFunc {
      declar := "${g.gen_type(s.sym.type.ret)} ${s.sym.name}()"
      // TODO: gen paramenters
      g.gend_fn_decl.writeln(declar+";")
      g.gend_main.writeln(declar + "\n{")
      g.gen_stmt(s.block)  
      g.gend_main.writeln("}")
    }
    StmtReturn    {g.write_tabbed("return ${g.gen_expr(s.expr)};")}
    StmtContinue  {g.write_tabbed("continue;")}
    StmtBreak     {g.write_tabbed("break;")}
    StmtDeclStruct {
      g.gend_struct_decl.writeln("struct ${s.sym.name} {")
      for m in s.members {
        g.gen_stmt(m)
      }
      g.gend_struct_decl.writeln("}")
    }
    StmtDeclMember {
      g.gend_struct_decl.writeln("\t${g.gen_type(s.type)} ${s.name};")
    }
    StmtDeclEnum {
      g.gend_struct_decl.writeln("enum ${s.sym.name} {")
      for m in s.members {
        g.gen_stmt(m)
      }
      g.gend_struct_decl.writeln("}")
    }
    StmtDeclEnumMember {
      g.gend_struct_decl.writeln("\t${s.name},")
    }
    else {g.gen_error("unimplemented stmt ${s}")}
  }
}

fn Generator.gen_program(checked_ast CheckedAST) {
  mut g := Generator{checked_ast: checked_ast, current_scope: &Scope{}}
  for stmt in g.checked_ast.ast {
    g.gen_stmt(stmt)
  }
  println("// types \n ${g.gend_struct_decl}")
  println("// program \n ${g.gend_main.str()}")
}
