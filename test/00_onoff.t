#!/usr/bin/env perl

use strict;
use warnings;

use Test::More;
use File::Spec;
use File::Temp qw(tempdir);
use FindBin qw($Bin);
use IPC::Open3;
use Symbol qw(gensym);

my $root   = File::Spec->catdir($Bin, '..');
my $onoff = File::Spec->catfile($root, 'onoff');
my $sample = File::Spec->catfile($root, 'examples', 'text2.txt');

sub run_onoff {
  my ($stdin, @args) = @_;
  my $error = gensym;
  my $pid = open3(my $input, my $output, $error, $^X, $onoff, @args);

  if (defined $stdin) {
    print {$input} $stdin;
  }
  close $input;

  local $/;
  my $stdout = <$output> // '';
  my $stderr = <$error>  // '';
  waitpid $pid, 0;

  return ($stdout, $stderr, $? >> 8);
}

sub read_text_file {
  my $filename = shift;
  open my $filehandle, '<', $filename or die "Cannot read '$filename': $!";
  local $/;
  my $text = <$filehandle> // '';
  close $filehandle or die "Cannot close '$filename': $!";
  return $text;
}

my ($stdout, $stderr, $status) = run_onoff(undef, '13', $sample);
is($stdout, "    13\tThirteen\n", 'prints one numbered input line');
is($stderr, '', 'one-line selection has no diagnostics');
is($status, 0, 'one-line selection succeeds');

($stdout, $stderr, $status) = run_onoff(undef, '4..7', $sample);
is(
  $stdout,
  "     4\tFour\n     5\tFive\n     6\tSix\n     7\tSeven\n",
  'prints an inclusive numeric range',
);

($stdout, $stderr, $status) = run_onoff(undef, '..3', $sample);
is(
  $stdout,
  "     1\tOne\n     2\tTwo\n     3\tThree\n",
  'prints from the beginning through a numbered line',
);

($stdout, $stderr, $status) = run_onoff(undef, '107..', $sample);
is(
  $stdout,
  "   107\tHundred Seven\n   108\tHundred Eight\n   109\tHundred Nine\n",
  'prints from a numbered line through end of file',
);

my $sections = <<'TEXT';
outside
BEGIN
inside
END
outside again
BEGIN
second
END
TEXT

($stdout, $stderr, $status) = run_onoff(
  $sections, '-start', '^BEGIN$', '-stop', '^END$', '-',
);
is(
  $stdout,
  "BEGIN\ninside\nEND\nBEGIN\nsecond\nEND\n",
  'prints repeated inclusive regexp ranges from standard input',
);

($stdout, $stderr, $status) = run_onoff(
  $sections, 'BEGIN..END', '-',
);
is(
  $stdout,
  "BEGIN\ninside\nEND\nBEGIN\nsecond\nEND\n",
  'supports the compact regexp range form',
);

($stdout, $stderr, $status) = run_onoff(
  "zero\nmatch\ntwo\n", '-regexp', '^match$', '-context', '1', '-',
);
is($stdout, "zero\nmatch\ntwo\n", 'prints a match with context');

($stdout, $stderr, $status) = run_onoff(
  "BEGIN\ninside\nEND\nafter\n", '-start', '^BEGIN$', '-stop', '^END$',
  '-linger', '1', '-number', '-',
);
is(
  $stdout,
  "    1 BEGIN\n    2 inside\n    3 END\n    4 after\n",
  'numbers lingering output correctly',
);

($stdout, $stderr, $status) = run_onoff(undef, '-usage');
like($stdout, qr/^usage:/, 'usage option prints the synopsis');
is($status, 0, 'usage option succeeds');

($stdout, $stderr, $status) = run_onoff(undef, '-help');
like($stdout, qr/-start\s+regexp to trigger printing/, 'help describes options');
is($status, 0, 'help option succeeds');

($stdout, $stderr, $status) = run_onoff(
  "zero\nbefore\nmatch\nafter\n", '-regexp', '^match$', '-lead', '1', '-',
);
is($stdout, "before\nmatch\n", 'lead prints only the requested preceding line');

($stdout, $stderr, $status) = run_onoff(
  "match\nafter\nlast\n", '-regexp', '^match$', '-linger', '1', '-',
);
is($stdout, "match\nafter\n", 'linger prints only the requested following line');

($stdout, $stderr, $status) = run_onoff(
  "first\nmatch\nmiddle\nmatch\nlast\n",
  '-regexp', '^match$', '-context', '1', '-',
);
is(
  $stdout,
  "first\nmatch\nmiddle\nmatch\nlast\n",
  'overlapping context is merged without duplicates or missed triggers',
);

my $temporary_directory = tempdir(CLEANUP => 1);
my $first_file = File::Spec->catfile($temporary_directory, 'first.txt');
my $second_file = File::Spec->catfile($temporary_directory, 'second.txt');
for my $file_and_text (
  [$first_file,  "first one\nfirst two\n"],
  [$second_file, "second one\nsecond two\n"],
) {
  open my $filehandle, '>', $file_and_text->[0] or die $!;
  print {$filehandle} $file_and_text->[1];
  close $filehandle or die $!;
}

