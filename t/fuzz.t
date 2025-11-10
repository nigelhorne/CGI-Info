#!/usr/bin/env perl

use strict;
use warnings;

use FindBin qw($Bin);
use IPC::Run3;
use IPC::System::Simple qw(system);
use Test::Most;
use Test::Needs 'App::Test::Generator';

my $dirname = "$Bin/conf";

if((-d $dirname) && opendir(my $dh, $dirname)) {
	while (my $filename = readdir($dh)) {
		# Skip '.' and '..' entries
		next if ($filename eq '.' || $filename eq '..');

		my $filepath = "$dirname/$filename";

		if(-f $filepath) {	# Check if it's a regular file
			my ($stdout, $stderr);
			run3 ['fuzz-harness-generator', '-r', $filepath], undef, \$stdout, \$stderr;

			ok($? == 0, 'Generated test script exits successfully');

			if($? == 0) {
				ok($stdout =~ /^Result: PASS/ms);
			} else {
				diag("STDOUT:\n$stdout");
			}
			diag($stderr) if(length($stderr));
		}
	}
}

done_testing();
