#!perl -w

use strict;
use warnings;

use Carp;
use Test::Carp;
use Test::Most tests => 15;

BEGIN {
	use_ok('CGI::Info');
}

CARP: {
	local $ENV{'GATEWAY_INTERFACE'} = 'CGI/1.1';

	does_carp_that_matches(
		sub {
			local $ENV{'REQUEST_METHOD'} = 'FOO';
			my $i = new_ok('CGI::Info');
			$i->params();
			ok($i->status() == 501);
		},
		qr/^Use/
	);

	does_carp_that_matches(
		sub {
			local $ENV{'REQUEST_METHOD'} = 'POST';

			my $input = 'foo=bar';
			local $ENV{'CONTENT_LENGTH'} = length($input) + 1;	# One more than the length, should error

			open (my $fin, '<', \$input);
			local *STDIN = $fin;

			my $i = new_ok('CGI::Info');
			my %p = %{$i->params()};
			ok(!defined($p{fred}));
			is($p{'foo'}, 'bar', 'foo=bar');
			close $fin;
		},
		qr/^POST failed/
	);

	does_carp_that_matches(sub { CGI::Info->new({ expect => 'foo' }); }, qr/must be a reference to an array/);

	{
		local $ENV{'REQUEST_METHOD'} = 'POST';
		local $ENV{'CONTENT_TYPE'} = 'Multipart/form-data; boundary=-----xyz';
		my $input = <<'EOF';
-------xyz
Content-Disposition: form-data; name="country"

44
-------xyz
Content-Disposition: form-data; name="datafile"; filename="foo.txt"
Content-Type: text/plain

Bar

-------xyz--
EOF
		local $ENV{'CONTENT_LENGTH'} = length($input);
		does_carp_that_matches(sub { new_ok('CGI::Info')->params(upload_dir => '/') }, qr/ isn't writeable$/);
		does_carp_that_matches(sub { new_ok('CGI::Info')->params(upload_dir => 't/carp.t') }, qr/ isn't a full pathname$/);
		does_carp_that_matches(sub { new_ok('CGI::Info')->params(upload_dir => '/t/carp.t') }, qr/ isn't a directory$/);
		# new_ok('CGI::Info')->params(upload_dir => '/t/carp.t');
	}
}
