package Lithium::Daemon;

use strict;
use warnings;

use POSIX qw/:sys_wait_h setgid setuid/;
use Lithium;


sub spawn_worker
{
	my (@options) = @_;
	my $pid = fork;
	exit 1 if $pid < 0;
	if ($pid == 0) {
		$0 = __PACKAGE__." worker";
		if ($options{dont_loop}) {
			$options{sub}->();
		} else {
			while (1) {
				sleep($options{sleep} || 30);
				$options{sub}->();
			}
		}
	}
	return $pid;
}

sub app
{
	$0 = __PACKAGE__." master";
	debug "clearing cache file '$CONFIG->{cache_file}'";
	$CACHE->empty;
	debug "success on clearing cache";
	NODES({}); SESSIONS({}); OLD({});
	STATS({ nodes => 0, runtime => 0, sessions => 0 });
	debug "initialized the backend";
	# CONFIG->set($CONFIG);
	my $server = Plack::Handler::Starman->new(
			port              => $CONFIG->{port},
			workers           => $CONFIG->{workers},
			keepalive_timeout => $CONFIG->{keepalive},
			argv              => [__PACKAGE__,],
		);
	info "starting ".__PACKAGE__;
	push @PIDS, spawn_worker(
		sub   => Lithium::check_sessions,
		sleep => $CONFIG{session_timeout}
	);
	push @PIDS, spawn_worker(
		sub   => Lithium::check_nodes
	);
	my $pid = fork;
	exit 1 if $pid < 0;
	if ($pid == 0) {
		$server->run(sub {Lithium->dance(Dancer::Request->new(env => shift))});
	} else {
		push @PIDS, $pid;
	}
	while (1) { sleep 9999; }
}

sub run
{
	if (!$CONFIG->{daemon} || $CONFIG->{daemon} =~ m/off|no|false/i) {
		&app;
		return $? == 0;
	}
	my $pid = fork;
	my $pidfile = $CONFIG->{pidfile};
	exit 1 if $pid < 0;
	if ($pid == 0) {
		exit if fork;
		my $fh;
		if (-f $pidfile) {
			open my $fh, "<", $pidfile or die "Failed to read $pidfile: $!\n";
			my $found_pid = <$fh>;
			close $fh;
			if (kill "ZERO", $found_pid) {
				warning __PACKAGE__." already running";
				return 1;
			} else {
				unlink $pidfile;
			}
		}
		open $fh, ">", $pidfile and do {
			print $fh "$$";
			close $fh;
		};
		$) = getgrnam($CONFIG->{gid}) or die "Unable to set group to $CONFIG->{gid}: $!";
		$> = getpwnam($CONFIG->{uid}) or die "Unable to set user to $CONFIG->{uid}: $!";
		open STDOUT, ">/dev/null";
		open STDERR, ">/dev/null";
		open STDIN,  "</dev/null";
		&app;
		exit 2;
	}

	waitpid($pid, 0);
	return $? == 0;
}

sub stop
{
	info "stopping ".__PACKAGE__;
	for (@PIDS) {
		kill 'TERM', $_;
	}
	my $pidfile = $CONFIG->{pidfile};
	return unless -f $pidfile;
	my $fh;
	open $fh, "<", $pidfile or die "Failed to read $pidfile: $!\n";
	my $pid = <$fh>;
	close $fh;

	kill "TERM", $pid;
	for (1 .. 2 ) {
		if (waitpid($pid, WNOHANG)) {
			unlink $pidfile;
			return;
		}
		sleep 1;
	}

	kill "KILL", $pid;
	waitpid($pid, 0);
	unlink $pidfile;
	return;

}

=head1 Lithium::Daemon

=cut

1;
