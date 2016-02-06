# gpio

This package provides diverse mechanisms for writing GPIO programs in
Haskell. It includes an embedded DSL for writing platform-independent
programs, along with low-level monads and IO functions which provide
direct support for each supported platform's native GPIO API.

Currently only the Linux `sysfs` GPIO filesystem is supported, but
support for other Unix GPIO platforms is planned.

See the `examples` directory for examples of how to use the various
included monads.
