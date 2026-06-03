
module main

// -- Parser
import os 
import strings

struct Parser {
  mut: 
  toks []Token
  ast []Stmt
  pos u32
  span Span
}

@[noreturn]
fn (p Parser) parse_error(s string) {
  eprintln("${p.span} Parser Error -> \"${s}\"")
  eprintln("current AST tree ${p.ast}")
	exit(1)
}

fn (p Parser) parse_warning(s string) {
  eprintln("${p.span} Parser Warning -> \"${s}\"")
}

fn (p Parser) peek() Token {
  return p.toks[p.pos]
}

fn (p Parser) peek_next() Token {
  if p.pos+1 >= p.toks.len {
    p.parse_error("tried to peek_next() at EOF")
  }
  return p.toks[p.pos + 1]
}

fn (mut p Parser) advance() Token {
  t := p.peek()
  p.span = t.span
  p.pos++
  return t
}

fn (mut p Parser) expect(k TokKind) Token {
  if p.peek().kind != k {
    p.parse_error("expected token of kind ${k}, got ${p.peek().kind}")
  }
  return p.advance()
}

// parsing expressions

fn (mut p Parser) parse_type_qualifs() []TypeQualifier {
  mut qualifs := []TypeQualifier{}
  for p.peek().kind.is_type_qualifier() {
    q := p.peek().kind.get_type_qualifier()
    if qualifs.contains(q) {
      p.parse_warning("qualifier ${q} already specified")
    }
    qualifs << q
    p.advance()
  }
  return qualifs
}

fn (mut p Parser) parse_primary() Expr {
  t := p.peek()
  if t.kind.is_type_qualifier() || t.kind.is_primitive_type() {
    return ExprType{type: p.parse_type()}
  }
  p.advance()
  return match t.kind {
    .l_int    {
      ExprLiteralPrimitive{
        type: TypePrimitive {
          qualifs: [.const]
          type: .i32
        }
        value: LiteralValue{i64: t.text.i64()}
      }
    }
    .l_float  {
      ExprLiteralPrimitive{
        type: TypePrimitive {
          qualifs: [.const]
          type: .f32
        }
        value: LiteralValue{f64: t.text.f64()}
      }
    }
    .l_true, .l_false {
      ExprLiteralPrimitive{
        type: TypePrimitive {
          qualifs: [.const]
          type: .bool
        }
        value: LiteralValue{bool: t.kind == .l_true}
      }
    }
    .l_string {
      ExprLiteralPrimitive{
        type: TypePrimitive {
          qualifs: [.const]
          type: .string
        }
        value: LiteralValue{string: t.text}
      } 
    }
    .identifier {
      if t.text.starts_with_capital() && p.peek().kind == .lparen {
        // Struct instanciation
        p.expect(.lparen)
        mut argv := []Expr{}
        for p.peek().kind != .rparen {
          argv << p.parse_expr(.literal)
            if p.peek().kind != .rparen {
              p.expect(.comma)
            }
        }
        p.expect(.rparen)
        ExprLiteralStruct{
          type: TypeStruct {
            qualifs: [.const]
            name: t.text
          }
          argv: argv
        }
      } else {
        ExprVar{name: t.text}
      }
    }
    .lparen {
      e := ExprGroup{inner: p.parse_expr(.literal)}
      p.expect(.rparen)
      e
    }
    .lsquare {
      mut elems := []Expr{}
      for p.peek().kind != .rsquare {
        elems << p.parse_expr(.literal)
        if p.peek().kind != .rsquare {
          p.expect(.comma)
        }
      }
      p.expect(.rsquare)
      ExprLiteralArray{argv: elems}
    }
    .o_minus, .o_exclam, .o_tilde, .o_plusplus, .o_minusminus {p.parse_unary_prefix(t.text, .prefix)}
    .o_and {
      ExprRef{inner: p.parse_expr(.prefix)}
    }
    .o_caret {
      ExprDeref{inner: p.parse_expr(.prefix)}
    }
    else {p.parse_error("invalid expr token of kind ${t.kind}")}
  }
}

fn (mut p Parser) parse_call(callee Expr) ExprCall {
  mut argv := []Expr{}
  for p.peek().kind != .rparen {
    argv << p.parse_expr(.literal)
    if p.peek().kind != .rparen {
      p.expect(.comma)
    }
  }
  p.expect(.rparen)
  return ExprCall{callee: callee, argv: argv}
}

fn (mut p Parser) parse_unary_prefix(op string, prec Precedence) Expr {
  right := p.parse_expr(prec)
  return ExprUnary{op: op, operand: right}
}

fn (mut p Parser) parse_binary(left Expr, op string, prec Precedence) Expr {
  right := p.parse_expr(prec)
  return ExprBinary{op: op, left: left, right: right}
}

