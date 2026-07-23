# onoff

`onoff` extracts selected lines or sections from text files. Output can be
turned on and off by line numbers or regular expressions, and matching lines
can be printed with surrounding context.

## Requirements

- Perl 5
- The core Perl modules `Text::Abbrev` and `Data::Dumper`

## Installation

Make sure the script is executable, then put it somewhere on your `PATH`:

```sh
chmod +x onoff
cp onoff "$HOME/bin/onoff"
```

Alternatively, run it directly from this directory:

```sh
./onoff 10..20 file.txt
```

## Syntax

```text
onoff [options] [range] [file ...]
```

When no files are supplied, `onoff` reads standard input. Use `-` explicitly
when standard input must appear at a particular position among other files.

### Ranges

```text
N        print line N
N..      print from line N to the end
..M      print from the beginning through line M
N..M     print lines N through M
X..Y     print from a line matching X through a line matching Y
```

Range boundaries are included in the output.

### Options

```text
-start REGEXP    start printing at a matching line
-stop REGEXP     stop printing after a matching line
-regexp REGEXP   print individual matching lines
-lead N          include N lines before a trigger
-linger N        include N lines after a trigger
-context N       include N lines before and after a trigger
-number          prefix output with line numbers
-file FILE       add an input file explicitly
-help            show detailed option help
-usage           show a short usage summary
-debug           show argument parsing and processing details
```

The aliases `-on` and `-begin` mean `-start`; `-off` and `-end` mean
`-stop`; and `-find` and `-grep` mean `-regexp`. Unique single-hyphen
abbreviations are also accepted.

Regular expressions are Perl regular expressions supplied as plain arguments.
Do not surround them with `/` characters. Quote expressions containing spaces
or shell metacharacters.

## Examples

Print one line:

```sh
onoff 13 file.txt
```

Print an inclusive line-number range:

```sh
onoff 4..27 file.txt
```

Print from the first `BEGIN` line through the following `END` line:

```sh
onoff -start '^BEGIN$' -stop '^END$' file.txt
```

The compact range form expresses the same operation:

```sh
onoff 'BEGIN..END' file.txt
```

Print lines containing `error`, with two lines of context on each side:

```sh
onoff -regexp 'error' -context 2 logfile
```

Print numbered output from line 20 onward, stopping at `__END__`, and include
two additional lines:

```sh
onoff 20.. -stop '__END__' -linger 2 -number source.pl
```

Read from a pipeline:

```sh
some-command | onoff -start 'connected' -stop 'disconnected' -
```

Multiple files may be supplied. Each file is opened and processed in order:

```sh
onoff 1..10 first.txt second.txt
```

## Behavior

- Start and stop lines are printed inclusively.
- After a stop, scanning continues, so later start/stop sections may also be
  printed.
- A line matching both the start and stop condition is printed once and does
  not leave printing enabled.
- `-regexp` selects individual matching lines rather than an entire section.
- `-lead`, `-linger`, and `-context` add nearby lines around triggers.
- Files are processed independently and output is written to standard output.
- Diagnostics and file-opening errors are written to standard error.

### Exit status

```text
0    processing completed and at least one line was selected
1    processing completed but no lines were selected
2    invalid arguments or an input/output error
```

## Current limitations

- Use single-hyphen options such as `-help`; GNU-style `--help` is not
  supported.
- Paired trigger sets are planned but not implemented. All configured starts
  and stops share one printing state.
- Supplying multiple start, stop, or single-match expressions is not reliable;
  use one expression of each kind and combine alternatives with `|`.
- Option values are not fully validated. Always provide an argument after
  `-start`, `-stop`, `-regexp`, `-lead`, `-linger`, `-context`, and `-file`.

## Project commands

The small project `Makefile` provides the common development commands:

```sh
make help
make syntax
make test
make examples
make check
```

Sample input and runnable command examples live in `examples/`. The existing
test file is under `test/`; it is an unfinished placeholder and does not yet
test `onoff` behavior.

The original development notes and design questions are preserved in
`docs/Readme.notes`. Planned development is described in `docs/Roadmap.txt`.
