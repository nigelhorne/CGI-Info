#!/usr/bin/env perl

use strict;
use warnings;

use Test::More;
use File::Temp qw(tempdir);
use CGI::Info;

END { CGI::Info->reset() }

sub multipart_body {
	my ($boundary, @parts) = @_;

	my $body = '';
	foreach my $part (@parts) {
		$body .= "--$boundary\n$part\n";
	}
	$body .= "--$boundary--\n";

	return $body;
}

subtest 'constructor defaults and overrides' => sub {
	my $info = CGI::Info->new();

	is($info->{max_params}, 1000, 'max_params defaults to 1000');
	is($info->{max_parts}, 100, 'max_parts defaults to 100');
	is($info->{max_part_headers}, 20, 'max_part_headers defaults to 20');
	is($info->{max_nesting_depth}, 8, 'max_nesting_depth defaults to 8');
	ok(!defined($info->{max_body_size}), 'max_body_size defaults to max_upload_size');

	my $custom = CGI::Info->new(
		max_body_size     => 64,
		max_params        => 2,
		max_parts         => 3,
		max_part_headers  => 4,
		max_nesting_depth => 5,
	);
	is($custom->{max_body_size}, 64, 'max_body_size can be overridden');
	is($custom->{max_params}, 2, 'max_params can be overridden');
	is($custom->{max_parts}, 3, 'max_parts can be overridden');
	is($custom->{max_part_headers}, 4, 'max_part_headers can be overridden');
	is($custom->{max_nesting_depth}, 5, 'max_nesting_depth can be overridden');
};

subtest 'limits can be configured from the environment' => sub {
	local %ENV = (
		CGI__Info__max_params        => 3,
		CGI__Info__max_nesting_depth => 2,
	);

	my $info = CGI::Info->new();
	is($info->{max_params}, 3, 'max_params read from the environment');
	is($info->{max_nesting_depth}, 2, 'max_nesting_depth read from the environment');
};

subtest 'max_body_size caps declared and pre-read bodies' => sub {
	local %ENV = (
		GATEWAY_INTERFACE => 'CGI/1.1',
		REQUEST_METHOD    => 'POST',
		CONTENT_TYPE      => 'application/x-www-form-urlencoded',
		CONTENT_LENGTH    => 6,
	);
	local $CGI::Info::stdin_data;
	CGI::Info->reset();
	$CGI::Info::stdin_data = 'a=1234';

	my $info = CGI::Info->new(max_body_size => 5);
	my $params = eval { $info->params() };
	ok(!defined($params), 'declared body over max_body_size is rejected');
	is($info->status(), 413, 'body over max_body_size returns 413');

	$CGI::Info::stdin_data = 'a=1234';
	my $allowed = CGI::Info->new(max_body_size => 6);
	$params = eval { $allowed->params() };
	is($params->{a}, '1234', 'body exactly at max_body_size is accepted');

	# The declared length can lie; the pre-populated body must still be capped.
	local %ENV = (
		GATEWAY_INTERFACE => 'CGI/1.1',
		REQUEST_METHOD    => 'POST',
		CONTENT_TYPE      => 'application/x-www-form-urlencoded',
		CONTENT_LENGTH    => 3,
	);
	$CGI::Info::stdin_data = 'abcdefgh';
	my $actual = CGI::Info->new(max_body_size => 5);
	$params = eval { $actual->params() };
	ok(!defined($params), 'pre-read body over max_body_size is rejected');
	is($actual->status(), 413, 'actual body over max_body_size returns 413');
};

subtest 'max_params caps the number of raw parameters' => sub {
	local %ENV = (
		GATEWAY_INTERFACE => 'CGI/1.1',
		REQUEST_METHOD    => 'GET',
		QUERY_STRING      => 'a=1&b=2&c=3',
	);
	CGI::Info->reset();

	my $info = CGI::Info->new(max_params => 2);
	my $params = eval { $info->params() };
	ok(!defined($params), 'more than max_params is rejected');
	is($info->status(), 413, 'too many parameters returns 413');

	$ENV{QUERY_STRING} = 'a=1&b=2';
	my $allowed = CGI::Info->new(max_params => 2);
	$params = eval { $allowed->params() };
	is_deeply($params, { a => '1', b => '2' }, 'exactly max_params is accepted');
};

