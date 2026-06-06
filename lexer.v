module main

import os

struct Lexer {
  mut: 
  source string
  tokens []Token
  pos u32
  span Span
}

fn (l Lexer) tok(kind TokKind, value TokValue, text string) Token {
  return Token{
    kind: kind,
    value: value,
    text: text,
    span: l.span
  }
}

@[noreturn]
fn (l Lexer) lex_error(s string) {
  eprintln("${l.span} Lexer Error -> \"${s}\"")
	exit(1)
}

fn (l Lexer) is_at_end() bool {
	return l.pos >= l.source.len-1 || l.source[l.pos] == `\0`
}

fn (l Lexer) peek() u8 {
  return l.source[l.pos]
}

fn (l Lexer) peek_next() u8 {
  if l.is_at_end() {
    l.lex_error("tried to peek_next() at EOF")
}
  return l.source[l.pos+1]
}

fn (mut l Lexer) advance() u8 {
  c := l.source[l.pos]
	if c == `\n` { l.span.row++; l.span.col = 0 }
  else         { l.span.col++ }
  l.pos++
  return c
}

fn (mut l Lexer) skip_space() {
  for !l.is_at_end() && l.peek().is_space() {
		l.advance()
	}
}

fn (mut l Lexer) lex_string() Token {
  assert(l.peek() == `"`)
  l.advance()
  start := l.pos
	for l.peek() != `"` && !l.is_at_end() {
		// escapes such as \"
		if l.peek() == `\\` && l.peek_next() == `"` {
			l.advance()
		}
		l.advance()
	}

	if l.is_at_end() { l.lex_error('Unterminated string') }

	lit := l.source[start..l.pos]
  assert(l.peek() == `"`)
	l.advance() // skip closing "
	return l.tok(.l_string, TokValue{string: lit}, lit)
}

fn (mut l Lexer) lex_number() Token {
  start := l.pos
	mut seen_point := false
	for !l.is_at_end() && 
      (l.peek().is_digit() || (!seen_point && l.peek() == `.`)) 
  {
		if l.peek() == `.` {
			seen_point = true
		}
		l.advance()
	}

	text := l.source[start..l.pos]
	if seen_point {
		return l.tok(.l_float, TokValue{f64: text.f64()}, text)
	} else {
		return l.tok(.l_int, TokValue{i64: text.i64()}, text)
	}
}

fn (mut l Lexer) lex_ident() Token {
	start := l.pos
	for !l.is_at_end() && (l.peek().is_alnum() || l.peek() == `_`) {
		l.advance()
	}

	lit := l.source[start..l.pos]
	kind := Token.from_str(lit) or {TokKind.identifier}
	return l.tok(kind, TokValue{void: none}, lit)
}

const delimiters := ",;.:+-*/%#()[]{}<>=|&^|@~!-\""
fn (mut l Lexer) lex_delimiter() Token {
	start := l.pos
	l.advance()
	for !l.is_at_end() && Token.from_str(l.source[start..l.pos+1]) != none {
		l.advance()
	}

	lit := l.source[start..l.pos]
	kind := Token.from_str(lit) or {l.lex_error("invalid string ${lit}")}

  assert(kind != .invalid) //TODO: find better way of allowing "..."

	return l.tok(kind, TokValue{void: none}, lit)
}

fn (mut l Lexer) next_tok() Token {
  l.skip_space()

  if l.is_at_end() {
    return l.tok(.eof, TokValue{void: none}, "")
  }

  mut c := l.peek()

  if c == `"` {
    return l.lex_string()
  }

  if c.is_digit() {
    return l.lex_number()
  }

  if c.is_letter() || c == `_` {
    return l.lex_ident()
  }

  if delimiters.contains(c.ascii_str()) {
    return l.lex_delimiter()
  }

  l.lex_error("invalid character ${c}")
}

fn Lexer.lex_file(path string) []Token {

  input := os.read_file(path) or {return []}

  mut l := Lexer{}
  l.source = input
  l.span.row = 1
  l.span.file = path

  mut ts := []Token{}

  for ts.len == 0 || ts[ts.len-1].kind != .eof {
    ts << l.next_tok()
  }

  return ts
}
