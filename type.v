
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
  i32
  f32
  bool
  string
  type
}

fn BuiltinType.from_tok_kind(t TokKind) BuiltinType {
  return match t {
    .t_i32    {BuiltinType.i32}
    .t_f32    {.f32}
    .t_bool   {.bool}
    .t_void   {.void}
    .t_type   {.type}
    else      {
      panic("invalid TokKind ${t} to convert to BuiltinType")
    }
  }
}

type Type = 
  TypePrimitive | TypeFunc | TypePointer | 
  TypeArray | TypeStruct

struct TypePrimitive {
  qualifs []TypeQualifier
  type BuiltinType 
}

struct TypeFunc {
  qualifs []TypeQualifier
  arg_types []Type
  arg_names []string
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

fn (t Type) str() string {
  mut type_str := t.qualifs.str()
  type_str += match t {
    TypePrimitive {
       t.type.str()
    }
    TypeStruct {
      t.name
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
			s += ") -> ${t.ret}"
			s
    }
    TypePointer {
      "^${t.inner.str()}"
    }
    TypeArray {
      "[]${t.inner.str()}"
    }
  }
  return type_str
}
