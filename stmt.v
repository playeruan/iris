
module main

// -- DeclQualifier

enum DeclQualifier as u8 {
  extern
  export
}

fn (qs []DeclQualifier) str() string {
  mut s := ""
  for q in qs {
    s += q.str() + " "
  }
	return s
}

fn (q DeclQualifier) valid_for_decl(s Stmt) bool {
  valid := match s {
    StmtDeclFunc, StmtDeclStruct {[DeclQualifier.extern]}
    else {[]}
  }
  return valid.contains(q)
}

// -- Stmt

type Stmt = 
  StmtExpr | StmtBlock | StmtDeclVar |
  StmtDeclFunc | StmtDeclMember | StmtDeclStruct |
  StmtReturn | StmtContinue | StmtBreak |
  StmtBranch | StmtWhile | StmtFor | StmtAssign |
  StmtDeclEnum | StmtDeclEnumMember | StmtInclude |
  StmtDirectiveLink | StmtDeclConstraint |
  StmtGeneric | StmtNoop

struct StmtExpr {
  expr Expr
  span Span
  id i32
}

struct StmtBlock {
  stmts []Stmt
  span Span
  id i32
}

struct StmtDeclVar {
  sym Symbol
  value Expr
  span Span
  id i32
}

struct StmtDeclFunc {
  sym Symbol
  block StmtBlock
  span Span
  id i32
}

struct StmtDeclMember {
  name string
  type Type
  default_value ?Expr
  span Span
  id i32
}

struct StmtDeclStruct {
  sym Symbol
  members []StmtDeclMember
  span Span
  id i32
}

struct StmtDeclEnumMember {
  name string
  type Type
  override_value ?Expr
  span Span
  id i32
}

struct StmtDeclEnum {
  sym Symbol
  members []StmtDeclEnumMember
  span Span
  id i32
}

struct StmtReturn {
  expr Expr
  span Span
  id i32
}

struct StmtBranch {
  if_guard Expr 
  if_block StmtBlock
  elif_guards ?[]Expr
  elif_blocks ?[]StmtBlock
  else_block ?StmtBlock
  span Span
  id i32
}

struct StmtFor {
  start Stmt
  guard Expr
  loop  Stmt
  block StmtBlock
  span Span
  id i32
}

struct StmtWhile {
  guard Expr
  block StmtBlock
  span Span
  id i32
}

struct StmtContinue {
  span Span
  id i32
}

struct StmtBreak {
  span Span
  id i32
}

struct StmtAssign {
  assignee Expr
  op string
  val Expr
  span Span
  id i32
}

struct StmtInclude {
  path string
  span Span
  id i32
}

struct StmtDirectiveLink {
  lib string
  span Span
  id i32
}

struct StmtGeneric {
  type_params []string
  constraints []string
  decl Stmt
  span Span
  id i32
}

struct StmtDeclConstraint {
  name string
  types []Type
  span Span
  id i32
}

struct StmtNoop {
  span Span
  id i32
}
