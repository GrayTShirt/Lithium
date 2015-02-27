#!/usr/bin/perl

use strict;
use warnings;

use Test::More;
use Test::Deep;

use LWP::UserAgent;
use JSON::XS qw/decode_json encode_json/;

use t::common;
use Lithium;

diag "Testing lithium-$Lithium::VERSION Subroutines";
my $site = start_depends;

subtest "Does check_nodes do it's jerb?" => sub {
	my @PHANTOMS;
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
	redead_phantoms @PHANTOMS;
	# Lithium::check_nodes;
	sleep 5; # wait 5 seconds to ensure check_nodes has run
	visit('/nodes');
	$nodes = decode_json(html("pre"));
	cmp_deeply($nodes, {}, "Node should be removed from list");
	push @PHANTOMS, spool_a_phantom(port => 16716);
	visit('/nodes');
	$nodes = decode_json(html("pre"));
	cmp_deeply($nodes, {}, "Node should not be in rotation yet");
	sleep 5; # wait 5 sec to have check_nodes push phantom back into production.
	visit '/nodes';
	$nodes = decode_json(html("pre"));
	cmp_deeply($nodes, {
			"http://127.0.0.1:16716_phantomjs" => {
					'browser'       => "phantomjs",
					'max_instances' => "1",
					'sessions'      => {},
					'url'           => "http://127.0.0.1:16716",
				},
			},
			"Ensure the node made it back into rotation");
	redead_phantoms @PHANTOMS;
	stop_webdriver;
};

subtest "What happens when sessions go stale?" => sub {
	my @PHANTOMS;
	push @PHANTOMS, spool_a_phantom(port => 16716, grid => $site);
	my $hang_session = LWP::UserAgent->new();
	push $hang_session->requests_redirectable, 'POST';
	my $res = $hang_session->post(
		"http://localhost:".LITHIUM_PORT."/session",
		Content => encode_json(
			{ desiredCapabilities => { browserName => 'phantomjs' } }
		));
	ok($res->is_success, "Made a fake session");
	start_webdriver sel_conf(
		site    => $site,
		port    => PHANTOM_PORT,
		headers => {
			HTTP_ACCEPT => 'application/json'
		});
	visit('/sessions');
	my $sessions = decode_json(html("pre"));
	cmp_ok scalar(keys %$sessions), "==", 1, "We should find the first session";
	sleep 10; # Idle out the session.
	visit('/sessions');
	$sessions = decode_json(html("pre"));
	cmp_ok scalar(keys %$sessions), "==", 0, "The session should have idled out";
	redead_phantoms @PHANTOMS;
	stop_webdriver;
};

stop_depends;
done_testing;