($stdout, $stderr, $status) = run_onoff(
  undef, '2', $first_file, $second_file,
);
is($stdout, "first two\nsecond two\n", 'processes each input file independently');

($stdout, $stderr, $status) = run_onoff(
  "outside\nBEGIN\ninside\n", '-start', '^BEGIN$',
);
is($stdout, "BEGIN\ninside\n", 'reads standard input when no file is supplied');
is($status, 0, 'default standard-input selection succeeds');

($stdout, $stderr, $status) = run_onoff(
  "nothing here\n", '-regexp', '^missing$',
);
is($stdout, '', 'a run with no matches has no output');
is($status, 1, 'a run with no matches exits with status 1');

($stdout, $stderr, $status) = run_onoff(
  "BEGIN\ninside\n", '-start', '^BEGIN$', '-stop', '^END$',
);
is($stdout, "BEGIN\ninside\n", 'an unterminated range prints through end of file');
is($status, 0, 'an unterminated range with output succeeds');

($stdout, $stderr, $status) = run_onoff(
  "MARK\noutside\n", '-start', '^MARK$', '-stop', '^MARK$',
);
is($stdout, "MARK\n", 'a line matching both boundaries is printed once');

($stdout, $stderr, $status) = run_onoff(
  undef, '1', File::Spec->catfile($temporary_directory, 'missing.txt'),
);
is($status, 2, 'an unreadable input file exits with status 2');
like($stderr, qr/Cannot read/, 'an unreadable input file reports its error');

for my $invalid_case (
  [['-start'],                  'missing start expression'],
  [['-context', '-1', '-'],     'negative context'],
  [['0', $sample],              'line number zero'],
  [['9..3', $sample],           'reversed numeric range'],
  [['-regexp', '(', '-'],       'invalid regular expression'],
  [['-not-an-option'],          'unknown option'],
) {
  ($stdout, $stderr, $status) = run_onoff('', @{$invalid_case->[0]});
  is($status, 2, "$invalid_case->[1] exits with status 2");
  like($stderr, qr/^onoff:/, "$invalid_case->[1] reports a usage error");
}

($stdout, $stderr, $status) = run_onoff(
  $sections, '--start', '^BEGIN$', '--end', '^END$',
);
is(
  $stdout,
  "BEGIN\ninside\nEND\nBEGIN\nsecond\nEND\n",
  'conventional long start and end options work',
);

($stdout, $stderr, $status) = run_onoff(
  $sections, '-sta', '^BEGIN$', '-sto', '^END$',
);
is(
  $stdout,
  "BEGIN\ninside\nEND\nBEGIN\nsecond\nEND\n",
  'legacy unique option abbreviations remain compatible',
);

($stdout, $stderr, $status) = run_onoff(undef, '--help');
like($stdout, qr/--start/, 'double-hyphen help works');
is($status, 0, 'double-hyphen help succeeds');

my $literal_sections = <<'TEXT';
outside
[BEGIN]
inside
[END]
outside again
TEXT

($stdout, $stderr, $status) = run_onoff(
  $literal_sections,
  '--fixed', '--start', '[BEGIN]', '--end', '[END]',
);
is(
  $stdout,
  "[BEGIN]\ninside\n[END]\n",
  'fixed matching treats regular-expression punctuation literally',
);

($stdout, $stderr, $status) = run_onoff(
  "outside\nbegin\ninside\nEnD\n",
  '--ignore-case', '--start', '^BEGIN$', '--end', '^end$',
);
is(
  $stdout,
  "begin\ninside\nEnD\n",
  'ignore-case applies to start and end expressions',
);

($stdout, $stderr, $status) = run_onoff(
  "outside\nOPEN\none\nCLOSE\noutside\nBEGIN\ntwo\nEND\n",
  '--start', '^OPEN$', '--start', '^BEGIN$',
  '--end', '^CLOSE$', '--end', '^END$',
);
is(
  $stdout,
  "OPEN\none\nCLOSE\nBEGIN\ntwo\nEND\n",
  'repeated starts and ends accumulate as alternatives',
);

($stdout, $stderr, $status) = run_onoff(
  "zero\napple\nbanana\ncarrot\n",
  '--regexp', '^apple$', '--regexp', '^carrot$',
);
is($stdout, "apple\ncarrot\n", 'repeated individual expressions accumulate');

my $unterminated_file = File::Spec->catfile(
  $temporary_directory,
  'unterminated.txt',
);
my $following_file = File::Spec->catfile(
  $temporary_directory,
  'following.txt',
);
for my $file_and_text (
  [$unterminated_file, "BEGIN\nfirst file\n"],
  [$following_file,    "second file\nEND\n"],
) {
  open my $filehandle, '>', $file_and_text->[0] or die $!;
  print {$filehandle} $file_and_text->[1];
  close $filehandle or die $!;
}

