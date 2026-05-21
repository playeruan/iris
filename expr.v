
module main

// -- Expr

enum LiteralKind as u8 {
  int
  float
  bool
  string
  // TODO: type
}

union LiteralValue {
  i64 i64 
  f64 f64
  bool bool
  string string
}

type Expr = 
  ExprVar | ExprLiteralPrimitive | ExprGroup |
  ExprCall | ExprIndex | ExprAccess |
  ExprType | ExprCast | ExprLiteralStruct | 
  ExprLiteralArray | ExprRef | ExprDeref

struct ExprVar {
  name string
}

struct ExprLiteralPrimitive {
  kind LiteralKind
  value LiteralValue 
}

struct ExprLiteralStruct {
  type TypeStruct
  argv []Expr
}

struct ExprLiteralArray {
  of_type Type
  argv []Expr
}

struct ExprGroup {
  inner Expr
}

struct ExprCall {
  callee Expr
  argv []Expr
}

struct ExprIndex {
  indexee Expr
  idx     Expr
}

struct ExprAccess {
  accessee  Expr
  member    ExprVar
}

struct ExprType {
  type Type
}

struct ExprCast {
  castee Expr
  type Type
}

struct ExprRef {
  inner Expr
}

struct ExprDeref {
  inner Expr
}

struct ExprBinary {
  op string
  left Expr
  right Expr
}

struct ExprUnary {
  op string
  operand Expr
}
