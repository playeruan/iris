
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
  ExprBinary | ExprUnary | ExprSizeof |
  ExprLiteralNullptr

struct ExprVar {
  name string
  id i32
}

struct ExprLiteralPrimitive {
  type TypePrimitive 
  value LiteralValue 
  id i32
}

struct ExprLiteralStruct {
  type TypeStruct
  generic_args []Type
  argv []Expr
  id i32
}

struct ExprLiteralArray {
  of_type Type
  argv []Expr
  id i32
}

struct ExprLiteralNullptr {
  id i32
}

struct ExprGroup {
  inner Expr
  id i32
}

struct ExprCall {
  callee Expr
  argv []Expr
  id i32
}

struct ExprIndex {
  indexee Expr
  idx     Expr
  id i32
}

struct ExprAccess {
  accessee  Expr
  member    ExprVar
  id i32
}

struct ExprType {
  type Type
  id i32
}

struct ExprCast {
  castee Expr
  type Type
  id i32
}

struct ExprRef {
  inner Expr
  id i32
}

struct ExprDeref {
  inner Expr
  id i32
}

struct ExprBinary {
  op string
  left Expr
  right Expr
  id i32
}

struct ExprUnary {
  op string
  operand Expr
  id i32
}

struct ExprSizeof {
  expr Expr 
  id i32
}
