
Generics in iris work with two keywords:
`generic` and `constraint`

## generic

The first, `generic`, is used before a function or struct declaration
to express the names of the generic types that will be used. i.e.

```
generic K, V
struct Pair {
    key: K;
    value: V;
}
```

which could then be used like this: 

```
main: () -> i32 {
    my_pair: Pair<i32, string> = Pair<i32, string>(1, "Hello, ");
    another_pair: Pair<i32, string> = Pair<i32, string>(2, "World!");
    ret 0;
}
```

It is also possible to use `generic` for function declarations, going
on with the `Pair` example:

```
generic K, V
make_pair: (key: K, value: V) -> Pair<K, V> {
    return Pair<K, V>(key, value);
}
```

## constraints

`constraint`s are a way to express what types a generic can assume.
For example, an `add` function should only be callable with `Numeric`
types. The standard library `generics.iris` file already defines some
constraints:

```
constraint Numeric = [i8, i16, i32, u8, u16, u32, f32, f64];
constraint Integer = [i8, i16, i32, u8, u16, u32];
constraint Float = [f32, f64];
```

these can be used with the following syntax:

```
generic K: Numeric, V
struct Pair {
    key: K;
    value: V;
}
```

where `K` can only be one of the `Numeric` types.
