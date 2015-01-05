package lithium;

use strict;
use warnings;

use Dancer;
use LWP::UserAgent;
use Data::Dumper;
use YAML::XS;
use HTTP::Request::Common ();
# Add a delete function to LWP, for continuity!
no strict 'refs';
if (! defined *{"LWP::UserAgent::delete"}{CODE}) {
	*{"LWP::UserAgent::delete"} =
		sub {
			my ($self, $uri) = @_;
			$self->request(HTTP::Request::Common::DELETE($uri));
		};
}

our $VERSION = '0.1';

my $NODES    = {};
my %CONFIG   = ();
my $SESSIONS = {};
my $agent    = LWP::UserAgent->new(agent => __PACKAGE__);
$agent->default_header(Content_Type => "application/json;charset=UTF-8");
# pretty sure this violates RFC 2616, oh well
push @{$agent->requests_redirectable}, 'POST';

my %CONFIG = (
	 log           => 'syslog',
	'log_level'    => 'info',
	'log_facility' => 'daemon',
	 port          =>  8910,
	 gid           => 'lithium',
	 uid           => 'lithium',
	 pidfile       => '/var/run/lithium.pid',
);

my %OPTIONS = (
	config  => '/etc/ghost.conf',
);

GetOptions(\%OPTIONS, qw/
	help|h|?
	config|c=s
	port|P=i
	log|l=s
	log_level|L=s
	log_facility|f=s
	log_file|F=s
	uid|U=s
	gid|G=s
	pidfile|p=s
	debug|D
/) or pod2usage(2);
pod2usage(1) if $OPTIONS{help};

my $config_file;
if (-f $OPTIONS{config}) {
	eval { $config_file = LoadFile($OPTIONS{config}); 1 }
		or die "Failed to load $OPTIONS{config}: $@\n";
} else {
	print STDERR "No configuration file found starting|stopping with defaults\n";
}

for (keys %$config_file) {
	$CONFIG{$_} = $config_file->{$_};
	$CONFIG{$_} = $OPTIONS{$_} if exists $OPTIONS{$_};
}
for (keys %OPTIONS) {
	$CONFIG{$_} = $OPTIONS{$_} if exists $OPTIONS{$_};
}
set serializer => 'JSON';
set port       => $CONFIG{port};
set logger     => 'console';
set log        => 'debug';
set show_errors => 1;


get '/sessions' => sub {
	debug "Sessions hit\n";
	# ... hmmm landing page? ... docs ?
	return 'ok';
};
get '/wd/hub/sessions' => sub {
	redirect "/sessions";
};
post '/' => sub {
	redirect '/session', 301;
};
post '/session' => sub {
	debug "client is requesting a new session (/session)";
	my $request = from_json(request->body);
	debug(Dumper($request));
	for (keys %$NODES) {
		next unless scalar keys %{$NODES->{$_}{sessions}} < $NODES->{$_}{max_instances};
		next unless $request->{desiredCapabilities}{browserName} eq $NODES->{$_}{browser};
		my $res = $agent->post("$NODES->{$_}{url}/session", Content => request->body);
		if ($res->is_success) {
			$res = from_json($res->content);
			$res->{value}{node} = $NODES->{$_}{url};
			$NODES->{$_}{sessions}{$res->{sessionId}} = 1;
			$SESSIONS->{$res->{sessionId}} = $_; # Reverse hash session -> node
			return to_json($res);
			last;
		}
	}
	redirect "/next lithium server", 301
		if $CONFIG{pair};
	status 404; return;
};
del '/session/:session_id' => sub {
	my $session_id = param('session_id');
	debug "deleting session: $session_id";
	my $node = delete $SESSIONS->{$session_id};
	my $res = $agent->delete("$NODES->{$node}{url}/session/$session_id");

	delete $NODES->{$node}{sessions}{$session_id};
	debug "Nodes: \n".Dumper($NODES);
	debug "Sessions: \n".Dumper($SESSIONS);
	status 204;
	return 'ok';
};
del '/wd/hub/session/:session_id' => sub {
	forward '/session/'.params->{session_id};
};
post '/wd/hub/session' => sub {
	debug "client is requesting a new session (/wd/hub/session)";
	redirect "/session", 301;
};

post '/grid/register' => sub {
	my $node = from_json(request->body);
	debug "Registering new node ($node->{capabilities}[0]{browserName}"
		." at $node->{configuration}{url},"
		." available sessions: $node->{capabilities}[0]{maxInstances})";

	$NODES->{"$node->{configuration}{url}_$node->{capabilities}[0]{browserName}"} =
		{
			url           => $node->{configuration}{url},
			max_instances => $node->{capabilities}[0]{maxInstances},
			browser       => $node->{capabilities}[0]{browserName},
			sessions      => {},
		};

	return "ok";
};

get qr|/lithium(/v\d)?/health| => sub {

};
get '/lithium/stats' => sub {

};

sub start
{
	my $pid = fork;
	my $pidfile = $CONFIG{pidfile};
	exit 1 if $pid < 0;
	if ($pid == 0) {
		exit if fork;

		my $fh;
		if (-f $pidfile) {
			open my $fh, "<", $pidfile or die "Failed to read $pidfile: $!\n";
			my $found_pid = <$fh>;
			close $fh;
			if (kill "ZERO", $found_pid) {
				return 1;
			} else {
				unlink $pidfile;
			}
		}
		open $fh, ">", $pidfile and do {
			print $fh "$$";
			close $fh;
		};
		$) = getgrnam($CONFIG{gid}) or die "Unable to set group to $CONFIG{gid}: $!";
		$> = getpwnam($CONFIG{uid}) or die "Unable to set user to $CONFIG{uid}: $!";
		open STDOUT, ">/dev/null";
		open STDERR, ">/dev/null";
		open STDIN,  "</dev/null";
		dance;
		exit 2;
	}

	waitpid($pid, 0);
	return $? == 0;
}

sub stop
{
	my $pidfile = $CONFIG{pidfile};
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

=head1 NAME

lithium - The great new lithium!

=head1 SYNOPSIS

Quick summary of what the module does.

Perhaps a little code snippet.

=head1 EXPORT

A list of functions that can be exported.  You can delete this section
if you don't export anything, such as for a purely object-oriented module.

=head1 FUNCTIONS

=head2 function1

=head1 AUTHOR

Dan Molik, C<< <dmolik at synacor.com> >>

=head1 COPYRIGHT & LICENSE

Copyright 2014 Synacor Inc.

All rights reserved.

=cut

1;