($stdout, $stderr, $status) = run_onoff(
  undef,
  '--start', '^BEGIN$', '--end', '^END$',
  $unterminated_file, $following_file,
);
is(
  $stdout,
  "BEGIN\nfirst file\n",
  'printing state does not carry into the next file',
);

($stdout, $stderr, $status) = run_onoff(
  undef, '--regexp', '^second file$', '--lead', '1',
  $unterminated_file, $following_file,
);
is(
  $stdout,
  "second file\n",
  'lead context does not carry between files',
);

($stdout, $stderr, $status) = run_onoff(
  undef, '--regexp', '^first file$', '--linger', '1',
  $unterminated_file, $following_file,
);
is(
  $stdout,
  "first file\n",
  'linger state does not carry between files',
);

($stdout, $stderr, $status) = run_onoff(
  '', '--regexp', 'anything', '-', '-',
);
is($status, 2, 'standard input cannot be listed more than once');
like($stderr, qr/standard input.*once/, 'repeated standard input is explained');

my $range_listing_input = <<'TEXT';
outside
BEGIN
inside
END
outside
BEGIN
unfinished
TEXT

($stdout, $stderr, $status) = run_onoff(
  $range_listing_input,
  '--start', '^BEGIN$', '--end', '^END$', '--list-ranges',
);
is(
  $stdout,
  "<stdin>\t2\t4\tdefault\n<stdin>\t6\tEOF\tdefault\n",
  'list-ranges reports completed and unterminated logical ranges',
);
is($status, 0, 'list-ranges succeeds when ranges were found');

($stdout, $stderr, $status) = run_onoff(
  "zero\nmatch\ntwo\n", '--regexp', '^match$', '--list-ranges',
);
is($stdout, "<stdin>\t2\t2\tmatch\n", 'list-ranges reports individual matches');

($stdout, $stderr, $status) = run_onoff(
  "zero\nnothing\ntwo\n", '--regexp', '^match$', '--list-ranges',
);
is($stdout, '', 'list-ranges prints nothing when no range matched');
is($status, 1, 'list-ranges returns status 1 when no range matched');

my $boundary_input = <<'TEXT';
outside
BEGIN
inside
END
outside again
TEXT

for my $boundary_case (
  [
    ['--start', '^BEGIN$', '--end', '^END$'],
    "BEGIN\ninside\nEND\n",
    'inclusive start and inclusive end',
  ],
  [
    ['--start-after', '^BEGIN$', '--end', '^END$'],
    "inside\nEND\n",
    'exclusive start and inclusive end',
  ],
  [
    ['--start', '^BEGIN$', '--end-before', '^END$'],
    "BEGIN\ninside\n",
    'inclusive start and exclusive end',
  ],
  [
    ['--start-after', '^BEGIN$', '--end-before', '^END$'],
    "inside\n",
    'exclusive start and exclusive end',
  ],
) {
  ($stdout, $stderr, $status) = run_onoff(
    $boundary_input,
    @{$boundary_case->[0]},
  );
  is($stdout, $boundary_case->[1], $boundary_case->[2]);
  is($status, 0, "$boundary_case->[2] succeeds");
}

($stdout, $stderr, $status) = run_onoff(
  undef, '--exclude-start', '--exclude-end', '4..7', $sample,
);
is(
  $stdout,
  "     5\tFive\n     6\tSix\n",
  'boundary modifiers apply to numeric ranges',
);

($stdout, $stderr, $status) = run_onoff(
  $boundary_input,
  '--exclude-start', '--exclude-end', 'BEGIN..END',
);
is($stdout, "inside\n", 'boundary modifiers apply to compact regexp ranges');

($stdout, $stderr, $status) = run_onoff(
  "one\ntwo\nthree\n", '--exclude-end', '..3',
);
is($stdout, "one\ntwo\n", 'exclude-end applies to a range from file start');

($stdout, $stderr, $status) = run_onoff(
  "one\ntwo\nthree\n", '--exclude-start', '1..',
);
is($stdout, "two\nthree\n", 'exclude-start applies to a range through EOF');

for my $same_line_case (
  [
    ['--start', '^MARK$', '--end', '^MARK$'],
    "MARK\n",
    'same line with both boundaries included',
  ],
  [
    ['--start-after', '^MARK$', '--end', '^MARK$'],
    "MARK\n",
    'same line with only end included',
  ],
  [
    ['--start', '^MARK$', '--end-before', '^MARK$'],
    "MARK\n",
    'same line with only start included',
  ],
  [
    ['--start-after', '^MARK$', '--end-before', '^MARK$'],
    '',
    'same line with both boundaries excluded',
  ],
) {
  ($stdout, $stderr, $status) = run_onoff(
    "MARK\noutside\n",
    @{$same_line_case->[0]},
  );
  is($stdout, $same_line_case->[1], $same_line_case->[2]);
}

