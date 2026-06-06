
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
    .t_string {.string}
    else      {
      panic("invalid TokKind ${t} to convert to BuiltinType")
    }
  }
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

      if t.arg_names.len == 0 {
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
    if non_joinable.contains(ua.type) || non_joinable.contains(ub.type) {
      return none
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
