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

fn (mut g Generator) writeln_tabbed(s string) {
  g.gend_main.writeln("\t".repeat(g.tabs)+s)
}

fn (mut g Generator) write_tabbed(s string) {
  g.gend_main.write_string("\t".repeat(g.tabs)+s)
}

fn (mut g Generator) mangle_ident(s string) string {
  return "iris_${s}_"
}

fn (mut g Generator) gen_type(t Type) string {
  return match t {
    TypePrimitive {
      match t.type {
        .i8 {"int8_t"} 
        .u8 {"uint8_t"} 
        .i16 {"int16_t"} 
        .u16 {"uint16_t"} 
        .i32 {"int32_t"} 
        .u32 {"uint32_t"} 
        .f32 {"float"}
        .bool {"bool"}
        .string {"char*"}
        .void {"void"}
        else {g.gen_error("unimplemented type ${t.type}")}
      }
    }
    TypePointer {"${g.gen_type(t.inner)}*"}
    TypeArray   {"${g.gen_type(t.inner)}*"}
    TypeStruct  {"struct ${g.mangle_ident(t.name)}"}
    TypeEnum    {"enum ${g.mangle_ident(t.name)}"}
    else        {g.gen_error("something went wrong here, type: ${t}")}
  }
}

fn (mut g Generator) gen_expr(e Expr) string {
  unsafe {
    return match e {
      ExprGroup {
        "(${g.gen_expr(e.inner)})"
      }
      ExprRef {
        "(&${g.gen_expr(e.inner)})"
      }
      ExprDeref {
        "(*${g.gen_expr(e.inner)})"
      }
      ExprLiteralPrimitive {
        s := match e.type.type {
          .i8, .u8, .i16, .u16, .i32, .u32 {e.value.i64.str()}
          .f32, .f64 {e.value.f64.str()}
          .bool {e.value.bool.str()}
          .string {"\"${e.value.string}\""}
          .type {g.gen_error("unimplemented type type")}
          .void {""}
          .any {g.gen_error("unimplemented type any")}
        }
        s
      }
      ExprLiteralStruct {
        mut s := "(${g.gen_type(e.type)}){"
        for argv in e.argv {
          s += g.gen_expr(argv)
          if argv != e.argv[e.argv.len-1] {
            s += ", "
          }
        }
        s + "}"
      }
      ExprLiteralArray {
        mut s := "{"
        for argv in e.argv {
          s += g.gen_expr(argv)
          if argv != e.argv[e.argv.len-1] {
            s += ", "
          }
        }
        s + "}"
      }
      ExprCall {
        mut s := "${g.gen_expr(e.callee)}("
        for argv in e.argv {
          s += g.gen_expr(argv)
          if argv != e.argv[e.argv.len-1] {
            s += ", "
          }
        }
        s + ")"
      }
      ExprVar {g.mangle_ident(e.name)}
      ExprType {g.gen_type(e.type)}
      ExprCast {"((${g.gen_type(g.checked_ast.casts_resolved[e.id])})${g.gen_expr(e.castee)})"}
      ExprBinary {"(${g.gen_expr(e.left)}${e.op}${g.gen_expr(e.right)})"}
      ExprUnary  {"(${e.op}${g.gen_expr(e.operand)})"}
      ExprIndex  {"${g.gen_expr(e.indexee)}[${g.gen_expr(e.idx)}]"}
      ExprAccess {"${g.gen_expr(e.accessee)}.${e.member.name}"}
    }
  }
}

