module main

// -- Precedence

enum Precedence as u8 {
  literal // least
  disjunction
  conjunction
  comparison
  addition
  multiplication
  bitshift
  prefix
  postfix // most
}

fn (s Span) str() string {
  return "[${s.file}] ${s.row}:${s.col:}"
}

// -- TokKind

enum TokKind as u8 {

  eof

  identifier

  t_any
  t_i32
  t_u32
  t_i16
  t_u16
  t_i8
  t_u8
  t_f32
  t_f64
  t_void
  t_bool
  t_type

  l_int
  l_float
  l_true
  l_false
  l_string

  o_eq
  o_lt
  o_gt
  o_eqeq
  o_neq
  o_lteq
  o_gteq
  o_plus
  o_minus
  o_star
  o_slash
  o_pluseq
  o_minuseq
  o_stareq
  o_slasheq
  o_and
  o_andand
  o_or
  o_oror
  o_exclam
  o_tilde
  o_caret
  o_plusplus
  o_minusminus
  o_hash
  o_ellipsis

  dot
  dotdot
  comma
  colon
  semicolon
  arrow
  at

  lparen
  rparen
  lsquare
  rsquare
  lbrace
  rbrace

  // type qualifs
  tq_const
  tq_pure

  // decl qualifs
  dq_extern

  ret
  if 
  else
  elif
  for
  while
  break
  continue
  struct
  enum
  sizeof

  generic
  constraint

  nullptr

  include

  // directives
  d_extname
  d_link
  d_cinclude

  invalid
}

fn (k TokKind) precedence() Precedence {
  return match k {
    .o_oror {.disjunction}
    .o_andand {.conjunction}
    .o_eqeq, .o_lt, .o_gt, .o_lteq, .o_gteq, .o_neq {.comparison}
    .o_plus, .o_minus {.addition}
    .o_star, .o_slash, .o_and, .o_or {.multiplication}
    // {bitshift}
    .o_exclam, .o_tilde, .o_plusplus, .o_minusminus {.prefix}
    .dot, .lsquare, .lparen, .at, .dotdot {.postfix}
    else {.literal}
  }
}

fn (k TokKind) is_primitive_type() bool {
  return k.str().contains("t_")
}

fn (k TokKind) is_type_qualifier() bool {
  return k.str().contains("tq_")
}

fn (k TokKind) is_decl_qualifier() bool {
  return k.str().contains("dq_")
}

fn (k TokKind) get_type_qualifier() TypeQualifier {
  return match k {
    .tq_const {.const}
    .tq_pure  {.pure}
    else {panic("${k} is not a valid type qualifier")}
  }
}

fn (k TokKind) get_decl_qualifier() DeclQualifier {
  return match k {
    .dq_extern {.extern}
    else {panic("${k} is not a valid decl qualifier")}
  }
}

fn Token.from_str(s string) ?TokKind {
  return match s {
    "any"   {.t_any}
    "i32"   {.t_i32}
    "u32"   {.t_u32}
    "i16"   {.t_i16}
    "u16"   {.t_u16}
    "i8"    {.t_i8}
    "u8"    {.t_u8}
    "f32"   {.t_f32}
    "f64"   {.t_f64}
    "void"  {.t_void}
    "bool"  {.t_bool}
    "type"  {.t_type}
    "true"  {.l_true}
    "false" {.l_false}
    "struct"{.struct}
    "enum"  {.enum}
    "include" {.include}
    "sizeof" {.sizeof}
    "nullptr" {.nullptr}
    "generic" {.generic}
    "constraint" {.constraint}

    "="     {.o_eq}
    "<"     {.o_lt}
    ">"     {.o_gt}
    "=="    {.o_eqeq}
    "!="    {.o_neq}
    "<="    {.o_lteq}
    ">="    {.o_gteq}
    "+"     {.o_plus}
    "-"     {.o_minus}
    "*"     {.o_star}
    "/"     {.o_slash}
    "+="    {.o_pluseq}
    "-="    {.o_minuseq}
    "*="    {.o_stareq}
    "/="    {.o_slasheq}
    "&"     {.o_and}
    "&&"    {.o_andand}
    "|"     {.o_or}
    "||"    {.o_oror}
    "!"     {.o_exclam}
    "~"     {.o_tilde}
    "^"     {.o_caret}
    "++"    {.o_plusplus}
    "--"    {.o_minusminus}
    "#"     {.o_hash}
    ".."    {.dotdot}
    "..."   {.o_ellipsis}

    "."     {.dot}
    ","     {.comma}
    ":"     {.colon}
    ";"     {.semicolon}
    "->"    {.arrow}
    "@"     {.at}

    "("     {.lparen}
    ")"     {.rparen}
    "["     {.lsquare}
    "]"     {.rsquare}
    "{"     {.lbrace}
    "}"     {.rbrace}

    "const" {.tq_const}
    "pure"  {.tq_pure}

    "extern" {.dq_extern}
    "nexter" {.dq_extern} // hi nexter

    "extname" {.d_extname}
    "link"    {.d_link}
    "cinclude"{.d_cinclude}

    "ret"   {.ret}
    "if"    {.if}
    "else"  {.else}
    "elif"  {.elif}
    "for"   {.for}
    "while" {.while}
    "break" {.break}
    "continue" {.continue}

    else {none}
  }
}

// -- Span

struct Span {
  mut:
  file string
  row u32
  col u32
}

// -- Token

union TokValue {
  i64 i64
  f64 f64
  string string
  bool bool
  void ?
}

struct Token {
  kind TokKind
  value TokValue 
  span Span
  text string 
}

fn (t Token) str() string {
	mut s := "${t.span:-20} ${t.kind.str():-10}"
	if t.text.len > 0 {
		s += " | ${t.text}"
	}
	return s
}

fn (ts []Token) str() string {
  mut s := ""
  for t in ts {
    s += t.str() + "\n"
  }
  return s
}
