#!/usr/bin/env perl

use strict;
use warnings;
use Test::Most;
use File::Spec;
use File::Temp qw(tempdir);

BEGIN { use_ok('CGI::Info') }

# Setup for tests
my $info;
my $upload_dir = tempdir(CLEANUP => 1);

subtest 'Allowed Parameters Regex' => sub {
	local %ENV = (
		GATEWAY_INTERFACE => 'CGI/1.1',
		REQUEST_METHOD => 'GET',
		QUERY_STRING => 'allowed_param=123&disallowed_param=evil',
	);

	$info = CGI::Info->new(allow => { allowed_param => qr/^\d{3}$/ });
	my $params = $info->params();

	is_deeply(
		$params,
		{ allowed_param => '123' },
		'Only allowed parameters are present'
	);
	cmp_ok($info->status(), '==', 422, 'Status is not OK when disallowed params are used');
};

subtest 'Allow Parameters Rules' => sub {
	local %ENV = (
		GATEWAY_INTERFACE => 'CGI/1.1',
		REQUEST_METHOD => 'GET',
		QUERY_STRING => 'username=test_user&email=test@example.com&age=30&bio=a+test+bio&ip_address=192.168.1.1'
	);

	my $allowed = {
		username => { type => 'string', min => 3, max => 50, matches => qr/^[a-zA-Z0-9_]+$/ },
		email => { type => 'string', matches => qr/^[^@]+@[^@]+\.[^@]+$/ },
		age => { type => 'integer', min => 0, max => 150 },
		bio => { type => 'string', optional => 1 },
		ip_address => { type => 'string', matches => qr/^(?:[0-9]{1,3}\.){3}[0-9]{1,3}$/ }, #Basic IPv4 validation
	};

	$info = CGI::Info->new(allow => $allowed);
	my $params = $info->params();
	diag(Data::Dumper->new([$params])->Dump()) if($ENV{'TEST_VERBOSE'});

	is_deeply(
		$params,
		{
			'username' => 'test_user',
			'email' => 'test@example.com',
			'age' => 30,
			'bio' => 'a test bio',
			'ip_address' => '192.168.1.1',
		},
		'Command line parameters parsed correctly'
	);
};

subtest 'SQL Injection Detection' => sub {
	local %ENV = (
		GATEWAY_INTERFACE => 'CGI/1.1',
		REQUEST_METHOD => 'GET',
		QUERY_STRING => 'username=nigel%27+OR+%271%27%3D%271',
	);

	$info = new_ok('CGI::Info');
	my $params = $info->params();

	ok(!defined $params, 'SQL injection attempt blocked');
	is($info->status(), 403, 'Status set to 403 Forbidden');
};

subtest 'XSS Sanitization' => sub {
	local %ENV = (
		GATEWAY_INTERFACE => 'CGI/1.1',
		REQUEST_METHOD => 'GET',
		QUERY_STRING => 'comment=<script>alert("xss")</script>',
	);

	$info = new_ok('CGI::Info');
	my $params = $info->params();

	# is(
		# $params->{comment},
		# '&lt;script&gt;alert(&quot;xss&quot;)&lt;/script&gt;',
		# 'XSS content sanitized'
	# );
	ok(!defined $params, 'XSS injection attempt blocked');
	is($info->status(), 403, 'Status set to 403 Forbidden');
};

subtest 'Directory Traversal Prevention' => sub {
	local %ENV = (
		GATEWAY_INTERFACE => 'CGI/1.1',
		REQUEST_METHOD => 'GET',
		QUERY_STRING => 'file=../../etc/passwd',
	);

	$info = new_ok('CGI::Info');
	my $params = $info->params();

	ok(!defined $params, 'Directory traversal attempt blocked');
	is($info->status(), 403, 'Status set to 403 Forbidden');
};

subtest 'Upload Directory Validation' => sub {
	local %ENV = (
		GATEWAY_INTERFACE => 'CGI/1.1',
		REQUEST_METHOD => 'POST',
		CONTENT_TYPE => 'multipart/form-data; boundary=12345',
		CONTENT_LENGTH => 100,
		C_DOCUMENT_ROOT => $upload_dir,
	);

	# Invalid upload_dir (not absolute)
	$info = CGI::Info->new(upload_dir => 'tmp');
	$info->params();
	is($info->status(), 500, 'Invalid upload_dir rejected');

	# Valid upload_dir
	$info = CGI::Info->new(upload_dir => $upload_dir);
	local *STDIN;
	open STDIN, '<', \"--12345\nContent-Disposition: form-data; name=\"file\"; filename=\"test.txt\"\n\nContent\n--12345--";
	my $params = $info->params();

	ok($params->{file} =~ /test\.txt/, 'File uploaded to valid directory');
};

subtest 'Parameter Sanitization' => sub {
	local %ENV = (
		GATEWAY_INTERFACE => 'CGI/1.1',
		REQUEST_METHOD => 'GET',
		QUERY_STRING => 'key%00=evil%00data&value=valid+data',
	);

	$info = new_ok('CGI::Info');
	my $params = $info->params();

	is($params->{key}, 'evildata', 'NUL bytes in key removed');
	is($params->{value}, 'valid data', 'Spaces correctly decoded');
};

subtest 'Max Upload Size Enforcement' => sub {
	local %ENV = (
		GATEWAY_INTERFACE => 'CGI/1.1',
		REQUEST_METHOD => 'POST',
		CONTENT_TYPE => 'application/x-www-form-urlencoded',
		CONTENT_LENGTH => 1024 * 1024 * 600,	# 600MB
	);

	$info = CGI::Info->new(max_upload => 500 * 1024);	# 500KB
	$info->params();

	is($info->status(), 413, 'Status set to 413 Payload Too Large');
};

subtest 'Command Line Parameters' => sub {
	local @ARGV = ('--mobile', 'param1=value1', 'param2=value2');
	$info = new_ok('CGI::Info');
	my $params = $info->params();

	is_deeply(
		$params,
		{ param1 => 'value1', param2 => 'value2' },
		'Command line parameters parsed correctly'
	);
	ok($info->is_mobile, 'Mobile flag set from command line');
};

done_testing();
