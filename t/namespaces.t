#!/usr/bin/env perl

use strict;
use warnings;
use Test::Most;

unless($ENV{RELEASE_TESTING}) {
	plan(skip_all => "Author tests not required for installation");
}

use Test::CleanNamespaces;

all_namespaces_clean;
