
module main

// -- Parser

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
    panic("TODO: type qualifier")
  }
  return []
}

fn (mut p Parser) parse_primary() Expr {
  t := p.peek()
  if t.kind.is_type_qualifier() || t.kind.is_primitive_type() ||
    t.kind == .caret {
    p.parse_type()
  }
  p.advance()
  return match t.kind {
    .l_int {Expr{}}
    .l_float {Expr{}}
    // TODO: ^^^^ these
  }
}

fn (mut p Parser) parse_type() Type {
  qualifs := []TypeQualifier{}
  //TODO: qualifs := p.parse_type_qualifs()
  if p.peek().kind == .lparen {
    // function
    p.advance()
    return p.parse_func_type(qualifs)
  } else if p.peek().kind == .lsquare {
    // array
    p.advance()
    p.expect(.rsquare)
    return TypeArray{
      qualifs: qualifs
      inner: p.parse_type()
    }
  } else if p.peek().kind == .caret {
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
    return TypeStruct {
      qualifs: qualifs
      name: tok_name.text
    }
  }
}

fn (mut p Parser) parse_func_type(qualifs []TypeQualifier) TypeFunc {
  p.expect(.lparen)
  mut param_names := []string{}
  mut arg_types := []Type{}

  for p.peek().kind != .rparen {
    param_names << p.advance().text
    p.expect(.colon)
    arg_types << p.parse_type()
  }

  if p.peek().kind != .rparen {
    p.expect(.comma)
  }

  p.expect(.rparen)
  p.expect(.arrow)
  ret := p.parse_type()
  return TypeFunc {
    qualifs: qualifs
    arg_types: arg_types
    ret: ret
  }
}
