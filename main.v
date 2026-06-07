module main

import os

fn main() {

  path := if os.args.len > 1 {os.args[1]} else {"source.iris"}

  toks := Lexer.lex_file(path)
  //eprintln(toks)
  ast := Parser.parse_program(toks, 0).ast
  //eprintln(ast)
  c_ast := Checker.check_program(ast)
  generated := Generator.gen_program(c_ast)

  os.write_file("out.c", generated.text) or {panic("unable to write out.c")}
  mut command := "clang out.c -Wall "
  for lib in generated.to_link {
    command += "-l${lib} "
  }
  command += "-o out"
  os.execute_or_exit(command)
}
