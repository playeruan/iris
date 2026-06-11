
There are two string types in iris, one is a built-in, and one is implemented in `std/string.iris`.
"raw" strings, the built-in ones, are `[]i8` similarly to C's `char*` and they share many
of C strings properties, such as being null terminated.

`[]i8` can be assigned and implicitly casted to `^i8` just like any Array -> Pointer
cast, and the opposite operation isn't permitted. This is the reason why you will mostly
see functions accepting `^i8` or `const ^i8` for strings, and not arrays. Accepting a 
pointer is more lenient, and doesn't require passing a raw string literal.

`String`s on the other hand are defined in `std/string.iris` and are basically wrappers
if `DynamicArray<i8>`, some specific operations such as `str_create(^i8)` and `str_to_i8(String)`
are implemented for ease of use.