subtest 'max_nesting_depth caps bracketed parameter names' => sub {
	local %ENV = (
		GATEWAY_INTERFACE => 'CGI/1.1',
		REQUEST_METHOD    => 'GET',
		QUERY_STRING      => 'a[b][c]=1',
	);
	CGI::Info->reset();

	my $info = CGI::Info->new(max_nesting_depth => 1);
	my $params = eval { $info->params() };
	ok(!defined($params), 'nesting deeper than max_nesting_depth is rejected');
	is($info->status(), 413, 'deeply nested parameter returns 413');

	my $allowed = CGI::Info->new(max_nesting_depth => 2);
	$params = eval { $allowed->params() };
	ok(defined($params) && defined($params->{'a[b][c]'}), 'depth at the limit is accepted');

	$ENV{QUERY_STRING} = 'a[b][c][d]=1';
	my $too_deep = CGI::Info->new(max_nesting_depth => 2);
	$params = eval { $too_deep->params() };
	ok(!defined($params), 'depth above the limit is rejected');
};

subtest 'multipart part count is capped' => sub {
	my $upload_dir = tempdir(CLEANUP => 1);
	my $body = multipart_body('BOUND',
		"Content-Disposition: form-data; name=\"a\"\n\n1",
		"Content-Disposition: form-data; name=\"b\"\n\n2",
	);

	local %ENV = (
		GATEWAY_INTERFACE => 'CGI/1.1',
		REQUEST_METHOD    => 'POST',
		CONTENT_TYPE      => 'multipart/form-data; boundary=BOUND',
		CONTENT_LENGTH    => length($body),
	);
	CGI::Info->reset();
	local *STDIN;
	open STDIN, '<', \$body or die "Can't open scalar handle: $!";

	my $info = CGI::Info->new(upload_dir => $upload_dir, max_parts => 1);
	my $params = eval { $info->params() };
	ok(!defined($params), 'more than max_parts is rejected');
	is($info->status(), 413, 'too many multipart parts returns 413');
};

subtest 'multipart header count per part is capped' => sub {
	my $upload_dir = tempdir(CLEANUP => 1);
	my $body = multipart_body('BOUND',
		"Content-Disposition: form-data; name=\"a\"\nX-One: 1\nX-Two: 2\n\nvalue",
	);

	local %ENV = (
		GATEWAY_INTERFACE => 'CGI/1.1',
		REQUEST_METHOD    => 'POST',
		CONTENT_TYPE      => 'multipart/form-data; boundary=BOUND',
		CONTENT_LENGTH    => length($body),
	);
	CGI::Info->reset();
	local *STDIN;
	open STDIN, '<', \$body or die "Can't open scalar handle: $!";

	my $info = CGI::Info->new(upload_dir => $upload_dir, max_part_headers => 2);
	my $params = eval { $info->params() };
	ok(!defined($params), 'more than max_part_headers is rejected');
	is($info->status(), 413, 'too many part headers returns 413');
};

subtest 'multipart nesting depth is capped' => sub {
	my $upload_dir = tempdir(CLEANUP => 1);
	my $body = multipart_body('BOUND',
		"Content-Disposition: form-data; name=\"a[b][c]\"\n\nvalue",
	);

	local %ENV = (
		GATEWAY_INTERFACE => 'CGI/1.1',
		REQUEST_METHOD    => 'POST',
		CONTENT_TYPE      => 'multipart/form-data; boundary=BOUND',
		CONTENT_LENGTH    => length($body),
	);
	CGI::Info->reset();
	local *STDIN;
	open STDIN, '<', \$body or die "Can't open scalar handle: $!";

	my $info = CGI::Info->new(upload_dir => $upload_dir, max_nesting_depth => 1);
	my $params = eval { $info->params() };
	ok(!defined($params), 'deeply nested multipart name is rejected');
	is($info->status(), 413, 'deeply nested multipart name returns 413');
};

