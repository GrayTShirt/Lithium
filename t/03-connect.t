#!/usr/bin/perl

use strict;
use warnings;

use t::common;

use Test::More;
use Test::Deep;

use JSON::XS qw/decode_json/;

diag "Testing lithium $Lithium::VERSION connectivity";
my $site = start_depends;

subtest 'Connect a Phatomjs to Lithium' => sub {
	start_webdriver sel_conf(
		site    => $site,
		headers => {
			HTTP_ACCEPT => 'application/json'
		});
	spool_a_phantom(port => 16716, grid => $site);
	visit('/nodes');
	my $nodes = decode_json(html("pre"));
	cmp_deeply($nodes, {
			"http://127.0.0.1:16716_phantomjs" => {
					'browser'       => "phantomjs",
					'max_instances' => "1",
					'sessions'      => {},
					'url'           => "http://127.0.0.1:16716",
				},
			},
			"Ensure the structure of the nodes object");
	visit('/stats');
	my $stats = decode_json(html("pre"));
	cmp_deeply($stats, {'nodes' => 1, 'runtime' => 0, 'sessions' => 0},
		"Ensure the stats object is updated when node is connected");
	stop_webdriver;
};

redead_phantoms;

stop_depends;
done_testing;
