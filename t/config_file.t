#!/usr/bin/env perl

use strict;
use warnings;

use Test::Most;
use File::Temp qw/tempfile tempdir/;
use YAML::XS qw/DumpFile/;

use_ok('CGI::Info');

# Create a temp config file
my $tempdir = tempdir(CLEANUP => 1);
my $config_file = "$tempdir/config.yml";

# Write a fake config
my $class_name = 'CGI::Info';

DumpFile($config_file, {
	$class_name => {
		max_upload_size => 2
	}
});

# Create object using the config_file
my $obj = CGI::Info->new(config_file => $config_file);

ok($obj, 'Object was created successfully');
isa_ok($obj, 'CGI::Info');
cmp_ok($obj->{'max_upload_size'}, '==', 2, 'read max_upload_size from config');

local $ENV{'CGI::Info_MAX_UPLOAD_SIZE'} = 3;

$obj = CGI::Info->new(config_file => $config_file);

ok($obj, 'Object was created successfully');
isa_ok($obj, 'CGI::Info');
cmp_ok($obj->{'max_upload_size'}, '==', 3, 'read max_upload_size from config');

done_testing();
