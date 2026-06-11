
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
  gend_globals strings.Builder

  span Span

  libs_to_link []string
  hs_to_include []string
}

struct GeneratorResult {
  text string 
  to_link []string
}

@[noreturn]
fn (g Generator) gen_error(s string) {
  eprintln("${g.span} Generation Error -> \"${s}\"")
	exit(1)
}

fn (mut g Generator) writeln_tabbed(s string) {
  g.gend_main.writeln("\t".repeat(g.tabs)+"#line ${g.span.row} \"${g.span.file}\"")
  g.gend_main.writeln("\t".repeat(g.tabs)+s)
}

fn (mut g Generator) write_tabbed(s string) {
  g.gend_main.writeln("\t".repeat(g.tabs)+"#line ${g.span.row} \"${g.span.file}\"")
  g.gend_main.write_string("\t".repeat(g.tabs)+s)
}

fn (mut g Generator) mangle_ident(s string) string {
  return "iris_${s}_"
}

fn (mut g Generator) gen_type_left(t Type, is_ret bool) string {
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
        .f64 {"double"}
        .bool {"bool"}
        .void {"void"}
        else {g.gen_error("unimplemented type ${t.type}")}
      }
    }
    TypePointer {"${g.gen_type_left(t.inner, is_ret)}*"}
    TypeArray   {
      if is_ret {"${g.gen_type_left(t.inner, is_ret)}*"}
      else {"${g.gen_type_left(t.inner, is_ret)}"}
    }
    TypeStruct  {"struct ${g.mangle_ident(t.name)}"}
    TypeEnum    {"enum ${g.mangle_ident(t.name)}"}
    else        {g.gen_error("something went wrong here, type: ${t}")}
  }
}

fn (mut g Generator) gen_type_right(t Type, is_ret bool) string {
  return match t {
    TypePrimitive, TypePointer, TypeStruct, TypeEnum {""}
    TypeArray   {
      if is_ret {""} else {"[]"}
    }
    else        {g.gen_error("something went wrong here, type: ${t}")}
  }
}

fn (mut g Generator) gen_expr(e Expr) string {
  unsafe {
    mut pre := ""
    mut post := ""
    if e.id in g.checked_ast.implicit_casts {
      t := g.gen_type_left(g.checked_ast.implicit_casts[e.id], false)
      pre = "((${t})"
      post = ")"
    }
    return pre + match e {
      ExprLiteralNullptr {
        "NULL"  
      }
      ExprGroup {
        "(${g.gen_expr(e.inner)})"
      }
      ExprRef {
        "(&${g.gen_expr(e.inner)})"
      }
      ExprDeref {
        "(*${g.gen_expr(e.inner)})"
      }
      ExprSizeof {
        if e.id in g.checked_ast.resolved {
          t := g.checked_ast.resolved[e.id] or { TypePrimitive{type: .void} }
          return "(sizeof(${g.gen_type_left(t, false)}))"
        }
        return "(sizeof(${g.gen_expr(e.expr)}))"
      }
      ExprLiteralPrimitive {
        s := match e.type.type {
          .i8, .u8, .i16, .u16, .i32, .u32 {e.value.i64.str()}
          .f32, .f64 {e.value.f64.str()}
          .bool {e.value.bool.str()}
          .type {g.gen_error("unimplemented type type")}
          .void {""}
          .any {g.gen_error("unimplemented type any")}
        }
        s
      }
      ExprLiteralString {
        "\"${e.value}\""
      }
      ExprLiteralStruct {
        t := if e.id in g.checked_ast.resolved {
          g.checked_ast.resolved[e.id]
        } else {
          Type(e.type)
        }
        mut s := "(${g.gen_type_left(t, false)}){"
        for argv in e.argv {
          s += g.gen_expr(argv)
          if argv != e.argv[e.argv.len-1] {
            s += ", "
          }
        }
        s + "}"
      }

      ExprLiteralArray {
        t := g.checked_ast.resolved[e.id] or { TypePrimitive{type: .void} }
        elem_t := if t is TypeArray { t.inner } else { Type(TypePrimitive{type: .void}) }
        mut s := "(${g.gen_type_left(elem_t, false)}[]){"
        for i, argv in e.argv {
          s += g.gen_expr(argv)
          if i < e.argv.len - 1 { s += ", " }
        }
        return s + "}"
      }
      
      ExprCall {
        callee_name := if e.id in g.checked_ast.resolved_calls {
          g.mangle_ident(g.checked_ast.resolved_calls[e.id])
        } else {
          g.gen_expr(e.callee)
        }
        mut s := "${callee_name}("
        for argv in e.argv {
          s += g.gen_expr(argv)
          if argv != e.argv[e.argv.len-1] {
            s += ", "
          }
        }
        s + ")"
      }
      ExprVar {g.mangle_ident(e.name)}
      ExprType {g.gen_type_left(e.type, false)+g.gen_type_right(e.type, false)}
      ExprCast {"((${g.gen_type_left(g.checked_ast.resolved[e.id], false)})${g.gen_expr(e.castee)})"}
      ExprBinary {"(${g.gen_expr(e.left)}${e.op}${g.gen_expr(e.right)})"}
      ExprUnary  {"(${e.op}${g.gen_expr(e.operand)})"}
      ExprIndex  {"${g.gen_expr(e.indexee)}[${g.gen_expr(e.idx)}]"}
      ExprAccess {
        if g.checked_ast.enum_accesses.contains(e.id) {
          "${e.member.name}"
        } else {
          "${g.gen_expr(e.accessee)}.${e.member.name}"
        }
      }
    } + post
  }
}

