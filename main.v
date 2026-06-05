module main

import os

fn main() {

  path := if os.args.len > 1 {os.args[1]} else {"source.iris"}

  toks := Lexer.lex_file(path)
  println(toks)
  ast := Parser.parse_program(toks)
  println(ast)
  c_ast := Checker.check_program(ast)
  Generator.gen_program(c_ast)
}
