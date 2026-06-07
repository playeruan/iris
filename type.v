
module main

// -- TypeQualifier

enum TypeQualifier as u8 {
  const
}

fn (qs []TypeQualifier) str() string {
  mut s := ""
  for q in qs {
    s += q.str() + " "
  }
	return s
}

// -- Type

enum BuiltinType as u8 {
  void
  i8
  i16
  i32
  u8 // TODO: implement this properly
  u16
  u32
  f32
  f64
  bool
  string
  type
  any
}

fn BuiltinType.from_tok_kind(t TokKind) BuiltinType {
  return match t {
    .t_i32    {BuiltinType.i32}
    .t_u32    {.u32}
    .t_i16    {.i16}
    .t_u16    {.u16}
    .t_i8     {.i8}
    .t_u8     {.u8}
    .t_f32    {.f32}
    .t_f64    {.f64}
    .t_bool   {.bool}
    .t_void   {.void}
    .t_type   {.type}
    .t_string {.string}
    .t_any    {.any}
    else      {
      panic("invalid TokKind ${t} to convert to BuiltinType")
    }
  }
}

fn (t BuiltinType) size() i32 {
  return match t {
    .void, .string, .type, .any {0} // TODO: .string, .type, .any sizes
    .i8, .u8, .bool {1}
    .i16, .u16 {2}
    .i32, .u32 {4}
    .f32 {4}
    .f64 {8}
  }
}

fn (t BuiltinType) is_int() bool {
  return t.str().starts_with("i") || t.str().starts_with("u")
}

fn (t BuiltinType) is_float() bool {
  return t.str().starts_with("f")
}

fn (t BuiltinType) is_unsigned() bool {
  assert(t.is_int())
  return t.str().starts_with("u")
}

fn BuiltinType.smallest_int(from i64, unsigned bool) BuiltinType {
  if unsigned {
    assert(from < 1<<32)
    if from < 1<<8  { return .u8  }
    if from < 1<<16 { return .u16 }
    if from < 1<<32 { return .u32 }
  }
  f_ := if from >= 0 {from} else {-from}
  assert(f_ < 1<<31)
  if f_ < 1<<7  { return .i8  }
  if f_ < 1<<15 { return .i16 }
  if f_ < 1<<31 { return .i32 }
  return .void // invalid, unreachable
}

type Type = 
  TypePrimitive | TypeFunc | TypePointer | 
  TypeArray | TypeStruct | TypeEnum |
  TypeUnresolved

struct TypePrimitive {
  qualifs []TypeQualifier
  type BuiltinType 
}

struct TypeFunc {
  qualifs []TypeQualifier
  arg_types []Type
  arg_names []string
  variadic_type ?Type  // none if function is not variadic
  captured_names []string
  ret Type
}

struct TypePointer {
  qualifs []TypeQualifier
  inner Type
}

struct TypeArray {
  qualifs []TypeQualifier
  inner Type
}

struct TypeStruct {
  qualifs []TypeQualifier
  name string 
}

struct TypeEnum {
  qualifs []TypeQualifier
  name string
  as Type
}

// for things that clearly should be 
// types but we're unsure of which
// kind
struct TypeUnresolved {
  qualifs []TypeQualifier
  name string
}

fn (t Type) str() string {
  mut type_str := t.qualifs.str()
  type_str += match t {
    TypePrimitive {
       t.type.str()
    }
    TypeStruct {
      "struct ${t.name}"
    }
    TypeEnum{ 
      "enum ${t.name} (${t.as})"
    } 
    TypeFunc {
      mut s := "("
      assert(t.arg_names.len == 0 || t.arg_types.len == t.arg_names.len)
			for i := 0; i < t.arg_types.len; i++ {
        arg_t := t.arg_types[i]
        arg_n := t.arg_names[i] or {""}
				s += arg_n + ": "  + arg_t.str()
				if arg_t != t.arg_types[t.arg_types.len-1] {
					s += ", "
				}
			}

      if t.variadic_type != none {
        s += ", ...${t.variadic_type}"
      }

      if t.arg_types.len == 0 {
        s += "void"
      }
			s += ")"

      s += "["

      for capt_n in t.captured_names {
				s += capt_n
				if capt_n != t.captured_names[t.captured_names.len-1] {
					s += ", "
				}
			}

      s += "] -> ${t.ret}"

			s
    }
    TypePointer {
      "Ptr <${t.inner.str()}>"
    }
    TypeArray {
      "Array <${t.inner.str()}>"
    }
    TypeUnresolved {
      "unresolved ${t.name}"
    }
  }
  return type_str
}

