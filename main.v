module main

import os

fn main() {
  content := os.read_file("source.iris") or {return}
  toks := Lexer.lex_input(content)
  println(toks)
}