fn (mut g Generator) gen_stmt(s Stmt) {
  match s {
    StmtExpr {{g.writeln_tabbed("${g.gen_expr(s.expr)};")}}
    StmtBlock {
      g.tabs++
      if s.id in g.checked_ast.scopes {
        g.current_scope = g.checked_ast.scopes[s.id] or {g.gen_error("scope not found")}
      }
      for s_ in s.stmts {
        g.gen_stmt(s_)
      }
      g.tabs--
    }
    StmtDeclVar {
      sym := g.current_scope.lookup_sym(s.sym.name) or {g.gen_error("forgot to register a symbol")}
      g.writeln_tabbed("${g.gen_type(sym.type)} ${g.mangle_ident(s.sym.name)} = ${g.gen_expr(s.value)};")
    }
    StmtDeclFunc {
      sym := g.current_scope.lookup_sym(s.sym.name) or {g.gen_error("didn't find func symbol (bad!)")}
      args := (sym as SymbolFunc).arg_syms
      if sym.type.variadic_type != none {
        g.gend_fn_decl.write_string("#define ${g.mangle_ident(sym.name)}(")
        for arg in args {
          g.gend_fn_decl.write_string("${g.mangle_ident(arg.name)}")
          if arg != args[args.len-1] {
            g.gend_fn_decl.write_string(", ")
          }
        }
        g.gend_fn_decl.write_string(", ...) ${sym.name}(")
        for arg in args {
          g.gend_fn_decl.write_string("${g.mangle_ident(arg.name)}")
          if arg != args[args.len-1] {
            g.gend_fn_decl.write_string(", ")
          }
        }
        g.gend_fn_decl.writeln(", ##__VA_ARGS__)")
        return
      }
      mut declar := "${g.gen_type(sym.type.ret)} ${g.mangle_ident(sym.name)}("
      for arg in args {
        declar += "${g.gen_type(arg.type)} ${g.mangle_ident(arg.name)}" 
        if arg != args[args.len-1] {
          declar += ", "
        }
      }
      declar += ")"
      g.gend_fn_decl.writeln(declar+";")
      g.gend_main.writeln(declar + "\n{")
      if sym.qualifs.contains(.extern) {
        name := sym.ext_name or {sym.name}
        g.tabs++
        if sym.type.ret != Type(TypePrimitive{type: .void}) {
          g.write_tabbed("return ")
        }
        g.write_tabbed("${name}(") 
        mut wrap_argv := ""
        for arg in args {
          wrap_argv += "${g.mangle_ident(arg.name)}"
          if arg != args[args.len-1] {
            wrap_argv += ", "
          }
        }
        g.writeln_tabbed("${wrap_argv});")
        g.tabs--
      } else {
        g.gen_stmt(s.block)  
      }
      g.gend_main.writeln("}\n\n")
    }
    StmtReturn    {g.writeln_tabbed("return ${g.gen_expr(s.expr)};")}
    StmtContinue  {g.writeln_tabbed("continue;")}
    StmtBreak     {g.writeln_tabbed("break;")}
    StmtDeclStruct {
      if s.sym.qualifs.contains(.extern) {
        g.gend_struct_decl.writeln("#define ${g.mangle_ident(s.sym.name)} ${s.sym.name}")
        return
      }
      g.gend_struct_decl.writeln("struct ${g.mangle_ident(s.sym.name)} {")
      for m in s.members {
        g.gen_stmt(m)
      }
      g.gend_struct_decl.writeln("};\n")
    }
    StmtDeclMember {
      g.gend_struct_decl.writeln("\t${g.gen_type(s.type)} ${s.name};")
    }
    StmtDeclEnum {
      g.gend_struct_decl.writeln("enum ${g.mangle_ident(s.sym.name)} {")
      for m in s.members {
        g.gen_stmt(m)
      }
      g.gend_struct_decl.writeln("}")
    }
    StmtDeclEnumMember {
      g.gend_struct_decl.writeln("\t${g.mangle_ident(s.name)},")
    }
    StmtAssign {
      g.writeln_tabbed("${g.gen_expr(s.assignee)} = ${g.gen_expr(s.val)};")
    }
    StmtInclude {}
    StmtWhile {
      g.writeln_tabbed("while (${g.gen_expr(s.guard)}) {")
      g.gen_stmt(s.block)
      g.writeln_tabbed("}")
    }
    StmtBranch {
      g.gen_error("unimplemented branch")
    }
    StmtFor {g.gen_error("unimplemented for")}
    //else {g.gen_error("unimplemented stmt ${s}")}
  }
}

fn Generator.gen_program(checked_ast CheckedAST) {
  mut g := Generator{checked_ast: checked_ast, current_scope: checked_ast.table.root_scope}
  for stmt in g.checked_ast.ast {
    g.gen_stmt(stmt)
  }

  g.gend_includes.writeln("#include <stdio.h>")
  g.gend_includes.writeln("#include <stdint.h>")
  g.gend_includes.writeln("#include <stdarg.h>")
  g.gend_includes.writeln("#include <raylib.h>")

  g.gend_main.writeln("int main(void) {\n\treturn ${g.mangle_ident("main")}();\n}")

  println("${g.gend_includes}")
  println("// -- types --\n${g.gend_struct_decl}")
  println("// -- fn decl --\n${g.gend_fn_decl}")
  println("// -- program --\n${g.gend_main.str()}")
}
