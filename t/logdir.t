#!perl -w

use strict;
use warnings;
use Test::Most tests => 13;
use Test::NoWarnings;

BEGIN {
	require_ok('CGI::Info');
}

PATHS: {
	delete $ENV{'LOGDIR'};

	my $i = new_ok('CGI::Info');
	my $dir = $i->logdir();
	ok(defined($dir));
	diag($dir);
	ok(-w $dir);
	ok(-d $dir);

	ok($i->logdir('.') eq '.');
	ok($i->logdir() eq '.');

	$dir = CGI::Info::logdir();
	ok(defined($dir));
	diag($dir);
	ok(-w $dir);
	ok(-d $dir);
}

# Collecting the candidates in a foreach list aliases a %ENV element, which
# vivifies it: a plain logdir() call must not leave LOGDIR in the environment.
NO_ENV_LEAK: {
	delete $ENV{'LOGDIR'};

	my $i = new_ok('CGI::Info');
	$i->logdir();
	ok(!defined($ENV{'LOGDIR'}), 'logdir() does not add LOGDIR to the environment');
}
