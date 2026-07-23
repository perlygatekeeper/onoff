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
--rule NAME         begin a named paired range rule
--output FILE       route a rule's ranges to one file
--output-template TEMPLATE
                    derive output filenames from each start match
--output-dir DIR    confine generated output beneath a directory
--otherwise FILE    write unselected input to a file
--append            append to existing output files
--force             replace existing output files
--on-duplicate POLICY
                    error, number, or append
--exclude-start     exclude the starting boundary
--exclude-end       exclude the ending boundary
--fixed             treat expressions as literal strings
--ignore-case       match without regard to letter case
--lead N            include N lines before a trigger
--linger N          include N lines after a trigger
--context N         include N lines before and after a trigger
--number            prefix output with line numbers
--list-ranges       report matched ranges instead of their contents
--interactive       ask whether to accept each candidate range
--responses FILE    read interactive answers from a file instead of a terminal
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

### Paired rules

Without `--rule`, repeated starts and ends retain the original shared-pool
behavior. A named rule connects its start expressions exclusively to its own
end expressions:

```sh
onoff \
  --rule errors \
    --start '^BEGIN ERROR$' \
    --end '^END ERROR$' \
  --rule reports \
    --start-after '^BEGIN REPORT$' \
    --end-before '^END REPORT$' \
  input.txt
```

The first declared rule whose start matches becomes active. While it is active,
only that rule's end expressions are examined. Other starts are ignored until
the active range ends. Rules do not nest or overlap.

Repeated start or end expressions within one rule are alternatives:

```sh
onoff \
  --rule failures \
    --start '^ERROR$' \
    --start '^FATAL$' \
    --end '^RECOVERED$' \
    --end '^ABORTED$' \
  logfile
```

Rule names begin with a letter and contain only letters, numbers, underscores,
or hyphens. Explicit rules cannot be mixed with implicit numeric, compact, or
unnamed start/end ranges in one command.

### Output routing

An output placed inside a rule applies to that rule:

```sh
onoff \
  --output-dir extracted \
  --rule errors \
    --start '^BEGIN ERROR$' \
    --end '^END ERROR$' \
    --output errors.txt \
  --rule reports \
    --start-after '^BEGIN REPORT$' \
    --end-before '^END REPORT$' \
    --output reports.txt \
  input.txt
```

Static destinations collect every match for that rule. Multiple rules may
intentionally name the same static destination. A rule without a destination
continues to write to standard output.

Dynamic templates create a destination for each matched range:

```sh
onoff \
  --output-dir extracted \
  --rule subs \
    --start-after '^[^#]*sub\s+(?<name>\S+)' \
    --end-before '^}$' \
    --output-template 'sub_{name}.pl' \
  source.pl
```

Supported template fields are:

```text
{1}             numbered start capture
{name}          named start capture
{number}        sequential range number
{number:03}     zero-padded sequential number
{input}         sanitized input path
{input_base}    sanitized input basename
{rule}          rule name
{start_line}    matching start line number
```

`$1`, `$2`, and similar fields are accepted as aliases for `{1}`, `{2}`, and
so on. Single-quote templates containing `$1` to prevent shell expansion.

Dynamic templates require `--output-dir`. Captured values are sanitized as
filename components, generated paths cannot escape the output directory, and
input files cannot also be output destinations.

Existing output files are refused by default:

```sh
onoff ... --force              # replace existing destinations
onoff ... --append             # append to existing destinations
```

When two dynamic ranges generate the same name, the default is an error:

```sh
--on-duplicate error           # default
--on-duplicate number          # name.txt, name_2.txt, ...
--on-duplicate append          # combine duplicate ranges
```

`--otherwise FILE` writes every unselected line—including excluded boundary
markers—to a separate static destination:

```sh
onoff \
  --output-dir split \
  --otherwise remainder.txt \
  --rule selected \
    --start-after '^BEGIN$' \
    --end-before '^END$' \
    --output selected.txt \
  input.txt
```

Non-append outputs are written through temporary files and finalized only
after successful processing. Append mode cannot be rolled back after an error.

### Interactive review

Review each matching start boundary before its range is selected:

```sh
onoff --interactive --start '^BEGIN$' --end '^END$' file.txt
```

Each prompt shows the input filename, matching line number, rule name, matching
line, and up to two preceding lines. The available responses are:

```text
yes (y)     select this range
no (n)      skip through this range's end boundary
all (a)     select this and all remaining candidate ranges
quit (q)    stop processing
```

Prompts and context use the controlling terminal, so selected standard output
remains safe for a pipeline or redirection. Without a usable terminal,
interactive mode exits with an error. For a repeatable scripted review, supply
one answer per line with `--responses FILE`; prompts are then written to
standard error:

```sh
onoff --interactive --responses answers.txt \
  --start '^BEGIN$' --end '^END$' file.txt
```

Interactive review applies to start/end ranges, including named rules. It
cannot be combined with `--list-ranges`; use the listing first when a
non-interactive inventory is sufficient.

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

The tab-separated report contains the input name, starting line, ending line,
and rule name. An unterminated range uses `EOF` as its end:

```text
file.txt    12    28     default
file.txt    61    EOF    default
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
- Named rules pair their own starts and ends and carry their own boundary
  inclusion policy.
- When several inactive rules start on one line, the first declared rule wins.
- While a rule is active, other starts are ignored until its paired end matches.
- Interactive review occurs at each candidate start boundary; rejecting one
  skips input through its paired end boundary.
- Interactive prompts never use standard output.
- Rule destinations are opened once and reused for static output.
- Dynamic destinations are expanded from captures and range metadata.
- Selected content is written only to its rule destination when one is set.
- `--otherwise` receives content not selected by a range or match.
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

- Paired rules do not nest or overlap; only one rule can be active.
- Explicit named rules cannot be mixed with implicit ranges in one command.
- Boundary inclusion remains global for an implicit range, but belongs to each
  explicit named rule.
- `--fixed` and `--ignore-case` apply to every expression in the command.
- Standard input may only appear once.
- End captures and `{end_line}` are not available in output templates because
  destinations are opened when ranges start.
- Configuration files and nested or overlapping output rules are not yet
  supported.
- Interactive prompts show preceding context but cannot show following lines
  without buffering input.

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