subtest 'per-call max_body_size overrides the constructor' => sub {
	local %ENV = (
		GATEWAY_INTERFACE => 'CGI/1.1',
		REQUEST_METHOD    => 'POST',
		CONTENT_TYPE      => 'application/x-www-form-urlencoded',
		CONTENT_LENGTH    => 6,
	);
	local $CGI::Info::stdin_data;
	CGI::Info->reset();
	$CGI::Info::stdin_data = 'a=1234';

	my $info = CGI::Info->new(max_body_size => 100);
	my $params = eval { $info->params(max_body_size => 5) };
	ok(!defined($params), 'per-call max_body_size rejects an oversized body');
	is($info->status(), 413, 'per-call max_body_size returns 413');
	is($info->{max_body_size}, 100, 'per-call max_body_size does not change the instance');

	$CGI::Info::stdin_data = 'a=1234';
	$params = eval { $info->params(max_body_size => 6) };
	is($params->{a}, '1234', 'per-call max_body_size at the limit is accepted');
};

subtest 'per-call max_params overrides the constructor and bypasses the cache' => sub {
	local %ENV = (
		GATEWAY_INTERFACE => 'CGI/1.1',
		REQUEST_METHOD    => 'GET',
		QUERY_STRING      => 'a=1&b=2&c=3',
	);
	CGI::Info->reset();

	my $info = CGI::Info->new(max_params => 3);
	my $params = eval { $info->params() };
	is_deeply($params, { a => '1', b => '2', c => '3' }, 'constructor limit accepts the request');

	$params = eval { $info->params(max_params => 2) };
	ok(!defined($params), 'per-call limit is applied to a cached request');
	is($info->status(), 413, 'per-call max_params returns 413');
	is($info->{max_params}, 3, 'per-call max_params does not change the instance');

	$params = eval { $info->params() };
	is_deeply($params, { a => '1', b => '2', c => '3' }, 'instance limit applies again on the next call');

	my $strict = CGI::Info->new(max_params => 1);
	$params = eval { $strict->params(max_params => 3) };
	is_deeply($params, { a => '1', b => '2', c => '3' }, 'per-call limit can relax a strict instance limit');
	is($strict->{max_params}, 1, 'relaxed per-call limit does not change the instance');
};

subtest 'limits hash applies a shared per-call profile' => sub {
	local %ENV = (
		GATEWAY_INTERFACE => 'CGI/1.1',
		REQUEST_METHOD    => 'GET',
		QUERY_STRING      => 'a=1&b=2&c=3',
	);
	CGI::Info->reset();

	my $info = CGI::Info->new(max_params => 3, max_nesting_depth => 2);
	my $params = eval { $info->params(limits => { max_params => 2, max_nesting_depth => 1 }) };
	ok(!defined($params), 'limits hash applies max_params');
	is($info->status(), 413, 'limits hash rejection returns 413');
	is($info->{max_params}, 3, 'limits hash does not change max_params on the instance');
	is($info->{max_nesting_depth}, 2, 'limits hash does not change max_nesting_depth on the instance');

	$params = eval { $info->params(limits => { max_params => 1 }, max_params => 3) };
	is_deeply($params, { a => '1', b => '2', c => '3' }, 'individual argument overrides the limits hash');
};

subtest 'limits hash applies to multipart parsing' => sub {
	my $upload_dir = tempdir(CLEANUP => 1);
	my $body = multipart_body('BOUND',
		"Content-Disposition: form-data; name=\"a\"\n\n1",
		"Content-Disposition: form-data; name=\"b\"\n\n2",
	);

	local %ENV = (
		GATEWAY_INTERFACE => 'CGI/1.1',
		REQUEST_METHOD    => 'POST',
		CONTENT_TYPE      => 'multipart/form-data; boundary=BOUND',
		CONTENT_LENGTH    => length($body),
	);
	CGI::Info->reset();
	local *STDIN;
	open STDIN, '<', \$body or die "Can't open scalar handle: $!";

	my $info = CGI::Info->new(upload_dir => $upload_dir, max_parts => 10);
	my $params = eval { $info->params(limits => { max_parts => 1 }) };
	ok(!defined($params), 'limits hash reaches multipart parsing');
	is($info->status(), 413, 'multipart limits hash rejection returns 413');
	is($info->{max_parts}, 10, 'multipart limits hash does not change the instance');
};

