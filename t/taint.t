#!perl -w

use strict;
use warnings;
use Test::Most tests => 7;
use Test::Needs 'Test::Taint';
use Taint::Runtime qw($TAINT taint_env taint_start);

BEGIN {
	taint_start();
	$TAINT = 1;
	taint_env();
}

Test::Taint->import();
if($ENV{'AUTHOR_TESTING'}) {
	taint_checking_ok();
} else {
	ok(1);
}
require_ok('CGI::Info');

$ENV{'C_DOCUMENT_ROOT'} = $ENV{'HOME'};
delete $ENV{'DOCUMENT_ROOT'};

my $i = new_ok('CGI::Info');
untainted_ok($i->tmpdir());
untainted_ok($i->script_name());
untainted_ok($i->tmpdir() . '/' . $i->script_name() . '.foo');
untainted_ok($i->script_path());
