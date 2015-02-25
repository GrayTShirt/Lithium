#!/usr/bin/perl

use strict;
use warnings;

use t::common;

use Test::More;
use Test::Deep;

use JSON::XS qw/decode_json/;

diag "Testing lithium $Lithium::VERSION connectivity";
my @PHANTOMS;
my $site = start_depends;

subtest 'Connect a Phatomjs to Lithium' => sub {
	start_webdriver sel_conf(
		site    => $site,
		headers => {
			HTTP_ACCEPT => 'application/json'
		});
	push @PHANTOMS, spool_a_phantom(port => 16716, grid => $site);
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

	start_webdriver sel_conf(
		site    => $site,
		host    => 'localhost',
		port    => LITHIUM_PORT,
		headers => {
			HTTP_ACCEPT => 'application/json'
		});
	visit '/help';
	is title, "Lithium - Help Lithium", "Check the title";
	stop_webdriver;

	start_webdriver sel_conf(
		site    => $site,
		host    => 'localhost',
		port    => LITHIUM_PORT,
		headers => {
			HTTP_ACCEPT => 'application/json'
		});
	visit '/help';
	is title, "Lithium - Help Lithium", "Check the title";
	stop_webdriver;

	start_webdriver sel_conf(
		site    => $site,
		port    => PHANTOM_PORT,
		headers => {
			HTTP_ACCEPT => 'application/json'
		});
	visit('/stats');
	$stats = decode_json(html("pre"));
	is $stats->{nodes}, 1, "Should have 1 node";
	is $stats->{sessions}, 2, "Should have 2 sessions";
	cmp_ok $stats->{runtime}, '>', 0, "Runtime must be greater than 0";
	stop_webdriver;
};

redead_phantoms @PHANTOMS;

stop_depends;
done_testing;
