
module main

// -- Expr

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
  ExprLiteralArray | ExprRef | ExprDeref |
  ExprBinary | ExprUnary | ExprEnumAccess

struct ExprVar {
  name string
}

struct ExprLiteralPrimitive {
  type TypePrimitive 
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

struct ExprEnumAccess {
  enum Expr
  member string
}
