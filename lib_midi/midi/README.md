
# midi-parser

This repository contains a simple midi parser
which is [free software](LICENSE.md).
It should be able to parse most `.midi` files out there.
Since the parser returns a stream of events (see [the
midi dump example](example/midi-dump.c)), it works without
any runtime allocation.

The parser has no dependencies, and supports most platforms
due to its simple code and no use of file I/O.


## Use in your project

You can build midi-parser via `cmake . && make`.

Alternatively, to build midi-parser as part of your program,
add `src/midi-parser.c` to your project's
object files, and the `include/` folder to your include path.
(For Visual Studio, you'll find the required fields in your
project settings.)

Example using gcc, assuming this repository is at `path-to-midi-parser`:

```
$ gcc -o myprogram my_own_code.c path-to-midi-parser/src/midi-parser.c -Ipath-to-midi-parser/include
```


## Demo

Running `cmake . && make` will also build the `example/mini-dump.c` demo
as `midi-dump` executable.

You can then use `./midi-dump mymidifile.mid` on any midi file to test.

