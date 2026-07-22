#!/usr/bin/env perl

use strict;
use warnings;

use Test::More;
use File::Spec;
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

done_testing();
