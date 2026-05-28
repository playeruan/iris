
module main

// -- Symbol

type Symbol = SymbolVar | SymbolFunc | SymbolStruct

struct SymbolVar {
  qualifs []DeclQualifier
  name string
  type Type
}

struct SymbolFunc {
  qualifs []DeclQualifier
  name string
  type Type
  arg_syms []SymbolVar
}

struct SymbolStruct {
  qualifs []DeclQualifier
  name string
  type Type
  member_syms []SymbolVar
}

// -- Scope

struct Scope {
  parent ?&Scope
  mut:
  syms map[string]Symbol
}

// -- SymbolTable

struct SymbolTable {
  mut:
  root_scope &Scope = &Scope{}
  structs map[string]SymbolStruct
}

fn (s Scope) lookup_sym(name string) ?Symbol {
  if name in s.syms {
    return s.syms[name] or {panic("unreachable")}
  }
  if s.parent != none {
    return s.parent.lookup_sym(name)
  }
  return none
}

