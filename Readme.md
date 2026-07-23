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
--start REGEXP      start printing at a matching line
--start-after REGEXP
                    start after an excluded matching line
--end REGEXP        stop printing after a matching line
--end-before REGEXP
                    stop before an excluded matching line
--regexp REGEXP     print individual matching lines
--exclude-start     exclude the starting boundary
--exclude-end       exclude the ending boundary
--fixed             treat expressions as literal strings
--ignore-case       match without regard to letter case
--lead N            include N lines before a trigger
--linger N          include N lines after a trigger
--context N         include N lines before and after a trigger
--number            prefix output with line numbers
--list-ranges       report matched ranges instead of their contents
--file FILE         add an input file explicitly
--help              show detailed option help
--usage             show a short usage summary
--debug             show argument parsing and processing details
```

The legacy single-hyphen forms remain supported. The aliases `--on` and
`--begin` mean `--start`; `--off` and `--stop` mean `--end`; and `--find` and
`--grep` mean `--regexp`. Unique option abbreviations are also accepted.

Regular expressions are Perl regular expressions supplied as plain arguments.
Do not surround them with `/` characters. Quote expressions containing spaces
or shell metacharacters. Repeating an expression option adds an alternative.

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
onoff --start '^BEGIN$' --end '^END$' file.txt
```

The compact range form expresses the same operation:

```sh
onoff 'BEGIN..END' file.txt
```

Print lines containing `error`, with two lines of context on each side:

```sh
onoff --regexp 'error' --context 2 logfile
```

Print numbered output from line 20 onward, stopping at `__END__`, and include
two additional lines:

```sh
onoff 20.. --end '__END__' --linger 2 --number source.pl
```

Read from a pipeline:

```sh
some-command | onoff --start 'connected' --end 'disconnected'
```

Multiple files may be supplied. Each file is opened and processed in order:

```sh
onoff 1..10 first.txt second.txt
```

Treat an expression literally rather than as a regular expression:

```sh
onoff --fixed --regexp '[warning]' logfile
```

Match several alternatives without regard to case:

```sh
onoff --ignore-case \
  --regexp '^warning:' \
  --regexp '^error:' \
  logfile
```

Report logical range locations without printing their contents:

```sh
onoff --start '^BEGIN$' --end '^END$' --list-ranges file.txt
```

The tab-separated report contains the input name, starting line, and ending
line. An unterminated range uses `EOF` as its end:

```text
file.txt    12    28
file.txt    61    EOF
```

Print only the content between marker lines:

```sh
onoff \
  --start-after '^BEGIN$' \
  --end-before '^END$' \
  file.txt
```

The general boundary modifiers also apply to numeric and compact ranges:

```sh
onoff --exclude-start --exclude-end 4..10 file.txt
onoff --exclude-start --exclude-end 'BEGIN..END' file.txt
```

## Behavior

- Start and stop lines are printed inclusively.
- `--start-after` and `--exclude-start` exclude a starting boundary.
- `--end-before` and `--exclude-end` exclude an ending boundary.
- A boundary match changes range state whether or not its line is included.
- After a stop, scanning continues, so later start/stop sections may also be
  printed.
- A line matching both the start and stop condition is printed once and does
  not leave printing enabled. It is omitted only when both boundary roles are
  excluded.
- `--regexp` selects individual matching lines rather than an entire section.
- `--lead`, `--linger`, and `--context` add nearby lines around triggers.
- Repeated start, end, and individual expressions are combined as alternatives.
- Files are processed independently and output is written to standard output.
- Line numbers, printing state, context, and active ranges reset for each file.
- Diagnostics and file-opening errors are written to standard error.

### Exit status

```text
0    processing completed and at least one line was selected
1    processing completed but no lines were selected
2    invalid arguments or an input/output error
```

## Current limitations

- Paired trigger sets are planned but not implemented. All configured starts
  and stops share one printing state.
- Boundary inclusion policy is global. Mixing `--start` with `--start-after`,
  or `--end` with `--end-before`, requires paired rules and is rejected.
- `--fixed` and `--ignore-case` apply to every expression in the command.
- Standard input may only appear once.

## Project commands

The small project `Makefile` provides the common development commands:

```sh
make help
make syntax
make test
make examples
make check
```

Sample input and runnable command examples live in `examples/`. Black-box tests
of the command-line behavior live under `test/`.

The original development notes and design questions are preserved in
`docs/Readme.notes`. Planned development is described in `docs/Roadmap.txt`.
