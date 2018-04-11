use Test::Most;

use warnings;
use strict;

eval 'use Test::Portability::Files';
plan skip_all => "Test::Portability::Files required for testing filenames portability" if $@;
options(use_file_find => 1);
run_tests();
