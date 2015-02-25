use strict;
use warnings;
use Test::More;
use Test::Deep;
use t::common;
use JSON::XS qw/decode_json/;
use YAML::XS;

diag "Testing lithium $Lithium::VERSION routes";
my $site = start_depends;

my $stats_obj = {nodes => 0, runtime => 0, sessions => 0};
subtest 'JSON stats' => sub {
	start_webdriver sel_conf(site => $site, headers => {HTTP_ACCEPT => 'application/json'});
	visit '/stats';
	isnt title, 'Error 404', "confirm the title is not 'Error 404'";
	my $stats = decode_json(html('pre'));
	cmp_deeply($stats, $stats_obj, "Verify the STATS object");
	stop_webdriver;
};
subtest 'YAML stats' => sub {
	start_webdriver sel_conf(site => $site, headers => {HTTP_ACCEPT => 'text/yaml'});
	visit '/stats';
	isnt title, 'Error 404', "confirm the title is not 'Error 404'";
	my $stats = YAML::XS::Load(html('pre'));
	cmp_deeply($stats, $stats_obj, "Verify the STATS object");
	stop_webdriver;
};

subtest 'JSON nodes' => sub {
	start_webdriver sel_conf(site => $site, headers => {HTTP_ACCEPT => 'application/json'});
	visit '/nodes';
	isnt title, 'Error 404', "confirm the title is not 'Error 404'";
	my $nodes = decode_json(html('pre'));
	cmp_deeply($nodes, {}, "Verify the NODES object");
	stop_webdriver;
};
subtest 'YAML nodes' => sub {
	start_webdriver sel_conf(site => $site, headers => {HTTP_ACCEPT => 'text/yaml'});
	visit '/nodes';
	isnt title, 'Error 404', "confirm the title is not 'Error 404'";
	my $nodes = YAML::XS::Load(html('pre'));
	cmp_deeply($nodes, {}, "Verify the NODES object");
	stop_webdriver;
};

subtest 'JSON sessions' => sub {
	start_webdriver sel_conf(site => $site, headers => {HTTP_ACCEPT => 'application/json'});
	visit '/sessions';
	isnt title, 'Error 404', "confirm the title is not 'Error 404'";
	my $sessions = decode_json(html('pre'));
	cmp_deeply($sessions, {}, "Verify the SESSIONS object");
	stop_webdriver;
};
subtest 'YAML sessions' => sub {
	start_webdriver sel_conf(site => $site, headers => {HTTP_ACCEPT => 'text/yaml'});
	visit '/sessions';
	isnt title, 'Error 404', "confirm the title is not 'Error 404'";
	my $sessions = YAML::XS::Load(html('pre'));
	cmp_deeply($sessions, {}, "Verify the SESSIONS object");
	stop_webdriver;
};

stop_depends;
done_testing;
