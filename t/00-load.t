#!perl -w

use warnings;
use strict;

use Test::Most tests => 2;

BEGIN {
	use_ok('CGI::Info') || BAIL_OUT('CGI::Info failed to load');
}

require_ok('CGI::Info') || do {
	diag("Failed to require CGI::Info: $@");
	BAIL_OUT("CGI::Info failed to load: $@");
};

diag("Testing CGI::Info $CGI::Info::VERSION, Perl $], $^X");
