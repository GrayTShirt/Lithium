use strict;
use warnings;
use Test::More;
use t::common;

diag "Testing lithium $Lithium::VERSION routes";
my $site = start_depends;

{
	start_webdriver sel_conf(site => $site);
	visit '/stats';
	stop_webdriver;
}

stop_depends;
done_testing;
