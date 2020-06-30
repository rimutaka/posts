# Cargo [features] explained with examples
#### If you feel confused about all the intricacies of Cargo.toml *[features]* section you are not alone ([1](https://github.com/Geal/nom/issues/544),[2](https://github.com/chyh1990/yaml-rust/issues/44),[3](https://github.com/rust-lang/cargo/issues/4328)).

*First of all, I assume that you have already read the docs at https://doc.rust-lang.org/cargo/reference/features.html to get some foundation of what features are before going through my examples. I did, but they left me confused until days later when I had to go much deeper into the topic to make some crates work together. What I think was missing for me in the docs was more examples with explanations how they work. This post was written to fill that gap.*

## How to find all features of a package

Crate docs can be very incomplete. Even if features are mentioned it's not always clear what they are for and how to use them. There is an easy way of finding out what features available and what may be behind them - check the *Cargo.toml* file of that package.

Consider this description of *features*:

![featrues-docs-example.png](featrues-docs-example.png)

If you check [the source](https://github.com/mockersf/serde_dynamodb/blob/0.5.0/serde_dynamodb/Cargo.toml) you'll notice that it fails to mention `rustls` feature altogether.

```
[dependencies]
rusoto_dynamodb = { version = "0.43.0", default-features = false, optional = true }

[features]
default = ["rusoto_dynamodb", "rusoto_dynamodb/default"]
rustls = ["rusoto_dynamodb", "rusoto_dynamodb/rustls"]
```
So there are actually 2 features: 
* `default`, which is a special Cargo keyword for when you do not specify any features as in `serde_dynamodb = "0.5"`
* `rustls`, which is only activated if specified as in `serde_dynamodb = { version="0.5", features=["rustls"]}`

So if we specify nothing (as in `serde_dynamodb = "0.5"`), the compiler will transform
```
rusoto_dynamodb = { version = "0.43.0", default-features = false, optional = true }
into
rusoto_dynamodb = { version = "0.43.0", default-features = true }
```

If we specify `serde_dynamodb = { version="0.5", features=["rustls"]}` the compiler will transform 
```
rusoto_dynamodb = { version = "0.43.0", default-features = false, optional = true }
into
rusoto_dynamodb = { version = "0.43.0", default-features = false, features=["rustls"] }
```

* `"rusoto_dynamodb/default"` means set `default-features = true` for dependency `rusoto_dynamodb`
* `"rusoto_dynamodb/rustls"` means apply feature `rustls` to dependency `rusoto_dynamodb`

![features-example-1](features-example-1.png)

## default_features = false

This attribute disables any defaults provided by a package.

For example, `some_core` package uses `openssl` by default with `rustls` implementation as an optional feature. *OpenSSL* and *RustLS* are mutually exclusive, so to enable *RustLS* we have to disable the defaults.
```
some_core = { version = "0.44", default_features = false, features=["rustls"] }
```

The authors of *some_core* could use [conditional compilation](https://doc.rust-lang.org/reference/conditional-compilation.html) to save us from having to remember to use `default_features = false`:
```
#[cfg(feature="rustls")]
fn use_rustls_here {
  ...
}

#[cfg(not(feature="rustls"))]
fn use_openssl_here {
  ...
}
```

## optional = true

This attribute tells the compiler to include the dependency only if it is explicitly mentioned in one of the activated features. For example, *log* is always included, while *dynomite-derive* will only be included if my Cargo.toml has `dynomite = {version = "*", features = ["derive"]}`:
```
[dependencies]
log = "0.4"
dynomite-derive = { version = "*", path = "../dynomite-derive", optional = true }

[features]
derive = ["dynomite-derive"]
```

## Features are like labels for dependencies

First, features have to be declared in Cargo.toml of the package they are used in, that is, in your dependency. Then they are "referenced" in your Cargo.toml file to tell the dependency what you want from it.

Here is an abridged example of feature declarations from [Dynomite, a DynamoDB library](https://github.com/softprops/dynomite/blob/master/dynomite/Cargo.toml).

```
[dependencies]
log = "0.4"
dynomite-derive = { version = "0.8.2", path = "../dynomite-derive", optional = true }
rusoto_core_default = { package = "rusoto_core", version = "0.44", optional = true }
rusoto_core_rustls = { package = "rusoto_core", version = "0.44", default_features = false, features=["rustls"], optional = true }
rusoto_dynamodb_default = { package = "rusoto_dynamodb", version = "0.44", optional = true }
rusoto_dynamodb_rustls = { package = "rusoto_dynamodb", version = "0.44", default_features = false, features=["rustls"], optional = true }
uuid = { version = "0.8", features = ["v4"], optional = true }
chrono = { version = "0.4", optional = true }

[features]
default = ["uuid", "chrono", "rusoto_core_default", "rusoto_dynamodb_default"]
rustls = ["uuid", "chrono", "derive", "rusoto_core_rustls", "rusoto_dynamodb_rustls"]
derive = ["dynomite-derive"]
magic = []
```

That gives us a default and 2 optional features, `rustls` and `derive`. I can use these features to tell Dynomite what I need from it in my project.

- *default* - activates if no feature is specified or even if another feature is specified without `default_features = false`. In the example above it lists the name of dependencies that should be included if this feature is activated.
- *rustls* - activates if my Cargo.toml has something like `dynomite = {version = "0.8.2", default-features = false, features = ["rustls"]}`. Its declaration includes a list of dependencies and another feature - `derive`. So if I specify  `features = ["rustls"]` it is the same as `features = ["rustls", "derive"]`
- *derive* - this feature references a single dependency `dynomite-derive`, plus all the unconditional ones.
- *magic* - this feature does not reference anything. It can only be used for conditional compilation with `#[cfg(feature="magic")]`



My Cargo.toml: `dynomite = {version = "0.8.2"}` tells the compiler to use all unconditional dependencies (*log*) and those listed in *default* feature declaration:
```
log = "0.4"
rusoto_core_default = { package = "rusoto_core", version = "0.44", optional = true }
rusoto_dynamodb_default = { package = "rusoto_dynamodb", version = "0.44", optional = true }
uuid = { version = "0.8", features = ["v4"], optional = true }
chrono = { version = "0.4", optional = true }
```

My Cargo.toml: `dynomite = {version = "0.8.2", default-features = false, features = ["derive"]}` tells the compiler I only want *derive* and none of the defaults. If I didn't specify `default-features = false` all the default features would still be included. The compiler gets:
```
log = "0.4"
dynomite-derive = { version = "0.8.2", path = "../dynomite-derive", optional = true }
```

My Cargo.toml: `dynomite = {version = "0.8.2", default-features = false, features = ["rustls"]}` tells the compiler I want everything from *rustls* feature, which also includes *derive* feature. The compiler gets:
```
log = "0.4"
dynomite-derive = { version = "0.8.2", path = "../dynomite-derive", optional = true }
rusoto_core_rustls = { package = "rusoto_core", version = "0.44", default_features = false, features=["rustls"], optional = true }
rusoto_dynamodb_rustls = { package = "rusoto_dynamodb", version = "0.44", default_features = false, features=["rustls"], optional = true }
uuid = { version = "0.8", features = ["v4"], optional = true }
chrono = { version = "0.4", optional = true }
```

![explained with colour](feature-colour-mapping.png)

## Dependency of a dependency - features are additive

Cargo takes the union of all features enabled for a crate throughout the dependency graph. If multiple crates enable *mutually exclusive* features of another crate, then all those features will be enabled at build time. The result of that would depend on the implementation of the crate and may result in a compiler error if mutually exclusive crates or features are enabled.

An example of this type of dependency would be *Crate X* that depends on *Crates A* and *Crate B*, while both *A* and *B* depend on *Crate awesome*.
```
       Crate X
      /        \
Crate A        Crate B
      \        /
    Crate awesome
```

In the following example both `go-faster` and `go-slower` features will be enabled in crate `awesome`. It will be up to that crate to decide which of the two features prevails.

- Crate `awesome`:
```
[features]
"go-faster" = []
"go-slower" = []
```
- Crate A: `awesome = { version = "1.0", features = ["go-faster"] }`
- Crate B: `awesome = { version = "1.0", features = ["go-slower"] }`

Consider a more complicated example with three possible configurations for `some_core` dependency.

- Crate `awesome `:
```
[dependencies]
some_core_default = { package = "some_core", version = "0.1" }
some_core_openssl = { package = "some_core", version = "0.1", default_features = false, features=["openssl"], optional = true }
some_core_rustls = { package = "some_core", version = "0.1", default_features = false, features=["rustls"], optional = true }

[features]
default = ["some_core_default"]
openssl = ["some_core_openssl"]
rustls = ["some_core_rustls"]
```

The following combination will make crate `awesome ` depend on `some_core_rustls` because the resulting tree includes `default-features = false,  features = ["rustls"]` which overrides the default:
- Crate A:  `awesome = { version = "1.0" }`
- Crate B: `awesome = { version = "1.0", default-features = false,  features = ["rustls"]` }`

Removing `default-features = false` results in a compilation error because the same `some_core` dependency is included twice. Once via `default` and once via `rustls`:
- Crate A:  `awesome = { version = "1.0" }`
- Crate B: `awesome = { version = "1.0", features = ["rustls"] }`

This combination will also result in the same compilation error because package `some_core` is included twice via `some_core_openssl` and `some_core_rustls`:
- Crate A:  `awesome = { version = "1.0", default-features = false, features = ["openssl"] }`
- Crate B: `awesome = { version = "1.0", default-features = false, features = ["rustls"] }`

