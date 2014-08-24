use strict;
use warnings;
use ExtUtils::MakeMaker;

WriteMakefile(
    NAME		=> 'CGI::Info',
    AUTHOR		=> q{Nigel Horne <njh@bandsman.co.uk>},
    VERSION_FROM	=> 'lib/CGI/Info.pm',
    ABSTRACT_FROM       => 'lib/CGI/Info.pm',
    ((defined($ExtUtils::MakeMaker::VERSION) &&
     ($ExtUtils::MakeMaker::VERSION >= 6.3002))
      ? ('LICENSE'=> 'GPL')
      : ()),
    PL_FILES	=> {},
    PREREQ_PM => {
	'Test::Most' => 0,
	'Test::NoWarnings' => 0,
	'URI::Heuristic' => 0,
	'Sys::Hostname' => 0,
	'File::Spec' => 0,
	'Cwd' => 0,
	'Carp' => 0,
	'Socket' => 0,
	'List::Member' => 0,
	# 'Test::Kwalitee' => 0,
	'HTTP::BrowserDetect' => 1.42,	# Include baidu etc.
	'Test::Requires' => 0,
	'File::Basename' => 0,
	'String::Clean::XSS' => 0,
    },
    dist		=> { COMPRESS => 'gzip -9f', SUFFIX => 'gz', },
    clean		=> { FILES => 'CGI-Info-*' },
    META_MERGE		=> {
    	'meta-spec' => { version => 2 },
    	resources => {
    		repository => {
			type => 'git',
			url => 'git://github.com/nigelhorne/CGI-Info.git',
			web => 'https://github.com/nigelhorne/CGI-Info',
    		},
	},
    },
    MIN_PERL_VERSION	=> '5.6.2'	# Probably would work, but never tested on earlier versions than this
);
