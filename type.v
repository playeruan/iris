
module main

// -- TypeQualifier

enum TypeQualifier as u8 {
  const
  pure
}
const all_type_qualifiers = [TypeQualifier.const, .pure]

enum QualifierJoinRule as u8 {
  union
  intersect
}

enum QualifierCompatDirection as u8 {
  value_subsumes_target
  target_subsumes_value
}

fn (qs []TypeQualifier) str() string {
  mut s := ""
  for q in qs {
    s += q.str() + " "
  }
	return s
}

fn (q TypeQualifier) join_rule() QualifierJoinRule {
  return match q {
    .const, .pure {.union}
  }
}
fn (q TypeQualifier) compat_direction() QualifierCompatDirection {
  return match q {
    .const {.value_subsumes_target}
    .pure {.target_subsumes_value}
  }
}

fn (q TypeQualifier) valid_for_type(t Type) bool {
  valid := match t {
    TypePrimitive, TypePointer, TypeArray, TypeStruct, TypeEnum, TypeType {[TypeQualifier.const]}
    TypeFunc {[.pure]}
    else {[]}
  }
  return valid.contains(q)
}

// -- Type

enum BuiltinType as u8 {
  void
  i8
  i16
  i32
  u8
  u16
  u32
  f32
  f64
  bool
  type
  any
}

const all_builtins := [
  BuiltinType.void, .i8, .i16,
  .i32, .u8, .u16, .u32, .f32,
  .f64, .bool, .type, .any
]

const any_type := TypePrimitive {
  type: .any
}

fn is_builtin_type(s string) bool {
  return [
    "void", "i8", "i16", "i32",
    "u8", "u16", "u32", "f32", 
    "f64", "bool", "type",
    "any"
  ].contains(s)
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
    .t_any    {.any}
    else      {
      panic("invalid TokKind ${t} to convert to BuiltinType")
    }
  }
}

fn BuiltinType.from_string(s string) BuiltinType {
  return match s {
    "i32"     {BuiltinType.i32}
    "u32"     {.u32}
    "i16"     {.i16}
    "u16"     {.u16}
    "i8"      {.i8}
    "u8"      {.u8}
    "f32"     {.f32}
    "f64"     {.f64}
    "bool"    {.bool}
    "void"    {.void}
    "type"    {.type}
    "any"     {.any}
    else      {
      panic("invalid string ${s} to convert to BuiltinType")
    }
  }
}