subtest 'limits hash is validated' => sub {
	local %ENV = (
		GATEWAY_INTERFACE => 'CGI/1.1',
		REQUEST_METHOD    => 'GET',
		QUERY_STRING      => 'a=1',
	);
	CGI::Info->reset();

	my $info = CGI::Info->new();

	my $ok = eval { $info->params(limits => 'strict'); 1 };
	ok(!$ok, 'a non-hash limits value is rejected');
	like($@, qr/limits must be a hash reference/, 'the error explains the limits type');

	$ok = eval { $info->params(limits => { max_parms => 2 }); 1 };
	ok(!$ok, 'an unknown limit name is rejected');
	like($@, qr/unknown complexity limit 'max_parms'/, 'the error names the unknown limit');

	$ok = eval { $info->params(limits => { max_params => 'lots' }); 1 };
	ok(!$ok, 'a non-integer value in limits is rejected');
	like($@, qr/max_params must be an integer/, 'the error names the invalid limit in the hash');
};

subtest 'per-call max_nesting_depth overrides the constructor' => sub {
	local %ENV = (
		GATEWAY_INTERFACE => 'CGI/1.1',
		REQUEST_METHOD    => 'GET',
		QUERY_STRING      => 'a[b][c]=1',
	);
	CGI::Info->reset();

	my $info = CGI::Info->new(max_nesting_depth => 2);
	my $params = eval { $info->params(max_nesting_depth => 1) };
	ok(!defined($params), 'per-call max_nesting_depth rejects a deeper name');
	is($info->status(), 413, 'per-call max_nesting_depth returns 413');
	is($info->{max_nesting_depth}, 2, 'per-call max_nesting_depth does not change the instance');

	$params = eval { $info->params(max_nesting_depth => 2) };
	ok(defined($params) && defined($params->{'a[b][c]'}), 'per-call max_nesting_depth at the limit is accepted');
};

subtest 'per-call max_parts overrides the constructor' => sub {
	my $upload_dir = tempdir(CLEANUP => 1);
	my $body = multipart_body('BOUND',
		"Content-Disposition: form-data; name=\"a\"\n\n1",
		"Content-Disposition: form-data; name=\"b\"\n\n2",
	);

	local %ENV = (
		GATEWAY_INTERFACE => 'CGI/1.1',
		REQUEST_METHOD    => 'POST',
		CONTENT_TYPE      => 'multipart/form-data; boundary=BOUND',
		CONTENT_LENGTH    => length($body),
	);
	CGI::Info->reset();
	local *STDIN;
	open STDIN, '<', \$body or die "Can't open scalar handle: $!";

	my $info = CGI::Info->new(upload_dir => $upload_dir, max_parts => 10);
	my $params = eval { $info->params(max_parts => 1) };
	ok(!defined($params), 'per-call max_parts rejects extra multipart parts');
	is($info->status(), 413, 'per-call max_parts returns 413');
	is($info->{max_parts}, 10, 'per-call max_parts does not change the instance');
};

subtest 'per-call max_part_headers overrides the constructor' => sub {
	my $upload_dir = tempdir(CLEANUP => 1);
	my $body = multipart_body('BOUND',
		"Content-Disposition: form-data; name=\"a\"\nX-One: 1\nX-Two: 2\n\nvalue",
	);

	local %ENV = (
		GATEWAY_INTERFACE => 'CGI/1.1',
		REQUEST_METHOD    => 'POST',
		CONTENT_TYPE      => 'multipart/form-data; boundary=BOUND',
		CONTENT_LENGTH    => length($body),
	);
	CGI::Info->reset();
	local *STDIN;
	open STDIN, '<', \$body or die "Can't open scalar handle: $!";

	my $info = CGI::Info->new(upload_dir => $upload_dir, max_part_headers => 10);
	my $params = eval { $info->params(max_part_headers => 2) };
	ok(!defined($params), 'per-call max_part_headers rejects extra part headers');
	is($info->status(), 413, 'per-call max_part_headers returns 413');
	is($info->{max_part_headers}, 10, 'per-call max_part_headers does not change the instance');
};

subtest 'XML element count is capped' => sub {
	my $xml = '<root><a>1</a><b>2</b></root>';

	local %ENV = (
		GATEWAY_INTERFACE => 'CGI/1.1',
		REQUEST_METHOD    => 'POST',
		CONTENT_TYPE      => 'text/xml; charset=utf-8',
		CONTENT_LENGTH    => length($xml),
	);
	CGI::Info->reset();
	local *STDIN;
	open STDIN, '<', \$xml or die "Can't open scalar handle: $!";

	my $info = CGI::Info->new(max_params => 3);
	my $params = eval { $info->params() };
	ok(defined($params) && ($params->{XML} eq $xml), 'XML at the element limit is accepted');

	my $strict = CGI::Info->new(max_params => 2);
	$params = eval { $strict->params() };
	ok(!defined($params), 'XML over the element limit is rejected');
	is($strict->status(), 413, 'too many XML elements returns 413');
};