fn (t Type) unqual() Type {
  return match t {
    TypePrimitive {TypePrimitive{qualifs: [], type: t.type}}
    TypeFunc {TypeFunc {qualifs: [], arg_types: t.arg_types, arg_names: t.arg_names, ret: t.ret}}
    TypePointer {TypePointer{qualifs: [], inner: t.inner}}
    TypeArray {TypeArray{qualifs: [], inner: t.inner}}
    TypeStruct {TypeStruct{qualifs: [], name: t.name}}
    TypeEnum {TypeEnum{qualifs: [], name: t.name, as: t.as}}
    TypeUnresolved{TypeUnresolved{qualifs: [], name: t.name}}
  }
}

fn are_types_equal(a Type, b Type) bool {
  ua := a.unqual()
  ub := b.unqual()
  return match ua {
    TypePrimitive{
      ub is TypePrimitive && ub.type == ua.type
    }
    TypeFunc {
      if ub !is TypeFunc {return false}
      if ua.arg_types.len != ub.arg_types.len {return false}
      if !are_types_equal(ua.ret, ub.ret) {return false}
      for i := 0; i < ua.arg_types.len; i++ {
        ta := ua.arg_types[i]
        tb := ub.arg_types[i]
        if !are_types_equal(ta, tb) {return false}
      }
      true
    }
    TypePointer {
      ub is TypePointer && are_types_equal(ua.inner, ub.inner)
    }
    TypeArray {
      ub is TypeArray && are_types_equal(ua.inner, ub.inner)
    }
    TypeStruct {
      ub is TypeStruct && ua.name == ub.name
    }
    TypeEnum {
      ub is TypeEnum && ua.name == ub.name
    }
    TypeUnresolved {
      false // unresolved type cannot be equal
    }
  }
}

fn join_types(a Type, b Type) ?Type {
  // TODO: cannot join non-const to const ?
  if are_types_equal(a, b) { return a.unqual() }

  ua := a.unqual()
  ub := b.unqual()  

  non_joinable := [BuiltinType.string, .void, .bool]
  if ua is TypePrimitive && ub is TypePrimitive {
    if ua.type == .any {return ub}
    if ub.type == .any {return ua}
    if non_joinable.contains(ua.type) || non_joinable.contains(ub.type) {
      return none
    }
    if ua.type.is_int() && ub.type.is_int() {
      if ua.type.is_unsigned() != ub.type.is_unsigned() {
        // TODO: handle signedness
      }
      if ua.type.size() >= ub.type.size() {
        return ua
      } else {
        return ub
      }
    } else if ua.type.is_float() && ua.type.is_float() {
      if ua.type.size() >= ub.type.size() {
        return ua
      } else {
        return ub
      }
    }
    // TODO: handle other types in the future
  }

  return none
}

fn cast_types(from Type, to Type) ?Type {
  if are_types_equal(from, to) { return from.unqual() }

  uf := from.unqual()
  ut := to.unqual()

  if uf is TypePointer && ut is TypePointer {
    return ut
  }

  if uf is TypePrimitive && ut is TypePrimitive {
    return none // TODO: handle
  }

  if uf is TypeEnum && ut == uf.as {
    return ut
  }
  
  if ut is TypeEnum && uf == ut.as {
    return uf
  }

  return none
}