fn (t BuiltinType) size() i32 {
  return match t {
    .void, .type, .any {0} // TODO: .string, .type, .any sizes
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

fn (t Type) is_complete_type() bool {
  if t is TypePrimitive && t.type == .void {return false}
  return true
}

fn (t Type) is_op_valid(op string) bool {
  valid := match t {
    TypePointer {["+", "-", "+=", "-=", "++", "--", "==", "!="]}
    TypeType {["==", "!="]}
    TypeEnum {["+", "-", "+=", "-=", "++", "--", "<", ">", "<=", ">=", "!=", "=="]}
    TypePrimitive {
      match t.type {
        .i8, .u8, .i16, .u16, .i32, .u32, .f32, .f64 {
          ["+", "-", "*", "/", "%", "+=", "-=", "*=", "/=", "%=", 
          "++", "--", "<", ">", "<=", ">=", "!=", "==", "||", "&&", "~"]
        }
        .bool {["==", "!=", "&&", "||", "!"]}
        .void, .any, .type {[]}
      }
    }
    TypeArray, TypeFunc, TypeStruct, TypeUnresolved, TypeGeneric {[]string([])}
  }
  return valid.contains(op)
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
  TypeUnresolved | TypeGeneric | TypeType

struct TypePrimitive {
  qualifs []TypeQualifier
  type BuiltinType 
}

struct TypeType {
  qualifs []TypeQualifier
  name string
}

struct TypeFunc {
  qualifs []TypeQualifier
  arg_types []Type
  arg_names []string
  variadic_type ?Type  // none if function is not variadic
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
  generic_args []Type
  generic_base ?string // none for non-generic structs
}

struct TypeEnum {
  qualifs []TypeQualifier
  name string
  as Type
}

struct TypeGeneric {
  qualifs []TypeQualifier
  name string
}

// for things that clearly should be 
// types but we're unsure of which
// kind
struct TypeUnresolved {
  qualifs []TypeQualifier
  name string
  generic_args []Type
}

fn (t Type) str() string {
  mut type_str := t.qualifs.str()
  type_str += match t {
    TypePrimitive {
       t.type.str()
    }
    TypeType {
      "comp-time type"
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
				if i != t.arg_types.len-1 {
					s += ", "
				}
			}

      if t.variadic_type != none {
        s += ", ...${t.variadic_type}"
      }

      if t.arg_types.len == 0 {
        s += "void"
      }

      s += ") -> ${t.ret}"

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
    TypeGeneric {
      "generic ${t.name}"
    }
  }
  return type_str
}

fn (t Type) compact_str() string {
  mut type_str := t.qualifs.str()
  type_str += match t {
    TypePrimitive {
       t.type.str()
    }
    TypeType {
      "t_${t.name.to_lower()}"
    }
    TypeStruct {
      "s_${t.name.to_lower()}"
    }
    TypeEnum{ 
      "e_${t.name.to_lower()}"
    } 
    TypeFunc {
      mut s := "fn_"
      assert(t.arg_names.len == 0 || t.arg_types.len == t.arg_names.len)
			for i := 0; i < t.arg_types.len; i++ {
        arg_t := t.arg_types[i]
				s += arg_t.compact_str()+"_"
			}
      s += "_${t.ret}"
			s
    }
    TypePointer {
      "p_${t.inner.compact_str()}"
    }
    TypeArray {
      "a_${t.inner.compact_str()}"
    }
    TypeUnresolved {
      "u_${t.name.to_lower()}"
    }
    TypeGeneric {
      "g_${t.name.to_lower()}"
    }
  }
  return type_str
}

fn (t Type) typename_str() string {
  mut type_str := t.qualifs.str()
  type_str += match t {
    TypePrimitive {t.type.str()}
    TypeType {"type"}
    TypeStruct {t.name}
    TypeEnum {t.name}
    TypeFunc {
      mut s := "("
      assert(t.arg_names.len == 0 || t.arg_types.len == t.arg_names.len)
			for i := 0; i < t.arg_types.len; i++ {
        arg_t := t.arg_types[i]
				s += arg_t.typename_str()
				if i != t.arg_types.len-1 {
					s += ", "
				}
			}

      if t.variadic_type != none {
        s += ", ...${t.variadic_type}"
      }

      if t.arg_types.len == 0 {
        s += "void"
      }

      s += ") -> ${t.ret}"

			s
    }
    TypePointer {
      "^${t.inner.typename_str()}"
    }
    TypeArray {
      "[]${t.inner.typename_str()}"
    }
    TypeUnresolved {
      "?${t.name}"
    }
    TypeGeneric {t.name}
  }
  return type_str
}

fn (t Type) with_qualifs(qs []TypeQualifier) Type {
  mut no_dup := []TypeQualifier{}
  for q in qs {
    if !no_dup.contains(q) {no_dup << q}
  }
  return match t {
    TypePrimitive {TypePrimitive{qualifs: no_dup, type: t.type}}
    TypeFunc {TypeFunc {qualifs: no_dup, arg_types: t.arg_types, arg_names: t.arg_names, ret: t.ret}}
    TypePointer {TypePointer{qualifs: no_dup, inner: t.inner}}
    TypeArray {TypeArray{qualifs: no_dup, inner: t.inner}}
    TypeStruct {TypeStruct{qualifs: no_dup, name: t.name, generic_args: t.generic_args, generic_base: t.generic_base}}
    TypeEnum {TypeEnum{qualifs: no_dup, name: t.name, as: t.as}}
    TypeUnresolved{TypeUnresolved{qualifs: no_dup, name: t.name}}
    TypeGeneric {TypeGeneric{qualifs: no_dup, name: t.name}}
    TypeType {TypeType{qualifs: no_dup, name: t.name}}
  }
}

fn (t Type) unqual() Type {
  return t.with_qualifs([])
}

fn (t TypePointer) pointer_depth() i32 {
  mut t_ := Type(t)
  mut i := 0;
  for t_ is TypePointer {
    t_ = t_.inner
    i++;
  }
  return i;
}

fn (t TypePointer) traverse_pointer(layers i32) Type {
  mut t_ := Type(t)
  mut i := 1;
  for t_ is TypePointer && i < layers {
    t_ = (t_ as TypePointer).inner
    i++;
  }
  if i < layers {
    panic("traversed pointer by too many layers!")
  }
  return t_;
}

fn (t Type) is_generic() bool {
  return match t {
    TypeGeneric {true}
    TypePointer {t.inner.is_generic()}
    TypeArray {t.inner.is_generic()}
    else {false}
  }
}

fn (t Type) get_generic_name() string {
  return match t {
    TypeGeneric {t.name}
    TypePointer {t.inner.get_generic_name()}
    TypeArray {t.inner.get_generic_name()}
    else {panic("invalid tried to get generic name of type ${t}")}
  }
}

fn mangle_monomorph_name(base string, subst map[string]Type) string {
  mut keys := subst.keys()
  keys.sort()
  mut name := base
  for k in keys {
    sub := subst[k] or {panic("unreachable")}
    name += "_${sub.unqual().compact_str()}"
  }
  return name
}

fn infer_into_subst(type_params []string, param_t Type, arg_t Type, mut subst map[string]Type) ! {
  match param_t {
    TypeGeneric {
      if param_t.name in type_params {
        if param_t.name in subst {
          sub := subst[param_t.name] or { panic("unreachable") }
          j := join_types(sub, arg_t.unqual()) or {
            return error("contradictory inference for ${param_t.name}: got ${arg_t} and ${sub}")
          }
          subst[param_t.name] = j
        } else {
          subst[param_t.name] = arg_t.unqual()
        }
      }
    }
    TypePointer {
      if arg_t is TypePointer {
        infer_into_subst(type_params, param_t.inner, arg_t.inner, mut subst)!
      } else {
        return error("expected more (${param_t.pointer_depth()}) nested pointer type, got ${arg_t}")
      }
    }
    TypeArray {
      if arg_t is TypeArray {
        infer_into_subst(type_params, param_t.inner, arg_t.inner, mut subst)!
      } else {
        return error("expected array type, got ${arg_t}")
      }
    }
    TypeStruct {
      if arg_t is TypeStruct && param_t.generic_args.len > 0 {
        for i, ga in param_t.generic_args {
          if i < arg_t.generic_args.len {
            infer_into_subst(type_params, ga, arg_t.generic_args[i], mut subst)!
          }
        }
      }
    }
    else {}
  }
}

fn infer_type_args(type_params []string, param_types []Type, arg_types []Type) !map[string]Type {
  mut subst := map[string]Type{}
  for i, param_t in param_types {
    infer_into_subst(type_params, param_t, arg_types[i], mut subst)!
  }
  for tp in type_params {
    if tp !in subst {
      return error("could not infer type argument for ${tp}")
    }
  }
  return subst
}

fn substitute_type(t Type, subst map[string]Type) Type {
  return match t {
    TypeGeneric {
      subst[t.name] or { t }
    }
    TypePointer {
      TypePointer{qualifs: t.qualifs, inner: substitute_type(t.inner, subst)}
    }
    TypeArray {
      TypeArray{qualifs: t.qualifs, inner: substitute_type(t.inner, subst)}
    }
    TypeStruct {
      if t.generic_args.len == 0 { return t }
      TypeStruct{
        qualifs: t.qualifs
        name: t.name
        generic_args: t.generic_args.map(substitute_type(it, subst))
        generic_base: t.generic_base
      }
    }
    TypeFunc {
      TypeFunc{
        qualifs: t.qualifs
        arg_types: t.arg_types.map(substitute_type(it, subst))
        arg_names: t.arg_names
        variadic_type: if vt := t.variadic_type { substitute_type(vt, subst) } else { none }
        ret: substitute_type(t.ret, subst)
      }
    }
    else { t }
  }
}

fn (t Type) collapse_generic(gen_name string, typ Type) Type {
  return substitute_type(t, {gen_name: typ})
}

fn join_qualifs(a []TypeQualifier, b []TypeQualifier) []TypeQualifier {
  mut result := []TypeQualifier{}
  for q in all_type_qualifiers {
    a_has := a.contains(q)
    b_has := b.contains(q)
    match q.join_rule() {
      .union        { if a_has || b_has { result << q } }
      .intersect    { if a_has && b_has { result << q } }
    }
  }
  return result
}

fn is_qualifs_compatible(from []TypeQualifier, to []TypeQualifier) bool {
  for q in all_type_qualifiers {
    from_has := from.contains(q)
    to_has   := to.contains(q)
    match q.compat_direction() {
      .value_subsumes_target  { if from_has && !to_has { return false } }
      .target_subsumes_value  { if to_has && !from_has { return false } }
    }
  }
  return true
}

fn (t Type) is_any() bool {
  return t is TypePrimitive && are_types_equal(t, any_type) 
}

fn is_type_compatible(from Type, to Type) bool {
  match from {
    TypePointer { 
      if to is TypePointer && !is_qualifs_compatible(from.inner.qualifs, to.inner.qualifs) {return false}
      return to.is_any() || (to is TypePointer && is_type_compatible(from.inner, to.inner)) 
    }
    TypeArray   { 
      return to.is_any() 
      || ((to is TypeArray && is_type_compatible(from.inner, to.inner)) || 
          (to is TypePointer && is_type_compatible(from.inner, to.inner)))
    }
    TypeFunc    {
      if to !is TypeFunc { return false }
      if !is_type_compatible(from.ret, to.ret) { return false }
      for i, fa in from.arg_types {
        if !is_type_compatible(fa, to.arg_types[i]) { return false }
      }
      return true
    }
    else {
      // only check non-const qualifiers
      if !is_qualifs_compatible(from.qualifs.filter(it != .const),
                                 to.qualifs.filter(it != .const)) { return false }
      return true
    }
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
    TypeGeneric {
      false // doesn't need to be aware
    }
    TypeType {
      ub is TypeType
    }
  }
}

fn join_unqual(a Type, b Type) ?Type {


  if are_types_equal(a, b) { return a.unqual() }


  ua := a.unqual()
  ub := b.unqual()  

  if ua is TypePrimitive && ua.type == .any {return ub}
  if ub is TypePrimitive && ub.type == .any {return ua}
  

  non_joinable := [BuiltinType.void, .bool]
  if ua is TypePrimitive && ub is TypePrimitive {

    if non_joinable.contains(ua.type) || non_joinable.contains(ub.type) {
      return none
    }
    if ua.type.is_int() && ub.type.is_int() {
      if ua.type.is_unsigned() != ub.type.is_unsigned() {
        larger_size := if ua.type.size() >= ub.type.size() { ua.type.size() } else { ub.type.size() }
        // widen to signed of the larger size
        return TypePrimitive{type: match larger_size {
          1 { BuiltinType.i8 }
          2 { BuiltinType.i16 }
          else { BuiltinType.i32 }
        }}
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

  if ua is TypeArray && ub is TypePointer {
    if are_types_equal(ua.inner, ub.inner) {
      return ub
    } else {
      return none
    }
  }
  
  if ub is TypeArray && ua is TypePointer {
    if are_types_equal(ua.inner, ub.inner) {
      return ua
    } else {
      return none
    }
  }

  if ua is TypeType && ub is TypePrimitive && ub.type == .type { return ub }
  if ub is TypeType && ua is TypePrimitive && ua.type == .type { return ua }
  
  if ua is TypeEnum {
    j := join_types(ua.as, ub)
    if j != none {
      if are_types_equal(ua.as, j) {return ub}
    }
    return none
  }
  
  if ub is TypeEnum {
    j := join_types(ub.as, ua)
    if j != none {
      if are_types_equal(ub.as, j) {return ua}
    }
    return none
  }

  if ua is TypeArray && ub is TypeArray {
    j := join_unqual(ua.inner, ub.inner) or {return none}
    return TypeArray{inner: j}
  }

  if ua is TypePointer && ub is TypePointer {
    if are_types_equal(ua.inner, TypePrimitive{type: .void}) { return ub }
    if are_types_equal(ub.inner, TypePrimitive{type: .void}) { return ua }
    j := join_unqual(ua.inner, ub.inner) or { return none }
    return TypePointer{ qualifs: ua.qualifs, inner: j }
  }

  if ua is TypeStruct && ub is TypeStruct {
    if ua.name == ub.name { return ua }
    base_a := ua.generic_base or { return none }
    base_b := ub.generic_base or { return none }
    if base_a != base_b { return none }
    if ua.generic_args.len != ub.generic_args.len { return none }
    mut joined_args := []Type{}
    for i, ga in ua.generic_args {
        joined_args << join_unqual(ga, ub.generic_args[i]) or { return none }
    }
    mut subst := map[string]Type{}
    for i, ja in joined_args { subst["_${i}"] = ja }
    return TypeStruct{name: mangle_monomorph_name(base_a, subst), generic_args: joined_args, generic_base: base_a}
}

  return none
}

fn join_types(a Type, b Type) ?Type {
  result := join_unqual(a.unqual(), b.unqual()) or { return none }
  return result.with_qualifs(join_qualifs(a.qualifs, b.qualifs))
}

fn cast_types(from Type, to Type) ?Type {
  joined := join_types(from, to)
  if joined != none {
    if joined == to {
      return to 
    }
  }



  uf := from.unqual()
  ut := to.unqual()

  if uf is TypePointer && ut is TypePointer {
    return ut
  }

  if uf is TypePrimitive && ut is TypePrimitive {
    if uf.type.is_int() && ut.type.is_float() {return ut}
    if uf.type.is_int() && ut.type.is_int() {
      if uf.type.is_unsigned() != ut.type.is_unsigned() {
        // TODO: handle signedness
      }
      if uf.type.size() < ut.type.size() {
        return ut
      } else {
        none
      }
    } else if uf.type.is_float() && uf.type.is_float() {
      if uf.type.size() < ut.type.size() {
        return ut
      } else {
        none
      }
    }
    return none 
  }

  if uf is TypeEnum {
    j := join_types(uf.as, ut)
    if j != none {
      if are_types_equal(uf.as, j) {return ut}
    }
    return none
  }

  if ut is TypeEnum {
    j := join_types(ut.as, uf)
    if j != none {
      if are_types_equal(ut.as, j) {return ut}
    }
    return none
  }


  return none
}