($stdout, $stderr, $status) = run_onoff(
  "BEGIN\nEND\n",
  '--start-after', '^BEGIN$', '--end-before', '^END$',
);
is($stdout, '', 'adjacent excluded boundaries produce no output');
is($status, 1, 'an empty exclusive range returns status 1');

($stdout, $stderr, $status) = run_onoff(
  "outside\nBEGIN\ninside\n",
  '--start-after', '^BEGIN$', '--end-before', '^END$',
);
is($stdout, "inside\n", 'an unterminated range honors excluded start');

($stdout, $stderr, $status) = run_onoff(
  "before\nBEGIN\ninside\nEND\nafter\n",
  '--start-after', '^BEGIN$', '--end-before', '^END$',
  '--lead', '1', '--linger', '1',
);
is(
  $stdout,
  "before\ninside\nafter\n",
  'context does not reintroduce excluded boundary markers',
);

($stdout, $stderr, $status) = run_onoff(
  $boundary_input,
  '--start-after', '^BEGIN$', '--end-before', '^END$',
  '--regexp', '^BEGIN$',
);
is(
  $stdout,
  "BEGIN\ninside\n",
  'an individual match can independently select an excluded boundary',
);

for my $mixed_policy_case (
  [
    ['--start', '^BEGIN$', '--start-after', '^OPEN$'],
    'mixed start boundary policies',
  ],
  [
    ['--end', '^END$', '--end-before', '^CLOSE$'],
    'mixed end boundary policies',
  ],
) {
  ($stdout, $stderr, $status) = run_onoff(
    '', @{$mixed_policy_case->[0]},
  );
  is($status, 2, "$mixed_policy_case->[1] are rejected");
  like($stderr, qr/mixed .* boundary policies/, 'mixed-policy error is clear');
}

($stdout, $stderr, $status) = run_onoff(
  $boundary_input,
  '--start-after', '^BEGIN$', '--end-before', '^END$', '--list-ranges',
);
is(
  $stdout,
  "<stdin>\t3\t3\tdefault\n",
  'list-ranges reports selected boundaries after exclusion',
);

($stdout, $stderr, $status) = run_onoff(
  "BEGIN\nEND\n",
  '--start-after', '^BEGIN$', '--end-before', '^END$', '--list-ranges',
);
is($stdout, '', 'list-ranges omits an empty exclusive range');
is($status, 1, 'an empty listed range returns status 1');

($stdout, $stderr, $status) = run_onoff(
  "outside\nBEGIN\ninside\n",
  '--start-after', '^BEGIN$', '--end-before', '^END$', '--list-ranges',
);
is(
  $stdout,
  "<stdin>\t3\tEOF\tdefault\n",
  'list-ranges reports an unterminated exclusive-start range',
);

my $paired_input = <<'TEXT';
outside
BEGIN A
a one
END B
a two
END A
outside
BEGIN B
b one
END A
b two
END B
outside
TEXT

($stdout, $stderr, $status) = run_onoff(
  $paired_input,
  '--rule', 'alpha', '--start', '^BEGIN A$', '--end', '^END A$',
  '--rule', 'beta',  '--start', '^BEGIN B$', '--end', '^END B$',
);
is(
  $stdout,
  "BEGIN A\na one\nEND B\na two\nEND A\n"
    . "BEGIN B\nb one\nEND A\nb two\nEND B\n",
  'each paired start is closed only by its own end',
);

my $precedence_input = <<'TEXT';
START
inside
GENERAL END
still inside
SPECIFIC END
TEXT

($stdout, $stderr, $status) = run_onoff(
  $precedence_input,
  '--rule', 'specific', '--start', '^START$', '--end', '^SPECIFIC END$',
  '--rule', 'general',  '--start', '^START$', '--end', '^GENERAL END$',
);
is(
  $stdout,
  "START\ninside\nGENERAL END\nstill inside\nSPECIFIC END\n",
  'the first declared matching rule wins',
);

($stdout, $stderr, $status) = run_onoff(
  "outside\nBEGIN A\na\nEND A\noutside\nBEGIN B\nb\nEND B\n",
  '--rule', 'alpha',
    '--start-after', '^BEGIN A$', '--end-before', '^END A$',
  '--rule', 'beta',
    '--start', '^BEGIN B$', '--end', '^END B$',
);
is(
  $stdout,
  "a\nBEGIN B\nb\nEND B\n",
  'boundary inclusion belongs to each paired rule',
);

($stdout, $stderr, $status) = run_onoff(
  "OPEN\none\nCLOSE\nBEGIN\ntwo\nEND\n",
  '--rule', 'sections',
  '--start', '^OPEN$', '--start', '^BEGIN$',
  '--end', '^CLOSE$', '--end', '^END$',
);
is(
  $stdout,
  "OPEN\none\nCLOSE\nBEGIN\ntwo\nEND\n",
  'a paired rule may have repeated start and end alternatives',
);

($stdout, $stderr, $status) = run_onoff(
  "MARK\noutside\n",
  '--rule', 'marker', '--start-after', '^MARK$', '--end', '^MARK$',
);
is($stdout, "MARK\n", 'same-line paired boundaries use the rule policy once');

