#!perl -Tw

use strict;
use warnings;
use Test::Most tests => 17;
use Test::NoWarnings;

BEGIN {
	use_ok('CGI::Info');
}

ROBOT: {
	delete $ENV{'REMOTE_ADDR'};
	delete $ENV{'HTTP_USER_AGENT'};

	my $i = new_ok('CGI::Info');
	ok($i->is_robot() == 0);

	$ENV{'REMOTE_ADDR'} = '65.52.110.76';
	$i = new_ok('CGI::Info');
	ok($i->is_robot() == 0);

	$ENV{'HTTP_USER_AGENT'} = 'Mozilla/5.0 (compatible; bingbot/2.0; +http://www.bing.com/bingbot.htm)';
	$i = new_ok('CGI::Info');
	ok($i->is_robot() == 1);
	ok($i->browser_type() eq 'robot');

	$ENV{'REMOTE_ADDR'} = '119.63.196.107';
	$ENV{'HTTP_USER_AGENT'} = 'Mozilla/5.0 (compatible; Baiduspider/2.0; +http://www.baidu.com/search/spider.html)';

	$i = new_ok('CGI::Info');
	ok($i->is_robot() == 1);
	ok($i->browser_type() eq 'robot');

	$ENV{'REMOTE_ADDR'} = '207.241.237.233';
	$ENV{'HTTP_USER_AGENT'} = 'Mozilla/5.0 (compatible; archive.org_bot +http://www.archive.org/details/archive.org_bot)';
	$i = new_ok('CGI::Info');
	ok($i->is_robot() == 1);
	ok($i->browser_type() eq 'robot');

	$ENV{'REMOTE_ADDR'} = '74.92.149.57';
	$ENV{'HTTP_USER_AGENT'} = 'Mozilla/5.0 (Macintosh; U; Intel Mac OS X 10.7; en-US; rv:1.9.2.20) Gecko/20110803 Firefox/3.6.20';
	$i = new_ok('CGI::Info');
	ok($i->is_robot() == 0);
}
