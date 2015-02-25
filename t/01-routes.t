use strict;
use warnings;
use Test::More;
use t::common;

diag "Testing lithium $Lithium::VERSION routes";
my $site = start_depends;

subtest "Ensure /help routes" => sub {
	start_webdriver sel_conf(site => $site);
	visit '/';
	isnt title, 'Error 404', "confirm the title is not 'Error 404'";
	visit '/help';
	isnt title, 'Error 404', "confirm the title is not 'Error 404'";
	visit '/lithium/help';
	isnt title, 'Error 404', "confirm the title is not 'Error 404'";
	visit '/docs';
	isnt title, 'Error 404', "confirm the title is not 'Error 404'";
	visit '/lithium/docs';
	isnt title, 'Error 404', "confirm the title is not 'Error 404'";
	stop_webdriver;
};

subtest "Ensure /stats routes" => sub {
	start_webdriver sel_conf(site => $site);
	visit '/stats';
	isnt title, 'Error 404', "confirm the title is not 'Error 404'";
	visit '/lithium/stats';
	isnt title, 'Error 404', "confirm the title is not 'Error 404'";
	stop_webdriver;
};

subtest "Ensure /health routes" => sub {
	start_webdriver sel_conf(site => $site);
	visit '/health';
	isnt title, 'Error 404', "confirm the title is not 'Error 404'";
	visit '/v1/health';
	isnt title, 'Error 404', "confirm the title is not 'Error 404'";
	visit '/v2/health';
	isnt title, 'Error 404', "confirm the title is not 'Error 404'";
	visit '/lithium/health';
	isnt title, 'Error 404', "confirm the title is not 'Error 404'";
	visit '/lithium/v1/health';
	isnt title, 'Error 404', "confirm the title is not 'Error 404'";
	visit '/lithium/v2/health';
	isnt title, 'Error 404', "confirm the title is not 'Error 404'";
	stop_webdriver;
};

subtest "Ensure /sessions routes" => sub {
	start_webdriver sel_conf(site => $site);
	visit '/sessions';
	isnt title, 'Error 404', "confirm the title is not 'Error 404'";
	visit '/wd/hub/sessions';
	isnt title, 'Error 404', "confirm the title is not 'Error 404'";
	stop_webdriver;
};

subtest "Ensure /nodes routes" => sub {
	start_webdriver sel_conf(site => $site);
	visit '/nodes';
	isnt title, 'Error 404', "confirm the title is not 'Error 404'";
	visit '/wd/hub/nodes';
	isnt title, 'Error 404', "confirm the title is not 'Error 404'";
	stop_webdriver;
};

subtest "Does 404 really 404?" => sub {
	start_webdriver sel_conf(site => $site);
	visit '/404';
	is title, 'Error 404', "confirm the title is 'Error 404'";
	stop_webdriver;
};

stop_depends;
done_testing;
