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

done_testing();
