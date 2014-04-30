#!perl -wT

use strict;
use warnings;
use Test::Most tests => 23;
use Test::NoWarnings;

BEGIN {
	use_ok('CGI::Info');
}

ALLOWED: {
	$ENV{'GATEWAY_INTERFACE'} = 'CGI/1.1';
	$ENV{'REQUEST_METHOD'} = 'GET';

	$ENV{'QUERY_STRING'} = 'foo=bar&fred=wilma';
	my %allowed = ('fred' => undef);
	my $i = new_ok('CGI::Info');
	my %p = %{$i->params({allow => \%allowed})};
	ok(!exists($p{foo}));
	ok($p{fred} eq 'wilma');
	ok($i->as_string() eq 'fred=wilma');

	$ENV{'QUERY_STRING'} = 'foo=bar&fred=wilma&foo=baz';
	%allowed = ('foo' => undef);
	$i = new_ok('CGI::Info' => [
		allow => \%allowed
	]);
	%p = %{$i->params()};
	ok($p{foo} eq 'bar,baz');
	ok(!exists($p{fred}));
	ok($i->as_string() eq 'foo=bar,baz');

	# Reading twice should yield the same result
	%p = %{$i->params()};
	ok($p{foo} eq 'bar,baz');

	%allowed = ('foo' => qr(\d+));
	$i = new_ok('CGI::Info' => [
		allow => \%allowed
	]);
	%p = %{$i->params()};
	ok(!exists($p{foo}));
	ok(!exists($p{fred}));
	ok($i->as_string() eq '');

	$ENV{'QUERY_STRING'} = 'foo=123&fred=wilma';

	$i = new_ok('CGI::Info' => [
		allow => \%allowed
	]);
	%p = %{$i->params()};
	ok($p{foo} eq '123');
	ok(!exists($p{fred}));
	ok($i->as_string() eq 'foo=123');

	%allowed = ('foo' => qr([a-z]+));
	$i = new_ok('CGI::Info' => [
		allow => \%allowed
	]);
	%p = %{$i->params()};
	ok(!exists($p{foo}));
	ok(!exists($p{fred}));
	ok($i->as_string() eq '');
}
