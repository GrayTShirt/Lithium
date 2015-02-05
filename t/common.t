#!/usr/bin/perl

use strict;
use warnings;

use POSIX;
use Test::More;
use Lithium;
use LWP::UserAgent;
use Synacor::Test::Selenium;

my $DANCER_PORT  = 8910;
my $PHANTOM_PORT = 16211;
my @phantom = qq/
	\/usr\/bin\/phantomjs
	--webdriver=$PHANTOM_PORT
	--webdriver-loglevel='INFO'
	--ignore-ssl-errors=yes
	--ssl-protocol=TSLv1
	>\/dev\/null 2>&1
/;

my %SELENIUM_CONFIG = (
	site     => undef,
	browser  => undef,
	host     => undef,
	port     => undef,
);

my $MASTER = $$;

END {
	&stop_depends if $$ == $MASTER;
}

# Set up default selenium configuration
$ENV{BROWSER} ||= "phantomjs";
if ($ENV{BROWSER} eq "phantomjs") {
	note "Using phantomjs for testing";
	plan skip_all => 'Install phantomjs' unless -x $phantom[0];
	$SELENIUM_CONFIG{browser} = "phantomjs";
	$SELENIUM_CONFIG{host}    = "localhost";
	$SELENIUM_CONFIG{port}    =  8910;
} else {
	note "Using $ENV{BROWSER} for testing";
	$SELENIUM_CONFIG{host}     = "ae01.buf.synacor.com";
	$SELENIUM_CONFIG{port}     =  4451;
	$SELENIUM_CONFIG{browser}  = $ENV{BROWSER};
	$SELENIUM_CONFIG{platform} = "MAC";
}

my $T = Test::Builder->new;
my %PIDS;

sub sel_conf
{
	my (%overrides) = @_;
	$SELENIUM_CONFIG{$_} = $overrides{$_} for keys %overrides;
	return %SELENIUM_CONFIG;
}

sub is_phantom
{
	my $driver = selenium_driver;
	return ($driver->{browser} eq "phantomjs")
		if $driver;
	return ($ENV{BROWSER} eq "phantomjs") if $ENV{BROWSER};
	return undef;
}

sub start_depends
{
	set_port($DANCER_PORT);
	my $target = &test_site;

	# Fire up Dancer
	$PIDS{dancer} = fork;
	die "Failed to fork Dancer app: $!\n" if $PIDS{dancer} < 0;
	if ($PIDS{dancer}) {
		# pause until we can connect to ourselves
		my $ua = LWP::UserAgent->new();
		my $up = 0;
		for (1 .. 30) {
			my $res = $ua->get($target);
			$up = $res->is_success; last if $up;
			sleep 1;
		}
		$T->ok($up, "Dancer is up and running at $target")
			or BAIL_OUT "Test website could not be started from Dancer";

		# Fire up Phantom
		if ($ENV{BROWSER} eq "phantomjs") {
			$PIDS{phantom} = fork;
			die "Failed to fork phantomjs: $!\n" if $PIDS{phantom} < 0;
			if ($PIDS{phantom}) {
				# pause until we can connect to webdriver
				my $ua = LWP::UserAgent->new();
				my $up = 0;
				for (1 .. 30) {
					my $res = $ua->get("http://127.0.0.1:$PHANTOM_PORT/sessions");
					$up = $res->is_success; last if $up;
					sleep 1;
				}
				$T->ok($up, "PhantomJS is up and running at http://127.0.0.1:$PHANTOM_PORT")
					or BAIL_OUT "PhantomJS could not start properly, giving up";
			} else {
				# Close stdout/stderr from phantom
				close STDOUT;
				close STDERR;
				exec @phantom;
				exit 1;
			}
		}
		return $target;
	} else {
		close STDERR;
		Lithium::run(
			daemonize => 'false',
		);
		exit 1;
	}
	return;
}

sub killproc
{
	my ($pid) = @_;
	kill "TERM", $pid;
	return 0 if waitpid($pid, POSIX::WNOHANG);
	sleep 1;

	return 0 if waitpid($pid, POSIX::WNOHANG);
	sleep 1;

	# Commented out because somehow this kills jenkins
	#kill "KILL", $pid;
	return 0;
}

sub stop_depends
{
	stop_selenium;
	for (keys %PIDS) {
		killproc $PIDS{$_};
		delete $PIDS{$_};
	}
}

sub dancer_port
{
	my $port = shift;
	$DANCER_PORT = $port if defined $port;
	$DANCER_PORT;
}

sub test_site
{
	my $hostname = `hostname`;
	chomp $hostname;
	return "http://$hostname:$DANCER_PORT/";
}

=head1 t::commom

=head2 DESCRIPTION

=head2 FUNCTIONS

=over

=item start_depends

=item stop_depends

=item spawn

=item reap

=back

=head1 AUTHOR

Written by Dan Molik <dmolik@synacor.com>

=cut

1;
