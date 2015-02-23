package Lithium::Daemon;

use strict;
use warnings;
no strict 'refs';

use POSIX qw/:sys_wait_h setgid setuid/;
use Lithium;

sub start
{
	*{"Lithium::info"}->("starting ".__PACKAGE__);
	my $pid = fork;
	my $pidfile = ${*{"Lithium::CONFIG"}}->{pidfile};
	exit 1 if $pid < 0;
	if ($pid == 0) {
		exit if fork;
		my $fh;
		if (-f $pidfile) {
			open $fh, "<", $pidfile or die "Failed to read $pidfile: $!\n";
			my $found_pid = <$fh>;
			close $fh;
			if (kill "ZERO", $found_pid) {
				Lithium::warning __PACKAGE__." already running";
				return 1;
			} else {
				unlink $pidfile;
			}
		}
		open $fh, ">", $pidfile and do {
			print $fh "$$";
			close $fh;
		};
		$) = getgrnam(${*{"Lithium::CONFIG"}}->{gid})
			or die "Unable to set group to ".${*{"Lithium::CONFIG"}}->{gid}.": $!";
		$> = getpwnam(${*{"Lithium::CONFIG"}}->{uid})
			or die "Unable to set user to ".${*{"Lithium::CONFIG"}}->{uid}.": $!";
		open STDOUT, ">/dev/null";
		open STDERR, ">/dev/null";
		open STDIN,  "</dev/null";
		Lithium::app;
		exit 2;
	}

	waitpid($pid, 0);
	return $? == 0;
}

sub stop
{
	*{"Lithium::info"}->("stopping ".__PACKAGE__);
	for (@{*{"Lithium::PIDS"}}) {
		kill 'TERM', $_;
	}
	my $pidfile = ${*{"Lithium::CONFIG"}}->{pidfile};
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

use strict 'refs';

=head1 NAME

Lithium::Daemon - Now witness this fully armed and operational Selenium Grip replacement.

=head2 SYNOPSIS

This class instantiates Lithium and daemonizes it.

=head2 FUNCTIONS

=over

=item I<start>

Start the Lithium application in daemon mode.

=item I<stop>

Stop the Lithium application.

=back

=head2 AUTHOR

Dan Molik C<< <dmolik at synacor.com> >>

=head2 COPYRIGHT & LICENSE

Copyright 2014 Synacor Inc.

All rights reserved.

=cut

1;
