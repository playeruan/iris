
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

// -- Stmt

type Stmt = 
  StmtExpr | StmtBlock | StmtDeclVar |
  StmtDeclFunc | StmtDeclMember | StmtDeclStruct |
  StmtReturn | StmtContinue | StmtBreak |
  StmtBranch | StmtWhile | StmtFor | StmtAssign |
  StmtDeclEnum

struct StmtExpr {
  expr Expr
  span Span
}

struct StmtBlock {
  stmts []Stmt
  span Span
}

struct StmtDeclVar {
  sym Symbol
  value Expr
  span Span
}

struct StmtDeclFunc {
  sym Symbol
  block StmtBlock
  span Span
}

struct StmtDeclMember {
  name string
  type Type
  default_value ?Expr
  span Span
}

struct StmtDeclStruct {
  sym Symbol
  members []StmtDeclMember
  span Span
}

struct StmtDeclEnum {
  sym Symbol
  members []StmtDeclMember
  span Span
}

struct StmtReturn {
  expr Expr
  span Span
}

struct StmtBranch {
  if_guard Expr 
  if_block StmtBlock
  elif_guards ?[]Expr
  elif_blocks ?[]StmtBlock
  else_block ?StmtBlock
  span Span
}

struct StmtFor {
  start Stmt
  guard Expr
  loop  Stmt
  block StmtBlock
  span Span
}

struct StmtWhile {
  guard Expr
  block StmtBlock
  span Span
}

struct StmtContinue {
  span Span
}

struct StmtBreak {
  span Span
}

struct StmtAssign {
  assignee Expr
  val Expr
  span Span
}