($stdout, $stderr, $status) = run_onoff(
  "outside\nBEGIN\ninside\n",
  '--rule', 'section', '--start-after', '^BEGIN$', '--end-before', '^END$',
);
is($stdout, "inside\n", 'an unterminated paired rule prints through EOF');

($stdout, $stderr, $status) = run_onoff(
  undef,
  '--rule', 'section', '--start', '^BEGIN$', '--end', '^END$',
  $unterminated_file, $following_file,
);
is(
  $stdout,
  "BEGIN\nfirst file\n",
  'an active paired rule resets between files',
);

($stdout, $stderr, $status) = run_onoff(
  "IMPORTANT\noutside\nBEGIN\ninside\nEND\nIMPORTANT\n",
  '--rule', 'section', '--start', '^BEGIN$', '--end', '^END$',
  '--regexp', '^IMPORTANT$',
);
is(
  $stdout,
  "IMPORTANT\nBEGIN\ninside\nEND\nIMPORTANT\n",
  'individual matches remain independent of paired rules',
);

($stdout, $stderr, $status) = run_onoff(
  $paired_input,
  '--rule', 'alpha', '--start-after', '^BEGIN A$', '--end-before', '^END A$',
  '--rule', 'beta', '--start', '^BEGIN B$', '--end', '^END B$',
  '--list-ranges',
);
is(
  $stdout,
  "<stdin>\t3\t5\talpha\n<stdin>\t8\t12\tbeta\n",
  'list-ranges identifies each paired rule',
);

($stdout, $stderr, $status) = run_onoff(
  "outside\n[begin]\ninside\n[end]\n",
  '--fixed', '--ignore-case',
  '--rule', 'literal', '--start-after', '[BEGIN]', '--end-before', '[END]',
);
is(
  $stdout,
  "inside\n",
  'fixed and ignore-case matching apply within paired rules',
);

for my $invalid_rule_case (
  [
    ['--rule', 'missing_start', '--end', '^END$'],
    qr/requires at least one start/,
    'a rule missing its start',
  ],
  [
    ['--rule', 'missing_end', '--start', '^BEGIN$'],
    qr/requires at least one end/,
    'a rule missing its end',
  ],
  [
    [
      '--rule', 'same', '--start', '^A$', '--end', '^B$',
      '--rule', 'same', '--start', '^C$', '--end', '^D$',
    ],
    qr/duplicate rule name/,
    'duplicate rule names',
  ],
  [
    [
      '--start', '^LEGACY$', '--end', '^END$',
      '--rule', 'paired', '--start', '^A$', '--end', '^B$',
    ],
    qr/cannot mix explicit rules with implicit ranges/,
    'mixed implicit and explicit rules',
  ],
  [
    ['--rule', '../unsafe', '--start', '^A$', '--end', '^B$'],
    qr/invalid rule name/,
    'an unsafe rule name',
  ],
) {
  ($stdout, $stderr, $status) = run_onoff('', @{$invalid_rule_case->[0]});
  is($status, 2, "$invalid_rule_case->[2] is rejected");
  like($stderr, $invalid_rule_case->[1], "$invalid_rule_case->[2] is explained");
}

my $routing_root = File::Spec->catdir($temporary_directory, 'routing');
mkdir $routing_root or die "Cannot create '$routing_root': $!";

my $static_dir = File::Spec->catdir($routing_root, 'static');
mkdir $static_dir or die "Cannot create '$static_dir': $!";
($stdout, $stderr, $status) = run_onoff(
  $paired_input,
  '--output-dir', $static_dir,
  '--rule', 'alpha', '--start', '^BEGIN A$', '--end', '^END A$',
    '--output', 'alpha.txt',
  '--rule', 'beta', '--start-after', '^BEGIN B$', '--end-before', '^END B$',
    '--output', 'beta.txt',
);
is($stdout, '', 'routed paired rules do not also print to standard output');
is($status, 0, 'static paired output routing succeeds');
is(
  read_text_file(File::Spec->catfile($static_dir, 'alpha.txt')),
  "BEGIN A\na one\nEND B\na two\nEND A\n",
  'the alpha rule is written to its static output',
);
is(
  read_text_file(File::Spec->catfile($static_dir, 'beta.txt')),
  "b one\nEND A\nb two\n",
  'the beta rule uses its own output and boundary policy',
);

my $aggregate_dir = File::Spec->catdir($routing_root, 'aggregate');
mkdir $aggregate_dir or die "Cannot create '$aggregate_dir': $!";
($stdout, $stderr, $status) = run_onoff(
  "BEGIN\none\nEND\noutside\nBEGIN\ntwo\nEND\n",
  '--output-dir', $aggregate_dir,
  '--rule', 'sections', '--start-after', '^BEGIN$', '--end-before', '^END$',
  '--output', 'sections.txt',
);
is(
  read_text_file(File::Spec->catfile($aggregate_dir, 'sections.txt')),
  "one\ntwo\n",
  'repeated matches for a static output are aggregated',
);