subtest 'XML nesting depth is capped' => sub {
	my $xml = '<root><a><b/></a></root>';

	local %ENV = (
		GATEWAY_INTERFACE => 'CGI/1.1',
		REQUEST_METHOD    => 'POST',
		CONTENT_TYPE      => 'text/xml; charset=utf-8',
		CONTENT_LENGTH    => length($xml),
	);
	CGI::Info->reset();
	local *STDIN;
	open STDIN, '<', \$xml or die "Can't open scalar handle: $!";

	my $info = CGI::Info->new(max_nesting_depth => 3);
	my $params = eval { $info->params() };
	ok(defined($params) && ($params->{XML} eq $xml), 'XML at the nesting limit is accepted');

	my $strict = CGI::Info->new(max_nesting_depth => 2);
	$params = eval { $strict->params() };
	ok(!defined($params), 'XML deeper than the limit is rejected');
	is($strict->status(), 413, 'too deeply nested XML returns 413');
};

subtest 'XML complexity ignores declarations, comments, CDATA and quoted >' => sub {
	my $xml = q{<?xml version="1.0"?>}
		. q{<root note="1 > 0">}
		. q{<!-- <fake><deep> -->}
		. q{<![CDATA[<fake>]]>}
		. q{<item/>}
		. q{</root>};

	local %ENV = (
		GATEWAY_INTERFACE => 'CGI/1.1',
		REQUEST_METHOD    => 'POST',
		CONTENT_TYPE      => 'text/xml',
		CONTENT_LENGTH    => length($xml),
	);
	CGI::Info->reset();
	local *STDIN;
	open STDIN, '<', \$xml or die "Can't open scalar handle: $!";

	my $info = CGI::Info->new(max_params => 2, max_nesting_depth => 2);
	my $params = eval { $info->params() };
	ok(defined($params) && ($params->{XML} eq $xml), 'non-element markup does not count towards the limits');

	$params = eval { $info->params(limits => { max_params => 1 }) };
	ok(!defined($params), 'per-call limits apply to XML bodies');
	is($info->status(), 413, 'XML limits hash rejection returns 413');
};

subtest 'application/xml bodies use the XML path and limits' => sub {
	my $xml = '<root><a><b/></a></root>';

	my $parse = sub {
		my %limits = @_;

		local %ENV = (
			GATEWAY_INTERFACE => 'CGI/1.1',
			REQUEST_METHOD    => 'POST',
			CONTENT_TYPE      => 'application/xml; charset=utf-8',
			CONTENT_LENGTH    => length($xml),
		);
		CGI::Info->reset();
		local *STDIN;
		open STDIN, '<', \$xml or die "Can't open scalar handle: $!";

		my $info = CGI::Info->new(%limits);
		return ($info, eval { $info->params() });
	};

	my ($info, $params) = $parse->(max_params => 3, max_nesting_depth => 3);
	ok(defined($params) && ($params->{XML} eq $xml), 'application/xml body is stored under XML');
	is($info->status(), 200, 'valid application/xml leaves the status at 200');

	($info, $params) = $parse->(max_params => 2);
	ok(!defined($params), 'application/xml over the element limit is rejected');
	is($info->status(), 413, 'too many application/xml elements returns 413');

	($info, $params) = $parse->(max_nesting_depth => 2);
	ok(!defined($params), 'application/xml deeper than the limit is rejected');
	is($info->status(), 413, 'too deeply nested application/xml returns 413');
};

subtest 'per-call limits must be integers' => sub {
	local %ENV = (
		GATEWAY_INTERFACE => 'CGI/1.1',
		REQUEST_METHOD    => 'GET',
		QUERY_STRING      => 'a=1',
	);
	CGI::Info->reset();

	my $info = CGI::Info->new();
	my $error = eval { $info->params(max_params => 'lots'); 1 };
	ok(!$error, 'a non-integer per-call limit is rejected');
	like($@, qr/max_params must be an integer/, 'the error names the invalid limit');
};

done_testing();
