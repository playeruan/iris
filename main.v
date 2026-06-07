module main

import os

fn main() {

  path := if os.args.len > 1 {os.args[1]} else {"source.iris"}

  toks := Lexer.lex_file(path)
  eprintln(toks)
  ast := Parser.parse_program(toks)
  eprintln(ast)
  c_ast := Checker.check_program(ast)
  Generator.gen_program(c_ast)
}