my $shared_dir = File::Spec->catdir($routing_root, 'shared');
mkdir $shared_dir or die "Cannot create '$shared_dir': $!";
($stdout, $stderr, $status) = run_onoff(
  "BEGIN A\na\nEND A\nBEGIN B\nb\nEND B\n",
  '--output-dir', $shared_dir,
  '--rule', 'alpha', '--start-after', '^BEGIN A$', '--end-before', '^END A$',
    '--output', 'shared.txt',
  '--rule', 'beta', '--start-after', '^BEGIN B$', '--end-before', '^END B$',
    '--output', 'shared.txt',
);
is(
  read_text_file(File::Spec->catfile($shared_dir, 'shared.txt')),
  "a\nb\n",
  'multiple rules may intentionally share one static output',
);

my $capture_dir = File::Spec->catdir($routing_root, 'captures');
mkdir $capture_dir or die "Cannot create '$capture_dir': $!";
my $capture_input = <<'TEXT';
BEGIN alpha
one
END
BEGIN beta
two
END
TEXT

($stdout, $stderr, $status) = run_onoff(
  $capture_input,
  '--output-dir', $capture_dir,
  '--rule', 'named',
  '--start-after', '^BEGIN (?<name>\S+)$', '--end-before', '^END$',
  '--output-template', '{name}.txt',
);
is($status, 0, 'named-capture output templates succeed');
is(
  read_text_file(File::Spec->catfile($capture_dir, 'alpha.txt')),
  "one\n",
  'a named start capture creates the first filename',
);
is(
  read_text_file(File::Spec->catfile($capture_dir, 'beta.txt')),
  "two\n",
  'a named start capture creates the second filename',
);

my $sequence_dir = File::Spec->catdir($routing_root, 'sequence');
mkdir $sequence_dir or die "Cannot create '$sequence_dir': $!";
($stdout, $stderr, $status) = run_onoff(
  $capture_input,
  '--output-dir', $sequence_dir,
  '--rule', 'parts', '--start-after', '^BEGIN (\S+)$', '--end-before', '^END$',
  '--output-template', '{rule}_{number:02}_{1}.txt',
);
is(
  read_text_file(File::Spec->catfile($sequence_dir, 'parts_01_alpha.txt')),
  "one\n",
  'sequential, rule, and numbered-capture fields expand together',
);
is(
  read_text_file(File::Spec->catfile($sequence_dir, 'parts_02_beta.txt')),
  "two\n",
  'sequential output numbering advances for each range',
);

my $sanitized_dir = File::Spec->catdir($routing_root, 'sanitized');
mkdir $sanitized_dir or die "Cannot create '$sanitized_dir': $!";
($stdout, $stderr, $status) = run_onoff(
  "BEGIN ../../unsafe\ninside\nEND\n",
  '--output-dir', $sanitized_dir,
  '--rule', 'safe', '--start-after', '^BEGIN (.+)$', '--end-before', '^END$',
  '--output-template', '$1.txt',
);
is($status, 0, 'captured path separators are sanitized safely');
opendir my $sanitized_handle, $sanitized_dir or die $!;
my @sanitized_files = grep { $_ !~ /^\./ } readdir $sanitized_handle;
closedir $sanitized_handle;
is(scalar @sanitized_files, 1, 'a sanitized capture creates one confined file');
is(
  read_text_file(File::Spec->catfile($sanitized_dir, $sanitized_files[0])),
  "inside\n",
  'the sanitized capture output contains the selected range',
);

my $metadata_dir = File::Spec->catdir($routing_root, 'metadata');
mkdir $metadata_dir or die "Cannot create '$metadata_dir': $!";
($stdout, $stderr, $status) = run_onoff(
  undef,
  '--output-dir', $metadata_dir,
  '--rule', 'meta', '--start', '^BEGIN$', '--end', '^END$',
  '--output-template', '{input_base}_{rule}_{start_line}.txt',
  $unterminated_file,
);
ok(
  -e File::Spec->catfile(
    $metadata_dir,
    'unterminated.txt_meta_1.txt',
  ),
  'input basename, rule name, and start line expand in templates',
);

my $duplicate_error_dir = File::Spec->catdir($routing_root, 'duplicate-error');
mkdir $duplicate_error_dir or die "Cannot create '$duplicate_error_dir': $!";
my $duplicate_input = "BEGIN same\none\nEND\nBEGIN same\ntwo\nEND\n";
($stdout, $stderr, $status) = run_onoff(
  $duplicate_input,
  '--output-dir', $duplicate_error_dir,
  '--rule', 'dupes', '--start-after', '^BEGIN (\S+)$', '--end-before', '^END$',
  '--output-template', '{1}.txt',
);
is($status, 2, 'duplicate generated filenames fail by default');
like($stderr, qr/duplicate generated output/, 'duplicate output is explained');
ok(
  !-e File::Spec->catfile($duplicate_error_dir, 'same.txt'),
  'atomic output is not finalized after a routing error',
);

