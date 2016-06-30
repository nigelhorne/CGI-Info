#!perl -w

use strict;

use Test::Most tests => 13;
use Test::Script;

my $stdout;
my $stderr;

script_compiles('bin/info.pl');
script_runs(['bin/info.pl', 'foo=bar'], { stdout => \$stdout, stderr => \$stderr });

ok($stdout =~ /Is_mobile: 0/m);
ok($stdout =~ /Is_robot: 0/m);
ok($stdout =~ /Is_search_engine: 0/m);
ok($stdout =~ /foo => bar/m);
ok($stderr eq '');

my $stdin = "fred=wilma\n";

script_runs(['bin/info.pl'], { stdin => \$stdin, stdout => \$stdout, stderr => \$stderr });

ok($stdout =~ /Is_mobile: 0/m);
ok($stdout =~ /Is_robot: 0/m);
ok($stdout =~ /Is_search_engine: 0/m);
ok($stdout =~ /fred => wilma/m);
ok($stderr eq '');
