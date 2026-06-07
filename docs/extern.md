
The extern keyword has similar meaning in all its current use cases

### Functions

An `extern` function is declared with this syntax

```
extern foo: (x: i32) -> i32
```

It cannot have a function body and it will be compiled so to call
a function with the same name. if you want to override the external
name (sometimes it's necessary due to iris's imposed name formatting)
it's possible to use the `#extname` directive like this 

```
extern my_function: (x: i32) -> i32 #extname MyFunction
```

`extern` functions (and only those as of now) can have a variadic
number of arguments if declared with the following syntax 

```
extern my_variadic: (x: i32, ...i32)
```

The type after the ellipsis (`...`) may also be a special
`any` type, which is only allowed in this context and 
lets the variadic arguments be of any type. This feature
was added for compatibility with libc's `printf` function.

### Structs

An `extern struct` exists just for the purpose of interacting with
libraries written for C. An example might be the `Color` struct from
raylib: 

```
extern struct Color {
    r: u8;
    g: u8;
    b: u8;
    a: u8;
}
```

this won't get compiled to a separate struct when transpiling to C, but
will rather become an alias for the actual C `Color` struct, allowing it 
to be used in iris.
