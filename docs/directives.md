

directives are special keywords which don't get translated into any
intructions but tell the compiler some information, usually useful 
for compatibility with C 

## link

the `#link` directive simply tells the compiler to link with a specific
library when calling clang after having generated C code.

it's useful when creating a bindings file for a library, such as raylib in 
this example.

```
#link "raylib"
```

means clang will get called with the `-lraylib` flag later.

## extname

the `#extname` directive is again useful when creating bindings.
it's used to specify what the original name of an `extern` function
is, since sometimes it's necessary for it to be different due to
iris's name formatting rules.

The `#extname` directive follows the return type of the function:

```
extern get_screen_width: () -> i32 #extname GetScreenWidth
```

this is a real example from the `raylib.iris` bindings file. 