my $duplicate_number_dir = File::Spec->catdir($routing_root, 'duplicate-number');
mkdir $duplicate_number_dir or die "Cannot create '$duplicate_number_dir': $!";
($stdout, $stderr, $status) = run_onoff(
  $duplicate_input,
  '--output-dir', $duplicate_number_dir,
  '--on-duplicate', 'number',
  '--rule', 'dupes', '--start-after', '^BEGIN (\S+)$', '--end-before', '^END$',
  '--output-template', '{1}.txt',
);
is($status, 0, 'numbered duplicate policy succeeds');
is(
  read_text_file(File::Spec->catfile($duplicate_number_dir, 'same.txt')),
  "one\n",
  'the first duplicate keeps the requested name',
);
is(
  read_text_file(File::Spec->catfile($duplicate_number_dir, 'same_2.txt')),
  "two\n",
  'the second duplicate receives a numeric suffix',
);

my $existing_dir = File::Spec->catdir($routing_root, 'existing');
mkdir $existing_dir or die "Cannot create '$existing_dir': $!";
my $existing_file = File::Spec->catfile($existing_dir, 'result.txt');
open my $existing_handle, '>', $existing_file or die $!;
print {$existing_handle} "existing\n";
close $existing_handle or die $!;

($stdout, $stderr, $status) = run_onoff(
  "BEGIN\nnew\nEND\n",
  '--output-dir', $existing_dir,
  '--rule', 'result', '--start-after', '^BEGIN$', '--end-before', '^END$',
  '--output', 'result.txt',
);
is($status, 2, 'existing output is refused by default');
is(read_text_file($existing_file), "existing\n", 'refused output is unchanged');

($stdout, $stderr, $status) = run_onoff(
  "BEGIN\nreplacement\nEND\n",
  '--output-dir', $existing_dir, '--force',
  '--rule', 'result', '--start-after', '^BEGIN$', '--end-before', '^END$',
  '--output', 'result.txt',
);
is($status, 0, 'force permits replacement');
is(read_text_file($existing_file), "replacement\n", 'force replaces output');

($stdout, $stderr, $status) = run_onoff(
  "BEGIN\nappended\nEND\n",
  '--output-dir', $existing_dir, '--append',
  '--rule', 'result', '--start-after', '^BEGIN$', '--end-before', '^END$',
  '--output', 'result.txt',
);
is($status, 0, 'append permits existing output');
is(
  read_text_file($existing_file),
  "replacement\nappended\n",
  'append preserves and extends existing output',
);

my $otherwise_dir = File::Spec->catdir($routing_root, 'otherwise');
mkdir $otherwise_dir or die "Cannot create '$otherwise_dir': $!";
($stdout, $stderr, $status) = run_onoff(
  "outside one\nBEGIN\ninside\nEND\noutside two\n",
  '--output-dir', $otherwise_dir,
  '--otherwise', 'otherwise.txt',
  '--rule', 'selected', '--start-after', '^BEGIN$', '--end-before', '^END$',
  '--output', 'selected.txt',
);
is(
  read_text_file(File::Spec->catfile($otherwise_dir, 'selected.txt')),
  "inside\n",
  'selected lines are routed to the rule output',
);
is(
  read_text_file(File::Spec->catfile($otherwise_dir, 'otherwise.txt')),
  "outside one\nBEGIN\nEND\noutside two\n",
  'otherwise receives every unselected line',
);

my $mixed_output_dir = File::Spec->catdir($routing_root, 'mixed-output');
mkdir $mixed_output_dir or die "Cannot create '$mixed_output_dir': $!";
($stdout, $stderr, $status) = run_onoff(
  "BEGIN A\na\nEND A\nBEGIN B\nb\nEND B\n",
  '--output-dir', $mixed_output_dir,
  '--rule', 'alpha', '--start', '^BEGIN A$', '--end', '^END A$',
    '--output', 'alpha.txt',
  '--rule', 'beta', '--start', '^BEGIN B$', '--end', '^END B$',
);
is(
  $stdout,
  "BEGIN B\nb\nEND B\n",
  'a rule without a destination continues to use standard output',
);

for my $invalid_output_case (
  [
    [
      '--rule', 'x', '--start', '^A$', '--end', '^B$',
      '--output-template', '{number}.txt',
    ],
    qr/requires --output-dir/,
    'a dynamic template without output-dir',
  ],
  [
    [
      '--output-dir', $routing_root,
      '--rule', 'x', '--start', '^A$', '--end', '^B$',
      '--output', '../escape.txt',
    ],
    qr/parent-directory traversal/,
    'parent traversal in output',
  ],
  [
    [
      '--output-dir', $routing_root,
      '--rule', 'x', '--start', '^A$', '--end', '^B$',
      '--output-template', '{unknown}.txt',
    ],
    qr/unknown template field/,
    'an unknown template field',
  ],
  [
    [
      '--append', '--force',
      '--rule', 'x', '--start', '^A$', '--end', '^B$',
    ],
    qr/cannot be used together/,
    'append combined with force',
  ],
) {
  ($stdout, $stderr, $status) = run_onoff(
    "A\nB\n",
    @{$invalid_output_case->[0]},
  );
  is($status, 2, "$invalid_output_case->[2] is rejected");
  like($stderr, $invalid_output_case->[1], "$invalid_output_case->[2] is explained");
}

