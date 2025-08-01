#!perl -w

use strict;
use warnings;
use Test::Most tests => 204;
use File::Spec;
use lib 't/lib';
use MyLogger;

eval 'use autodie qw(:all)';	# Test for open/close failures

my $has_test_returns;

BEGIN {
	use_ok('CGI::Info');
	$has_test_returns = eval {
		require Test::Returns;
		Test::Returns->import(qw(returns_is));
		1;
	};
}

PARAMS: {
	$ENV{'GATEWAY_INTERFACE'} = 'CGI/1.1';
	$ENV{'REQUEST_METHOD'} = 'GET';
	$ENV{'QUERY_STRING'} = 'foo=bar';

	my $i = new_ok('CGI::Info');
	ok(!defined($i->messages()));
	ok($i->messages_as_string() eq '');
	my %p = %{$i->params()};

	SKIP: {
		skip 'Test::Returns not installed', 1 unless $has_test_returns;

		returns_is(\%p, { type => 'hashref', max => 1, min => 1 }, 'params returns a hash ref');
	}

	ok($p{foo} eq 'bar');
	ok(!defined($p{fred}));
	ok($i->as_string() eq 'foo=bar');
	cmp_ok($i->status(), '==', 200, 'Check HTTP status code');

	$ENV{'QUERY_STRING'} = '=bar';

	$i = new_ok('CGI::Info');
	ok(!defined($i->params()));
	ok($i->as_string() eq '');

	$ENV{'QUERY_STRING'} = 'foo=bar&fred=wilma';
	$i = new_ok('CGI::Info');
	%p = %{$i->params()};

	SKIP: {
		skip 'Test::Returns not installed', 1 unless $has_test_returns;

		returns_is(\%p, { type => 'hashref', max => 2, min => 2 }, 'params returns a hash ref');
	}

	ok($p{foo} eq 'bar');
	ok($p{fred} eq 'wilma');
	ok($i->as_string() eq 'foo=bar; fred=wilma');

	$ENV{'QUERY_STRING'} = 'name=nigel+horne';
	%p = %{new_ok('CGI::Info')->params()};
	ok($p{name} eq 'nigel horne');

	$ENV{'QUERY_STRING'} = 'name=nigel%2Bhorne';
	$i = new_ok('CGI::Info');
	%p = %{$i->params()};
	ok($p{name} eq 'nigel horne');

	$ENV{'QUERY_STRING'} = 'foo=bar&fred=wilma&foo=%3Dbaz';
	$i = new_ok('CGI::Info');
	%p = %{$i->params()};
	ok($p{foo} eq 'bar,=baz');
	ok($p{fred} eq 'wilma');
	ok($i->as_string() eq 'foo=bar,\\=baz; fred=wilma');
	ok($i->as_string(raw => 1) eq 'foo=bar,=baz; fred=wilma');

	%p = %{$i->params()};
	is($p{foo}, 'bar,=baz', 'Reading twice should yield the same result');

	$ENV{'QUERY_STRING'} = 'foo=bar&fred=wilma&foo=bar';
	$i = new_ok('CGI::Info');
	%p = %{$i->params()};
	is($p{foo}, 'bar', "Don't add if it's already there");
	ok($p{fred} eq 'wilma');
	ok($i->as_string() eq 'foo=bar; fred=wilma');

	$ENV{'QUERY_STRING'} = 'foo=&fred=wilma';
	$i = new_ok('CGI::Info');
	%p = %{$i->params()};
	ok(!defined($p{foo}));
	ok($p{fred} eq 'wilma');
	ok($i->as_string() eq 'fred=wilma');

	$ENV{'QUERY_STRING'} = 'foo=&fred=wilma&foo=bar';
	$i = new_ok('CGI::Info');
	%p = %{$i->params()};
	ok($p{foo} eq 'bar');
	ok($p{fred} eq 'wilma');
	cmp_ok($i->foo(), 'eq', 'bar', 'Test AUTOLOAD');
	ok($i->as_string() eq 'foo=bar; fred=wilma');

	$ENV{'QUERY_STRING'} = 'page=submit&country=Singapore&county=';
	$i = new_ok('CGI::Info');
	%p = %{$i->params()};
	diag(Data::Dumper->new([\%p])->Dump()) if($ENV{'TEST_VERBOSE'});
	cmp_ok(scalar(keys %p), '==', 2, 'Ignored county=');
	cmp_ok($p{'page'}, 'eq', 'submit', 'Parsed page=submit');
	cmp_ok($p{'country'}, 'eq', 'Singapore', 'Parsed country=Singapore');

	# Catch XSS attempts
	$ENV{'QUERY_STRING'} = 'foo=bar&fred=<script>alert(123)</script>';
	$i = new_ok('CGI::Info');
	# %p = %{$i->params()};
	# ok($p{fred} eq '&lt;script&gt;alert(123)&lt;/script&gt;');
	ok(!defined($i->params()));

	# SQL Injection is prevented
	$ENV{'QUERY_STRING'} = "foo=bar&userName=' OR '1'='1&fred=wilma";
	$i = new_ok('CGI::Info');
	ok(!defined($i->params()));

	# SQL Injection is prevented
	$ENV{'QUERY_STRING'} = "page=surnames&surname='Stock%20or%20(1,2\)=(SELECT*from(select%20name_const(CHAR(111,108,111,108,111,115,104,101,114\),1\),name_const(CHAR( <-- HERE 111,108,111,108,111,115,104,101,114\),1\)\)a\)%20--%20and%201%3D1'";
	$i = new_ok('CGI::Info');
	ok(!defined($i->params()));
	ok($i->as_string() eq '');
	cmp_ok($i->status(), '==', 403, 'SQL Injection generates 403 code');

	# Seen in vwf.log
	$ENV{'QUERY_STRING'} = 'entry=-4346" OR 1749\=1749 AND "dgiO"\="dgiO;page=people';
	$i = new_ok('CGI::Info');
	ok(!defined($i->params()));
	ok(!defined($i->entry()));
	ok($i->as_string() eq '');
	cmp_ok($i->status(), '==', 403, 'SQL Injection generates 403 code');

	$ENV{'QUERY_STRING'} = '<script>alert(123)</script>=wilma';
	$i = new_ok('CGI::Info');
	%p = %{$i->params()};
	ok($p{'&lt;script&gt;alert(123)&lt;/script&gt;'} eq 'wilma');

	$ENV{'QUERY_STRING'} = 'username=admin&password=foo';
	$i = new_ok('CGI::Info');
	%p = %{$i->params()};
	ok($p{'username'} eq 'admin');
	ok($p{'password'} eq 'foo');
	cmp_ok(scalar(keys %p), '==', 2, 'Params returns correct number of keys');

	$ENV{'QUERY_STRING'} = 'foo%41=%20bar';
	$i = new_ok('CGI::Info');
	my $p = $i->params();
	ok($p->{'fooA'} eq 'bar');
	ok($i->as_string() eq 'fooA=bar');

	delete $ENV{'QUERY_STRING'};
	$i = new_ok('CGI::Info');
	ok(!$i->params());

	$ENV{'REQUEST_METHOD'} = 'HEAD';
	$ENV{'QUERY_STRING'} = 'foo=b+ar&fred=wilma';
	$i = new_ok('CGI::Info');
	%p = %{$i->params()};
	ok($p{fred} eq 'wilma');
	ok($p{foo} eq 'b ar');

	$ENV{'REQUEST_METHOD'} = 'FOO';
	$i = new_ok('CGI::Info');

	local $SIG{__WARN__} = sub { die $_[0] };
	eval { $i->params() };
	ok($@ =~ /Use POST, GET or HEAD/);

	delete $ENV{'QUERY_STRING'};
	$ENV{'REQUEST_METHOD'} = 'GET';
	$i = new_ok('CGI::Info');
	ok(!defined($i->params()));
	ok($i->as_string() eq '');

	$ENV{'REQUEST_METHOD'} = 'POST';
	delete $ENV{'CONTENT_LENGTH'};
	$i = new_ok('CGI::Info');
	ok(!defined($i->params()));
	ok($i->as_string() eq '');

	my $input = 'foo=bar';
	$ENV{'CONTENT_LENGTH'} = length($input);

	open (my $fin, '<', \$input);
	local *STDIN = $fin;

	$i = new_ok('CGI::Info');
	%p = %{$i->params()};
	ok($p{foo} eq 'bar');	# Fails on Perl 5.6.2
	ok(!defined($p{fred}));
	ok($i->as_string() eq 'foo=bar');
	close $fin;

	# Creating a second object should give the same parameters, without
	# reading
	$i = new_ok('CGI::Info');
	%p = %{$i->params()};
	ok($p{foo} eq 'bar');
	ok(!defined($p{fred}));
	ok($i->as_string() eq 'foo=bar');

	# TODO: find and use a free filename, otherwise /tmp/hello.txt
	# will be overwritten if it exists
	$ENV{'CONTENT_TYPE'} = 'Multipart/form-data; boundary=-----xyz';
	$input = <<'EOF';
-------xyz
Content-Disposition: form-data; name="country"

44
-------xyz
Content-Disposition: form-data; name="datafile"; filename="hello.txt"
Content-Type: text/plain

Hello, World

-------xyz--
EOF
	$ENV{'CONTENT_LENGTH'} = length($input);

	open ($fin, '<', \$input);
	local *STDIN = $fin;

	CGI::Info->reset();	# Force stdin re-read
	my $tmpdir = File::Spec->tmpdir();
	if(!-w $tmpdir) {
		BAIL_OUT("Your temporary directory ' $tmpdir' isn't writable, fix your configuration and try again");
	}
	$i = new_ok('CGI::Info' => [
		upload_dir => $tmpdir
	]);
	%p = %{$i->params()};
	ok(defined($p{country}));
	ok($p{country} eq '44');
	ok($p{datafile} =~ /^hello.txt_.+/);
	my $filename = File::Spec->catfile($tmpdir, $p{datafile});
	ok(-e $filename);
	ok(-r $filename);
	unlink($filename);
	close $fin;

	$ENV{'REQUEST_METHOD'} = 'GET';
	CGI::Info->reset();	# Force stdin re-read
	$i = new_ok('CGI::Info');
	$i = new_ok('CGI::Info' => [
		upload_dir => $tmpdir
	]);
	$ENV{'QUERY_STRING'} = 'foo=bar';
	eval { %p = $i->params() };
	ok($@ =~ /Multipart.+ not supported for GET/);
	delete $ENV{'QUERY_STRING'};

	open ($fin, '<', \$input);
	local *STDIN = $fin;

	$ENV{'REQUEST_METHOD'} = 'POST';
	CGI::Info->reset();	# Force stdin re-read
	$i = new_ok('CGI::Info');
	%p = %{$i->params(upload_dir => $tmpdir)};
	ok(defined($p{country}));
	ok($p{country} eq '44');
	ok($p{datafile} =~ /^hello.txt_.+/);
	$filename = File::Spec->catfile($tmpdir, $p{datafile});
	ok(-e $filename) || diag("$filename doesn't exist");
	ok(-r $filename);
	unlink($filename);
	close $fin;

	$input = <<'EOF';
-------xyz
Content-Disposition: form-data; name="country"

44
-------xyz
Content-Disposition: form-data; name=".hidden"; filename="/.trojanhorse.js"
Content-Type: text/plain

I would do nasty things, but my upload will be disallowed

-------xyz--
EOF
	$ENV{'CONTENT_LENGTH'} = length($input);

	open ($fin, '<', \$input);
	local *STDIN = $fin;

	CGI::Info->reset();	# Force stdin re-read
	$i = new_ok('CGI::Info' => [
		upload_dir => $tmpdir
	]);
	eval { %p = %{$i->params()} };
	ok(defined($@));
	like($@, qr/Disallowing invalid filename/);
	ok(defined($p{country}));
	ok($p{country} == 44);
	ok($p{datafile} =~ /^hello.txt_.+/);
	$filename = File::Spec->catfile($tmpdir, $p{datafile});
	ok(!-e $filename);
	ok(!-r $filename);
	close $fin;

	$input = <<'EOF';
-------xyz
Content-Disposition: form-data; name="country"

44
-------xyz
Content-Disposition: form-data; name="datafile"; filename="hello.txt"
Content-Type: text/plain

Hello, World

-------xyz--
EOF
	$ENV{'CONTENT_LENGTH'} = length($input);

	open ($fin, '<', \$input);
	local *STDIN = $fin;

	CGI::Info->reset();	# Force stdin re-read
	$i = new_ok('CGI::Info' => [
		upload_dir => '/does_not_exist11',
	]);
	eval { %p = %{$i->params()} };
	ok($@ =~ /isn't a directory/);
	ok(defined($p{country}));
	ok($p{country} == 44);
	ok($p{datafile} =~ /^hello.txt_.+/);
	$filename = File::Spec->catfile($tmpdir, $p{datafile});
	ok(!-e $filename);
	ok(!-r $filename);
	close $fin;

	open ($fin, '<', \$input);
	local *STDIN = $fin;

	CGI::Info->reset();	# Force stdin re-read
	$i = new_ok('CGI::Info' => [
		upload_dir => undef,
	]);
	eval { %p = $i->params() };
	ok($@ =~ /Attempt to upload a file when upload_dir has not been set/);
	ok(defined($p{country}));
	ok($p{country} eq '44');
	ok($p{datafile} =~ /^hello.txt_.+/);
	$filename = File::Spec->catfile($tmpdir, $p{datafile});
	ok(!-e $filename);
	ok(!-r $filename);
	close $fin;

	SKIP: {
		# e.g. running as root, or on Windows
		skip 'Root directory is writable', 7 if(-w '/');
		open ($fin, '<', \$input);
		local *STDIN = $fin;

		CGI::Info->reset();	# Force stdin re-read
		$i = new_ok('CGI::Info' => [
			upload_dir => '/',
		]);
		eval { %p = $i->params() };
		ok($@ =~ /isn't writeable/);
		ok(defined($p{country}));
		ok($p{country} eq '44');
		ok($p{datafile} =~ /^hello.txt_.+/);
		$filename = File::Spec->catfile($tmpdir, $p{datafile});
		ok(!-e $filename);
		ok(!-r $filename);
		close $fin;
	}

	open ($fin, '<', \$input);
	local *STDIN = $fin;

	my $script_path = $i->script_path();
	CGI::Info->reset();	# Force stdin re-read
	$i = new_ok('CGI::Info' => [
		upload_dir => $script_path,
	]);
	eval { %p = $i->params() };
	ok($@ =~ /isn't a directory/);
	ok(defined($p{country}));
	ok($p{country} eq '44');
	ok($p{datafile} =~ /^hello.txt_.+/);
	$filename = File::Spec->catfile($tmpdir, $p{datafile});
	ok(!-e $filename);
	ok(!-r $filename);
	close $fin;

	open ($fin, '<', \$input);
	local *STDIN = $fin;
	$script_path = $i->script_path();
	CGI::Info->reset();	# Force stdin re-read
	$i = new_ok('CGI::Info' => [
		upload_dir => '.',
	]);
	eval { %p = $i->params() };
	ok($@ =~ /isn't a full pathname/);
	ok(defined($p{country}));
	ok($p{country} eq '44');
	ok($p{datafile} =~ /^hello.txt_.+/);
	$filename = File::Spec->catfile($tmpdir, $p{datafile});
	ok(!-e $filename);
	ok(!-r $filename);
	close $fin;

	$ENV{'CONTENT_TYPE'} = 'xyzzy';
	open ($fin, '<', \$input);
	local *STDIN = $fin;

	CGI::Info->reset();	# Force stdin re-read
	$i = new_ok('CGI::Info' => [
		upload_dir => $tmpdir
	]);
	eval { %p = $i->params() };
	ok($@ =~ /POST: Invalid or unsupported content type: xyzzy/);
	ok(defined($p{country}));
	ok($p{country} eq '44');
	ok($p{datafile} =~ /^hello.txt_.+/);
	$filename = File::Spec->catfile($tmpdir, $p{datafile});
	ok(!-e $filename);
	ok(!-r $filename);
	close $fin;

	$ENV{'CONTENT_TYPE'} = 'Multipart/form-data; boundary=-----xyz';
	$input = <<'EOF';
-------xyz
Content-Disposition: form-data; name="country"

44
-------xyz
Content-Disposition: form-data; name="datafile"; filename="../../../passwd"
Content-Type: text/plain

Hello, World

-------xyz--
EOF
	open ($fin, '<', \$input);
	local *STDIN = $fin;
	$script_path = $i->script_path();
	CGI::Info->reset();	# Force stdin re-read
	$i = new_ok('CGI::Info' => [
		upload_dir => $tmpdir
	]);
	eval { %p = $i->params() };
	diag($@);
	ok($@ =~ /Disallowing invalid filename/);
	ok(defined($p{country}));
	ok($p{country} eq '44');
	ok($p{datafile} =~ /^hello.txt_.+/);
	$filename = File::Spec->catfile($tmpdir, $p{datafile});
	ok(!-e $filename);
	ok(!-r $filename);
	close $fin;

	$ENV{'REQUEST_METHOD'} = 'DELETE';
	$ENV{'QUERY_STRING'} = 'laleh=tulip';
	$i = new_ok('CGI::Info');
	eval { %p = $i->params() };
	cmp_ok(scalar(keys(%p)), '==', 0, 'params: DELETE mode is not supported');
	cmp_ok($i->status(), '==', 405, 'params: DELETE sets HTTP status to 405');

	# Check params are read from command line arguments for testing scripts
	delete $ENV{'GATEWAY_INTERFACE'};
	delete $ENV{'REQUEST_METHOD'};
	delete $ENV{'QUERY_STRING'};
	@ARGV = ('foo=bar', 'fred=wilma' );
	$i = new_ok('CGI::Info');
	%p = %{$i->params(logger => MyLogger->new())};
	ok($p{fred} eq 'wilma');
	ok($i->as_string() eq 'foo=bar; fred=wilma');
	ok(!$i->is_mobile());

	@ARGV= ('file=/../../../../etc/passwd%00');
	$i = new_ok('CGI::Info');
	dies_ok { %p = %{$i->params()} };	# Warns because logger isn't set
	like($@, qr/Blocked directory traversal attack/);
	diag(Data::Dumper->new([$i->messages()])->Dump()) if($ENV{'TEST_VERBOSE'});
	like(
		$i->messages()->[1]->{'message'},
		qr/^Blocked directory traversal attack for 'file'/,
		'Warning generated for disallowed parameter'
	);
	cmp_ok($i->messages()->[1]->{'level'}, 'eq', 'warn');
	like($i->messages_as_string(), qr/Blocked directory traversal attack/, 'messages_as_string works');

	@ARGV= ('file=/etc/passwd%00');
	$i = new_ok('CGI::Info');
	lives_ok { %p = %{$i->params()}; };
	like($p{'file'}, qr/passwd$/, 'strip NUL byte poison');

	@ARGV = ('--mobile', 'foo=bar', 'fred=wilma' );
	$i = new_ok('CGI::Info');
	%p = %{$i->params()};
	ok($p{fred} eq 'wilma');
	ok($i->as_string() eq 'foo=bar; fred=wilma');
	ok($i->is_mobile());

	@ARGV = ('--tablet', 'foo=bar', 'fred=wilma' );
	$i = new_ok('CGI::Info');
	%p = %{$i->params()};
	ok($p{fred} eq 'wilma');
	ok($i->as_string() eq 'foo=bar; fred=wilma');
	ok(!$i->is_mobile());
	ok($i->is_tablet());

	@ARGV = ('--search-engine', 'foo=bar', 'fred=wilma' );
	$i = new_ok('CGI::Info');
	%p = %{$i->params()};
	ok($p{fred} eq 'wilma');
	ok($i->as_string() eq 'foo=bar; fred=wilma');
	ok(!$i->is_mobile());
	ok($i->is_search_engine());

	@ARGV = ('--robot', 'foo=bar', 'fred=wilma' );
	$i = new_ok('CGI::Info');
	%p = %{$i->params()};
	ok($p{fred} eq 'wilma');
	ok($i->as_string() eq 'foo=bar; fred=wilma');
	ok(!$i->is_mobile());
	ok(!$i->is_search_engine());
	ok($i->is_robot());
	ok($i->status() == 200);

	eval {
		$i->reset();
	};

	ok($@ =~ /Reset is a class method/);

	delete $ENV{'CONTENT_TYPE'};
	delete $ENV{'CONTENT_LENGTH'};
	$ENV{'GATEWAY_INTERFACE'} = 'CGI/1.1';
	$ENV{'REQUEST_METHOD'} = 'GET';

	# Test that a message about SQL injection is logged
	{
		local $ENV{'QUERY_STRING'} = 'nan=lost&redir=-8717%22%20OR%208224%3D6013--%20ETLn';
		local $ENV{'REMOTE_ADDR'} = '127.0.0.1';
		my $mess = 'mess is undefined';

		{
			package MockLogger;

			sub new { bless { }, shift }
			sub trace { }
			sub debug { }
			sub warn { shift; $mess = (ref($_[0]) eq 'ARRAY') ? join(' ', @{$_[0]}) : join(' ' , @_) }
		}

		my $info = new_ok('CGI::Info');
		my $params = $info->params(logger => MockLogger->new());
		like($mess, qr/SQL injection attempt blocked/, 'Correct message when blocking SQL injection');

		cmp_ok($info->status(), '==', 403, 'SQL injection causes HTTP code 403');
	}

	$ENV{'QUERY_STRING'} = 'country=/etc/passwd&page=by_location';
	$i = new_ok('CGI::Info');

	my $allow = {
		'entry' => undef,
		'country' => qr/^[A-Z\s]+$/i,	# Must start with a letter
		'county' => qr/^[A-Z\s]+$/i,
		'string' => undef,
		'page' => 'by_location',
		'lang' => qr/^[A-Z]{2}/i,
	};

	my %params = %{$i->params({ allow => $allow })};

	cmp_ok($params{'page'}, 'eq', 'by_location', 'allow lets through legal parameters');
	is($params{'country'}, undef, 'allow blocks illegal parameters');
	cmp_ok($i->status(), '==', 422, 'HTTP Unprocessable Content');
}