fn (mut g Generator) gen_stmt(s Stmt) {
  g.span = s.span
  match s {
    StmtNoop {}
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
      if g.current_scope.parent == none {
        g.gend_globals.writeln("${g.gen_type_left(sym.type, false)} ${g.mangle_ident(s.sym.name)}${g.gen_type_right(sym.type, false)} = ${g.gen_expr(s.value)};")
      } else {
        g.writeln_tabbed("${g.gen_type_left(sym.type, false)} ${g.mangle_ident(s.sym.name)}${g.gen_type_right(sym.type, false)} = ${g.gen_expr(s.value)};")
      }
    }
    StmtDeclFunc {
      sym := if s in g.checked_ast.monomorph_decls {
        s.sym 
      } else {
        g.current_scope.lookup_sym(s.sym.name) or {g.gen_error("didn't find func symbol (bad!)")}
      }

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
      mut declar := "${g.gen_type_left(sym.type.ret, true)} ${g.mangle_ident(sym.name)}("
      for arg in args {
        declar += "${g.gen_type_left(arg.type, false)} ${g.mangle_ident(arg.name)}${g.gen_type_right(arg.type, false)}" 
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
        } else {
          g.write_tabbed("")
        }
        g.gend_main.write_string("${name}(") 
        mut wrap_argv := ""
        for arg in args {
          wrap_argv += "${g.mangle_ident(arg.name)}"
          if arg != args[args.len-1] {
            wrap_argv += ", "
          }
        }
        g.gend_main.writeln("${wrap_argv});")
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
      resolved_sym := g.checked_ast.table.structs[s.sym.name] or {g.gen_error("couldn't find struct ${s.sym.name} in symtable")}
      if s.sym.qualifs.contains(.extern) {
        g.gend_struct_decl.writeln("#define ${g.mangle_ident(s.sym.name)} ${s.sym.name}")
        return
      }
      g.gend_struct_decl.writeln("struct ${g.mangle_ident(s.sym.name)} {")
      for m in resolved_sym.member_syms {
        g.gend_struct_decl.writeln("\t${g.gen_type_left(m.type, false)} ${m.name};")
      }
      g.gend_struct_decl.writeln("};\n")
    }
    StmtDeclMember {
      g.gen_error("unrechable")
      //g.gend_struct_decl.writeln("\t${g.gen_type_left(s.type)} ${s.name};")
    }
    StmtDeclEnum {
      g.gend_struct_decl.writeln("enum ${g.mangle_ident(s.sym.name)} {")
      for m in s.members {
        g.gen_stmt(m)
      }
      g.gend_struct_decl.writeln("};")
    }
    StmtDeclEnumMember {
      mut es := s.name
      if s.override_value != none {
        es += " = ${g.gen_expr(s.override_value)}" 
      }
      g.gend_struct_decl.writeln("\t${es},")
    }
    StmtAssign {
      g.writeln_tabbed("${g.gen_expr(s.assignee)} ${s.op} ${g.gen_expr(s.val)};")
    }
    StmtInclude {}
    StmtWhile {
      g.writeln_tabbed("while (${g.gen_expr(s.guard)}) {")
      g.gen_stmt(s.block)
      g.writeln_tabbed("}")
    }
    StmtBranch {
      g.writeln_tabbed("if (${g.gen_expr(s.if_guard)}) {")
      g.gen_stmt(s.if_block)
      g.writeln_tabbed("}")
      if s.elif_guards != none && s.elif_blocks != none {
        for i := 0; i < s.elif_guards.len ; i++ {
          g.writeln_tabbed("else if (${g.gen_expr(s.elif_guards[i])}) {")
          g.gen_stmt(s.elif_blocks[i])
          g.writeln_tabbed("}")
        }
      }
      if s.else_block != none {
        g.writeln_tabbed("else {")
        g.gen_stmt(s.else_block)
        g.writeln_tabbed("}")
      }
    }
    StmtFor {g.gen_error("unimplemented for")}
    StmtDirectiveLink {
      if s.lib !in g.libs_to_link {
        g.libs_to_link << s.lib
      }
    }
    StmtDirectiveCInclude {
      if s.header !in g.hs_to_include {
        g.hs_to_include << s.header
      }
    }
    StmtDeclConstraint {}
    StmtGeneric {}
    //else {g.gen_error("unimplemented stmt ${s}")}
  }
}

fn Generator.gen_program(checked_ast CheckedAST) GeneratorResult {
  mut g := Generator{checked_ast: checked_ast, current_scope: checked_ast.table.root_scope}

  for decl in g.checked_ast.monomorph_decls {
    g.gen_stmt(decl)
  }

  for stmt in g.checked_ast.ast {
    g.gen_stmt(stmt)
  }

  for header in g.hs_to_include {
    g.gend_includes.writeln("#include <${header}>")
  }
  
  g.gend_includes.writeln("#include <stdio.h>")
  g.gend_includes.writeln("#include <stdint.h>")
  g.gend_includes.writeln("#include <stdlib.h>")
  g.gend_includes.writeln("#include <stdbool.h>")
  g.gend_includes.writeln("#include <string.h>")
  g.gend_includes.writeln("#include <assert.h>")
  g.gend_includes.writeln("#include <math.h>")


  g.gend_main.writeln("int main(void) {\n\treturn ${g.mangle_ident("main")}();\n}")

  mut generated := ""
  generated += g.gend_includes.str()
  generated += "// -- types --\n${g.gend_struct_decl}"
  generated += "// -- globals --\n${g.gend_globals}"
  generated += "// -- fn decl --\n${g.gend_fn_decl}"
  generated += "// -- program --\n${g.gend_main.str()}"

  return GeneratorResult {text: generated, to_link: g.libs_to_link}
}
