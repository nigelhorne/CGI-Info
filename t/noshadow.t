#!perl -w
#
# t/noshadow.t - a sample of how Test::NoShadow would be used here.
#
#     prove -l t/noshadow.t
#
# Two different questions, two different functions:
#
#   lib_ok()      did *this* test run exercise the copy of CGI::Info in this
#                 distribution's lib/ or blib/lib, or some other copy of it?
#                 That is a per-distribution question, so it belongs here.
#
#   find_shadows() do two checkouts in the workspace supply the same package?
#                 That is a question about the workspace, not about CGI::Info,
#                 so it does not belong in this distribution's test suite.
#                 The guarded block at the end shows how it would be wired up.
#
# Both functions emit their own TAP through Test::Builder and return a true or
# false value, so call them directly. Wrapping them in ok() double-counts, and
# also throws away the diagnostics they attach to the failure.

use strict;
use warnings;

use Test::Most;
use Test::Needs 'Test::NoShadow';	# skip cleanly if it isn't installed
use Test::NoShadow qw(lib_ok find_shadows);

use Cwd qw(abs_path);
use File::Spec;
use FindBin;

# lib_ok() looks the module up in %INC, so it has to be loaded first. Note this
# means the test fails outright, rather than skipping, when run without -Ilib
# against an installed CGI::Info - which is the failure it is there to catch.
use CGI::Info;

subtest 'CGI::Info came from this distribution' => sub {
	# Passes under prove -l and under make test (blib/lib). Fails if CGI::Info
	# was picked up from site_perl, which is what happens when the distribution
	# is installed and the tests are run from the wrong directory.
	lib_ok('CGI::Info');
};

subtest 'CGI::Info was not loaded twice' => sub {
	# lib_ok() only checks the module it is given. The complementary risk is a
	# second copy of the same package being pulled in from t/ or a sibling
	# checkout during this run.
	my @files = grep { defined } values %INC;
	my @copies = grep { m{/CGI/Info\.pm$} } @files;

	is(scalar(@copies), 1, 'exactly one CGI/Info.pm is loaded');
	diag("  loaded from: $copies[0]") if @copies == 1;
};

subtest 'pre-requisites came from the installed releases' => sub {
	# Every one of these is also a checkout in the same workspace, so a stray
	# -I on the command line, or a polluted PERL5LIB, would quietly substitute
	# a copy I am part-way through editing for the released version these tests
	# are supposed to be exercising.
	#
	# lib_ok() cannot express this. It passes when the loaded file *is* under
	# one of its lib arguments, so there is no way to say "not from there".
	# This is the check that the workspace-level tool is really for; here it is
	# done directly against %INC.
	my @prereqs = qw(Log::Abstraction Object::Configure Params::Get
		Params::Validate::Strict Return::Set Sub::Protected);
	my $siblings = abs_path(File::Spec->catdir($FindBin::Bin, File::Spec->updir, File::Spec->updir));

	foreach my $module (@prereqs) {
		(my $path = $module) =~ s/::/\//g;
		my $file = $INC{"$path.pm"};

		if(!defined($file)) {
			# Nothing loaded it, so there is no copy to have opinions about.
			pass("$module is not loaded by this test");
			next;
		}

		my $abs = abs_path($file) || File::Spec->rel2abs($file);
		my $rel = File::Spec->abs2rel($abs, $siblings);
		my $from_sibling = ($rel !~ /^\.\.(?:\/|$)/)
			&& !File::Spec->file_name_is_absolute($rel);

		ok(!$from_sibling, "$module came from the installed release, not a sibling checkout")
			or diag("  $module was loaded from $abs");
	}
};

# The workspace-level check. CGI::Info should not start failing its own test
# suite because of how the surrounding workspace is laid out, so this is off by
# default:
#
#     CGI_INFO_NOSHADOW_WORKSPACE=1 prove -l t/noshadow.t
#
# Two full scans of roughly 190 checkouts; expect it to take a few seconds.
SKIP: {
	skip 'set CGI_INFO_NOSHADOW_WORKSPACE=1 to scan the workspace', 2
		unless $ENV{'CGI_INFO_NOSHADOW_WORKSPACE'};

	my $workspace = abs_path(File::Spec->catdir($FindBin::Bin, File::Spec->updir, File::Spec->updir));

	# Backups and scratch copies of the same repository are expected to provide
	# the same packages as the checkout they were copied from; that is not a
	# bug, so they are filtered out. Providers are named by the first directory
	# beneath the scanned root, and ignore patterns are matched against both
	# "provider/package" and the full file path.
	my @backups = (qr{^ged2ste-http-vwf/}, qr{^OHTTP_VWF/}, qr{^Nvwf/});

	my $all = find_shadows($workspace);
	my $real = find_shadows($workspace, { ignore => \@backups });

	my $before = scalar(keys %$all);
	my $after = scalar(keys %$real);

	cmp_ok($after, '<=', $before, 'ignoring backups cannot invent a shadow');
	cmp_ok($after, '<', $before, 'ignoring the backup checkouts shortens the list')
		or diag('nothing was filtered - are those directories still at the top level?');

	diag(sprintf '%d shadowed package(s) under %s, %d once the backups are ignored',
		$before, $workspace, $after);

	# What is left is the interesting part: the packages that are genuinely
	# supplied by two live checkouts, which is what find_shadows is for.
	diag("still shadowed: $_") foreach (sort keys %$real);
}

done_testing();
