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
  "<stdin>\t2\t4\n<stdin>\t6\tEOF\n",
  'list-ranges reports completed and unterminated logical ranges',
);
is($status, 0, 'list-ranges succeeds when ranges were found');

($stdout, $stderr, $status) = run_onoff(
  "zero\nmatch\ntwo\n", '--regexp', '^match$', '--list-ranges',
);
is($stdout, "<stdin>\t2\t2\n", 'list-ranges reports individual matches');

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
  "<stdin>\t3\t3\n",
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
  "<stdin>\t3\tEOF\n",
  'list-ranges reports an unterminated exclusive-start range',
);

done_testing();
