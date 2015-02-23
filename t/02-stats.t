use strict;
use warnings;
use Test::More;
use t::common;

diag "Testing lithium $Lithium::VERSION routes";
my $site = start_depends;

{
	start_webdriver sel_conf(site => $site);
	visit '/';
	isnt title, 'Error 404', "confirm the title is not 'Error 404'";
	stop_webdriver;
}

stop_depends;
done_testing;