fn (mut p Parser) parse_expr(pr Precedence) Expr {
  mut expr := p.parse_primary()

  for int(pr) < int(p.peek().kind.precedence()) {
    op_tok := p.advance() 
    expr = match op_tok.kind {
      .lparen {p.parse_call(expr)}
      .lsquare {
        idx := p.parse_expr(.literal)
        p.expect(.rsquare)
        ExprIndex{indexee: expr, idx: idx}
      }
      .dot {
        ident := p.expect(.identifier)
        ExprAccess{accessee: expr, member: ExprVar{name: ident.text}}
      }
      .at {
        t := p.parse_type()
        ExprCast{castee: expr, type: t}
      }
      else {p.parse_binary(expr, op_tok.text, op_tok.kind.precedence())}
    }
  }

  return expr
}

// parsing statements 

fn (mut p Parser) parse_decl_qualifs() []DeclQualifier {
  mut qualifs := []DeclQualifier{}
  for p.peek().kind.is_decl_qualifier() {
    q := p.peek().kind.get_decl_qualifier()
    if qualifs.contains(q) {
      p.parse_warning("qualifier ${q} already specified")
    }
    qualifs << q
    p.advance()
  }
  return qualifs
}

fn (mut p Parser) parse_block() StmtBlock {
  p.expect(.lbrace)
  mut stmts := []Stmt{}
  for p.peek().kind != .rbrace {
    stmts << p.parse_stmt()
  }
  p.expect(.rbrace)
  return StmtBlock {
    stmts: stmts 
    span: p.span
  }
}

fn (mut p Parser) parse_stmt_expr() Stmt {
  expr := p.parse_expr(.literal) 

  if expr is ExprVar && p.peek().kind == .colon {
    return p.parse_decl(expr) 
  }

  if p.peek().kind == .o_eq {
    return p.parse_assignment(expr)
  }

  p.expect(.semicolon)
  return StmtExpr {
    expr: expr
    span: p.span
  }
}

fn (mut p Parser) parse_decl(var_expr ExprVar) Stmt {
  p.expect(.colon)
  typ := p.parse_type()

  if typ is TypeFunc && p.peek().kind == .lbrace {

    b := p.parse_block()
    mut arg_symbols := []Symbol{}
    for i := 0; i < typ.arg_names.len; i++ {
      arg_symbols << SymbolVar{
        name: typ.arg_names[i]
        type: typ.arg_types[i]
      }
    }
    return StmtDeclFunc {
      sym: SymbolFunc {
        name: var_expr.name 
        type: typ
        arg_syms: arg_symbols
      }
      block: b 
      span: p.span
    }
  } else {
    p.expect(.o_eq)
    val := p.parse_expr(.literal)
    p.expect(.semicolon)
    return StmtDeclVar {
      sym: SymbolVar {
        name: var_expr.name
        type: typ
      }    
      value: val 
      span: p.span
    }
  }
}

fn (mut p Parser) parse_assignment(left Expr) StmtAssign {
  p.expect(.o_eq)
  v := p.parse_expr(.literal)
  p.expect(.semicolon)
  return StmtAssign {
    assignee: left
    val: v
    span: p.span
  }
}

fn (mut p Parser) parse_while() StmtWhile {
  p.expect(.while)

  g := p.parse_expr(.literal)
  b := p.parse_block()

  return StmtWhile {
    guard: g
    block: b
    span: p.span
  }
}

fn (mut p Parser) parse_branch() StmtBranch {
  p.expect(.if)

  if_g := p.parse_expr(.literal)
  if_b := p.parse_block()

  mut elif_gs := []Expr{}
  mut elif_bs := []StmtBlock{}

  for p.peek().kind == .elif {
    p.expect(.elif)
    dump(p.peek())
    elif_gs << p.parse_expr(.literal)
    dump(p.peek())
    elif_bs << p.parse_block()
  }

  mut else_b := ?StmtBlock(none)

  if p.peek().kind == .else {
    p.expect(.else)
    else_b = p.parse_block()
  }

  return StmtBranch {
    if_guard: if_g 
    if_block: if_b
    elif_guards: if elif_gs.len > 0 {elif_gs} else {none}
    elif_blocks: if elif_bs.len > 0 {elif_bs} else {none}
    else_block: else_b
  }
}

