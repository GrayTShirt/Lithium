#!/usr/bin/perl

use strict;
use warnings;

use t::common;

use Test::More;
use Test::Deep;

use JSON::XS qw/decode_json/;

my @PHANTOMS;
sub spool_a_phantom
{
	my (%options) = @_;
	my @phantom = (
		"/usr/bin/phantomjs",
		"--webdriver='127.0.0.1:$options{port}'",
		"--webdriver-selenium-grid-hub='$options{grid}'",
		"--ignore-ssl-errors=yes",
		"--ssl-protocol=TSLv1",
	);
	my $forked = fork;
	push @PHANTOMS, $forked;
	return 0 if $forked < 0;
	if ($forked) {
		# pause until we can connect to webdriver
		my $ua = LWP::UserAgent->new();
		my $up = 0;
		for (1 .. 30) {
			my $res = $ua->get("http://127.0.0.1:$options{port}/sessions");
			$up = $res->is_success; last if $up;
			sleep 1;
		}
	} else {
		# Close stdout/stderr from phantom
		close STDOUT;
		close STDERR;
		exec join(" ", @phantom);
		exit 1;
	}
}
sub redead_phantoms
{
	for (@PHANTOMS) {
		killproc $_;
	}
}
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
	cmp_deeply($nodes,{
			"http://127.0.0.1:16716_phantomjs" => {
				'browser'       => "phantomjs",
				'max_instances' => "1",
				'sessions'      => {},
				'url'           => "http://127.0.0.1:16716",
			},
		}, "Ensure the structure of the nodes object");
	stop_webdriver;
};

redead_phantoms;

stop_depends;
done_testing;
