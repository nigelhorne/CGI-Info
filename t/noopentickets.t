#!/usr/bin/env perl

use strict;
use warnings;
use WWW::RT::CPAN;	# FIXME: use a REST client
use Data::Dumper;
use Test::Most tests => 3;

if($ENV{AUTHOR_TESTING}) {
	if(my @rc = @{WWW::RT::CPAN::list_dist_active_tickets(dist => 'CGI-Info')}) {
		ok($rc[0] == 200);
		ok($rc[1] eq 'OK');
		my @tickets = @{$rc[2]};

		if(scalar(@tickets)) {
			foreach my $ticket(@tickets) {
				diag($ticket->{id}, ': ', $ticket->{title}, ', broken since ', $ticket->{'broken_in'}[0]);
			}
		}
		ok(scalar(@tickets) == 0);
	} else {
		plan(skip_all => "Can't connect to rt.cpan.org");
	}
} else {
	plan(skip_all => 'Author tests not required for installation');
}