my $collision_file = File::Spec->catfile($routing_root, 'collision.txt');
open my $collision_handle, '>', $collision_file or die $!;
print {$collision_handle} "BEGIN\ninside\nEND\n";
close $collision_handle or die $!;
($stdout, $stderr, $status) = run_onoff(
  undef,
  '--output-dir', $routing_root,
  '--rule', 'collision', '--start', '^BEGIN$', '--end', '^END$',
  '--output', 'collision.txt',
  $collision_file,
);
is($status, 2, 'an input/output path collision is rejected');
like($stderr, qr/also an input file/, 'the input/output collision is explained');
is(
  read_text_file($collision_file),
  "BEGIN\ninside\nEND\n",
  'an input file is unchanged after collision rejection',
);

my $interactive_root = tempdir(CLEANUP => 1);
my $responses_file = File::Spec->catfile($interactive_root, 'responses.txt');
sub write_responses {
  my @responses = @_;
  open my $handle, '>', $responses_file
    or die "Cannot write '$responses_file': $!";
  print {$handle} join("\n", @responses), "\n";
  close $handle or die "Cannot close '$responses_file': $!";
}

my $interactive_input = <<'TEXT';
heading
before first
BEGIN
first
END
between
BEGIN
second
END
TEXT

write_responses('no', 'yes');
($stdout, $stderr, $status) = run_onoff(
  $interactive_input,
  '--interactive', '--responses', $responses_file,
  '--start', '^BEGIN$', '--end', '^END$',
);
is(
  $stdout,
  "BEGIN\nsecond\nEND\n",
  'interactive review can reject one range and accept a later range',
);
like(
  $stderr,
  qr/Candidate range: <stdin>:3 \(rule default\).*before first.*BEGIN/s,
  'the review prompt identifies the candidate and shows nearby context',
);
unlike($stdout, qr/Start printing/, 'interactive prompts never enter standard output');
is($status, 0, 'an accepted interactive range succeeds');

write_responses('no', 'yes');
($stdout, $stderr, $status) = run_onoff(
  $interactive_input,
  '--interactive', '--responses', $responses_file,
  '--start', '^BEGIN$', '--end', '^END$', '--lead', '1',
);
is(
  $stdout,
  "between\nBEGIN\nsecond\nEND\n",
  'rejecting a range discards its pending lead context',
);

write_responses('all');
($stdout, $stderr, $status) = run_onoff(
  $interactive_input,
  '--interactive', '--responses', $responses_file,
  '--start', '^BEGIN$', '--end', '^END$',
);
is(
  $stdout,
  "BEGIN\nfirst\nEND\nBEGIN\nsecond\nEND\n",
  'all accepts the current and remaining candidate ranges',
);
my $prompt_count = () = $stderr =~ /Start printing\?/g;
is($prompt_count, 1, 'all suppresses later prompts');

write_responses('quit');
($stdout, $stderr, $status) = run_onoff(
  $interactive_input,
  '--interactive', '--responses', $responses_file,
  '--start', '^BEGIN$', '--end', '^END$',
);
is($stdout, '', 'quit stops before printing the candidate range');
is($status, 1, 'quitting before a selection returns the no-selection status');

($stdout, $stderr, $status) = run_onoff(
  $interactive_input,
  '--interactive', '--start', '^BEGIN$', '--end', '^END$',
);
is($status, 2, 'interactive mode refuses a non-terminal input environment');
like(
  $stderr,
  qr/requires a terminal or --responses FILE/,
  'the non-terminal diagnostic recommends the explicit response source',
);

for my $invalid_interactive_case (
  [
    ['--responses', $responses_file, '--start', '^BEGIN$', '--end', '^END$'],
    qr/--responses requires --interactive/,
    'responses without interactive mode',
  ],
  [
    ['--interactive', '--responses', $responses_file, '--regexp', '^BEGIN$'],
    qr/requires a start\/end range/,
    'interactive review without a range',
  ],
  [
    [
      '--interactive', '--responses', $responses_file, '--list-ranges',
      '--start', '^BEGIN$', '--end', '^END$',
    ],
    qr/cannot be combined with --list-ranges/,
    'interactive review combined with list-ranges',
  ],
) {
  ($stdout, $stderr, $status) = run_onoff(
    $interactive_input,
    @{$invalid_interactive_case->[0]},
  );
  is($status, 2, "$invalid_interactive_case->[2] is rejected");
  like(
    $stderr,
    $invalid_interactive_case->[1],
    "$invalid_interactive_case->[2] is explained",
  );
}

done_testing();