fn (mut p Parser) parse_stmt() Stmt {
  
  if p.peek().kind.is_decl_qualifier() {
    qualifs := p.parse_decl_qualifs()
    panic("unimplemented decl qualifs") 
  }

  return match p.peek().kind {
    .ret {
      p.advance()
      r := StmtReturn{
        expr: 
          if p.peek().kind == .semicolon {
            ExprLiteralPrimitive{type: TypePrimitive{type: .void}}
          } else {
            p.parse_expr(.literal)
          }
        span: p.span
      }
      p.expect(.semicolon)
      r
    }
    .lbrace {p.parse_block()}
    .continue {
      p.advance()
      c := StmtContinue{span: p.span}
      p.expect(.semicolon)
      c
    }
    .break  {
      p.advance()
      b := StmtBreak{span: p.span}
      p.expect(.semicolon)
      b
    }
    .enum {
      p.advance()
      t_name := p.expect(.identifier)
      p.expect(.lbrace)

      mut member_decls := []StmtDeclEnumMember{}
      mut mem_syms := []Symbol{}
      
      for p.peek().kind != .rbrace {
        n := p.expect(.identifier).text 
        mut def_val := ?Expr(none)

        if p.peek().kind == .o_eq {
          p.advance()
          def_val = p.parse_expr(.literal)
        }

        if p.peek().kind == .comma {
          p.expect(.comma)
        }

        member_decls << StmtDeclEnumMember{
          name: n 
          type: TypePrimitive{type: .i32} 
          override_value: def_val
          span: p.span
        }
        mem_syms << SymbolVar{
          qualifs: [] //TODO: handle qualifs for members
          name: n 
          type: TypePrimitive{type: .i32} 
        }
      }
      
      p.expect(.rbrace)


      StmtDeclEnum{
        sym: SymbolEnum{
          name: t_name.text
          type: TypeEnum{name: t_name.text, as: TypePrimitive{type: .i32}} 
          member_syms: mem_syms
        } 
        members: member_decls
        span: p.span
      }

    }
    .struct {
      p.advance() 
      t_name := p.expect(.identifier)
      p.expect(.lbrace)

      mut member_decls := []StmtDeclMember{}
      mut mem_syms := []Symbol{}
      
      for p.peek().kind != .rbrace {
        n := p.expect(.identifier).text 
        p.expect(.colon)
        t := p.parse_type()
        mut def_val := ?Expr(none)

        if p.peek().kind == .o_eq {
          if t is TypeFunc {
            p.parse_error("a member of type ${Type(t)} cannot have a default value") 
          }
          p.advance()
          def_val = p.parse_expr(.literal)
        }

        p.expect(.semicolon)
        member_decls << StmtDeclMember{
          name: n 
          type: t
          default_value: def_val
          span: p.span
        }
        mem_syms << SymbolVar{
          qualifs: [] //TODO: handle qualifs for members
          name: n 
          type: t 
        }
      }
      
      p.expect(.rbrace)


      StmtDeclStruct{
        sym: SymbolStruct{
          name: t_name.text
          type: TypeStruct {
            name: t_name.text
          }
          member_syms: mem_syms
        } 
        members: member_decls
        span: p.span
      }

    }
    .include {
      p.advance()
      path := p.expect(.l_string)


      if !os.exists(path.text) {
        p.parse_error("imported file ${path.text} does not exist")
      }

      new_toks := Lexer.lex_file(path.text)
      inserted_ast := Parser.parse_program(new_toks)
      p.ast << inserted_ast 

      StmtInclude{
        path: path.text
        span: p.span
      }
    }
    .while  {p.parse_while()}
    .for    {p.parse_error("for not yet supported because I'm lazy")}
    .if     {p.parse_branch()}
    .else   {p.parse_error("standalone else statement")}
    .elif   {p.parse_error("standalone elif statement")}
    else {p.parse_stmt_expr()}
  }
}

// parsing types

fn (mut p Parser) parse_type() Type {
  qualifs := p.parse_type_qualifs()
  if p.peek().kind == .lparen {
    // function
    return p.parse_func_type(qualifs)
  } else if p.peek().kind == .lsquare {
    // array
    p.advance()
    p.expect(.rsquare)
    return TypeArray{
      qualifs: qualifs
      inner: p.parse_type()
    }
  } else if p.peek().kind == .o_caret {
    p.advance()
    return TypePointer{
      qualifs: qualifs
      inner: p.parse_type()
    }
  }

  if p.peek().kind.is_primitive_type() {
    tok_name := p.advance()
    return TypePrimitive {
      qualifs: qualifs
      type: BuiltinType.from_tok_kind(tok_name.kind)
    }
  } else {
    tok_name := p.advance()
    // may be struct or enum
    return TypeUnresolved {
      qualifs: qualifs
      name: tok_name.text
    }
  }
}

fn (mut p Parser) parse_func_type(qualifs []TypeQualifier) TypeFunc {
  p.expect(.lparen)
  mut arg_names := []string{}
  mut arg_types := []Type{}

  for p.peek().kind != .rparen {
    arg_names << p.advance().text
    p.expect(.colon)
    arg_types << p.parse_type()

    if p.peek().kind != .rparen {
      p.expect(.comma)
    }
  }

  p.expect(.rparen)

  mut captured_names := []string{}

  if p.peek().kind == .lsquare {
    p.expect(.lsquare)
    for p.peek().kind != .rsquare {
      captured_names << p.advance().text

      if p.peek().kind != .rsquare {
        p.expect(.comma)
      }
    }

    p.expect(.rsquare)
  }

  mut ret := Type(TypePrimitive{type: .void})

  if p.peek().kind == .arrow {
    p.expect(.arrow)
    ret = p.parse_type()
  }

  return TypeFunc {
    qualifs: qualifs
    arg_types: arg_types
    arg_names: arg_names
    captured_names: captured_names
    ret: ret
  }
}

fn Parser.parse_program(toks []Token) []Stmt {
  mut p := Parser{toks: toks}
  for p.peek().kind != .eof {
    p.ast << p.parse_stmt()
  }
  return p.ast
}
