package lithium;

use strict;
use warnings;

use Dancer;
use Plack::Handler::Starman;
use LWP::UserAgent;
use Time::HiRes qw/time/;
use YAML::XS qw/LoadFile/;
use POSIX qw/:sys_wait_h setgid setuid/;
use Getopt::Long;
use Cache::FastMmap;
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

our $VERSION = '0.9.0';

my $agent    = LWP::UserAgent->new(agent => __PACKAGE__."-$VERSION");
$agent->default_header(Content_Type => "application/json;charset=UTF-8");
# pretty sure this violates RFC 2616, oh well
push @{$agent->requests_redirectable}, 'POST';


# Defaults
my %CONFIG = (
	log          => 'syslog',
	log_level    => 'info',
	log_facility => 'daemon',
	workers      =>  3,
	keepalive    =>  150,
	port         =>  8910,
	gid          => 'lithium',
	uid          => 'lithium',
	pidfile      => '/var/run/lithium.pid',
	cache_file   => '/tmp/lithium-cache.tmp',
);

my %OPTIONS = (
	config  => '/etc/lithium.conf',
);

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

my $CACHE = Cache::FastMmap->new(
	share_file     => $CONFIG{cache_file},
	expire_time    =>  0,
	unlink_on_exit =>  0,
	empty_on_exit  =>  0,
	page_size      => '1m', # size of perl objects to store
	num_pages      =>  16,  # num of objects
);

my $NODES    = $CACHE->get('NODES');
my $SESSIONS = $CACHE->get('NODES');
my $STATS    = $CACHE->get('STATS');

set logger       => 'console';
set log          => 'debug';
set show_errors  =>  1;

set serializer   => 'JSON';
set content_type => 'application/json';


get qr|(/wd/hub)?/sessions| => sub {
	debug "Sessions hit\n";
	# ... hmmm landing page? ... docs ?
	return 'ok';
};
post '/' => sub {
	redirect '/session', 301;
};
post qr|(/wd/hub)?/session| => sub {
	debug "client is requesting a new session (/session)";
	my $request = from_json(request->body);
	$NODES = $CACHE->get('NODES');
	for (keys %$NODES) {
		next unless scalar keys %{$NODES->{$_}{sessions}} < $NODES->{$_}{max_instances};
		next unless $request->{desiredCapabilities}{browserName} eq $NODES->{$_}{browser};
		my $res = $agent->post("$NODES->{$_}{url}/session", Content => request->body);
		if ($res->is_success) {
			$res = from_json($res->content);
			$res->{value}{node} = $NODES->{$_}{url};
			$NODES->{$_}{sessions}{$res->{sessionId}} = time;
			$SESSIONS = $CACHE->get('SESSIONS');
			$STATS = $CACHE->get('STATS');
			$SESSIONS->{$res->{sessionId}} = $_; # Reverse hash session -> node
			$STATS->{sessions}++;
			$CACHE->set('SESSIONS', $SESSIONS);
			$CACHE->set('STATS', $STATS);
			$CACHE->set('NODES', $NODES);
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
	$SESSIONS = $CACHE->get('SESSIONS');
	my $node = delete $SESSIONS->{$session_id};
	$CACHE->set('SESSIONS', $SESSIONS);
	$NODES = $CACHE->get('NODES');
	my $res = $agent->delete("$NODES->{$node}{url}/session/$session_id");
	my $end_time = time;
	my $start_time = delete $NODES->{$node}{sessions}{$session_id};
	$CACHE->set('NODES', $NODES);
	$STATS = $CACHE->get('STATS');
	$STATS->{runtime} += $end_time - $start_time;
	$CACHE->set('STATS', $STATS);
	status 204;
	return 'ok';
};
del '/wd/hub/session/:session_id' => sub {
	forward '/session/'.params->{session_id};
};

post '/grid/register' => sub {
	my $node = from_json(request->body);
	debug "Registering new node ($node->{capabilities}[0]{browserName}"
		." at $node->{configuration}{url},"
		." available sessions: $node->{capabilities}[0]{maxInstances})";
	$NODES = $CACHE->get('NODES');
	$NODES->{"$node->{configuration}{url}_$node->{capabilities}[0]{browserName}"} =
		{
			url           => $node->{configuration}{url},
			max_instances => $node->{capabilities}[0]{maxInstances},
			browser       => $node->{capabilities}[0]{browserName},
			sessions      => {},
		};
	$CACHE->set('NODES', $NODES);
	$STATS = $CACHE->get('STATS');
	$STATS->{nodes}++;
	$CACHE->set('STATS', $STATS);
	return "ok";
};

get qr|(/lithium)?(/v\d)?/health| => sub {
	header 'Content-Type' => "text/plain";
	return to_yaml {
		name    => __PACKAGE__,
		version => $VERSION,
		checks  => {
			test1 => {
				status  => 'OK',
				message => 'Test OK'
			}
		}
	};
};
get qr|(/lithium)?/stats| => sub {
	$STATS = $CACHE->get('STATS');
	return to_json $STATS;
};

sub _check_nodes
{
	$NODES = $CACHE->get('NODES');
	$STATS = $CACHE->get('STATS');
	for (keys %$NODES) {
		my $res = $agent->get("$NODES->{$_}{url}/status");
		next if $res->is_success;
		delete $NODES->{$_};
		$STATS->{nodes}--;
		$CACHE->set('NODES', $NODES);
		$CACHE->set('STATS', $STATS);
	}
}

sub app
{
	my $request = Dancer::Request->new(env => shift);
	Dancer->dance($request);
}

sub run
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
				debug "Lithium already running";
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
		$CACHE->empty;
		$CACHE->set('STATS', { nodes => 0, runtime => 0, sessions => 0 });
		my $server = Plack::Handler::Starman->new(
				port              => $CONFIG{port},
				workers           => $CONFIG{workers},
				keepalive_timeout => $CONFIG{keepalive},
				argv              => ['lithium'],
			);
		$server->run(\&app);
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
