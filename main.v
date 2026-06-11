module main

import os

fn main() {

  path := if os.args.len > 1 {os.args[1]} else {"source.iris"}

  toks := Lexer.lex_file(path)
  //eprintln(toks)
  parsed := Parser.parse_program(toks, 0, [path])
  //eprintln(ast)
  c_ast := Checker.check_program(parsed)
  //eprintln(c_ast.table)
  generated := Generator.gen_program(c_ast)

  os.write_file("out.c", generated.text) or {panic("unable to write out.c")}
  mut command := "clang -g out.c "
  for lib in generated.to_link {
    command += "-l${lib} "
  }
  command += "-o out"
  os.execute_or_exit(command)
}
