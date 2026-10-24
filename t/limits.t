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

done_testing();
