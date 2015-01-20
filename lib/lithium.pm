package lithium;

use strict;
use warnings;

use Dancer;
use Dancer::Logger::Syslog;
use Plack::Handler::Starman;
use Cache::FastMmap;

use YAML::XS qw/LoadFile/;
use POSIX qw/:sys_wait_h setgid setuid/;
use Getopt::Long;
use Time::HiRes qw/time/;

use LWP::UserAgent;
use HTTP::Request::Common ();
use Devel::Size qw(size);
# Add a delete function to LWP, for continuity!
no strict 'refs';
if (! defined *{"LWP::UserAgent::delete"}{CODE}) {
	*{"LWP::UserAgent::delete"} =
		sub {
			my ($self, $uri) = @_;
			$self->request(HTTP::Request::Common::DELETE($uri));
		};
}
use strict 'refs';

our $VERSION = '1.0.0';

my $agent    = LWP::UserAgent->new(agent => __PACKAGE__."-$VERSION");
$agent->default_header(Content_Type => "application/json;charset=UTF-8");
push @{$agent->requests_redirectable}, 'POST';


my %CONFIG = (
	log          => 'syslog',
	log_level    => 'debug',
	log_facility => 'daemon',
	workers      =>  3,
	keepalive    =>  150,
	port         =>  8910,
	gid          => 'lithium',
	uid          => 'lithium',
	pidfile      => '/var/run/lithium.pid',
	cache_file   => '/tmp/lithium-cache.tmp',
);
my @PIDS;
$SIG{INT} = $SIG{TERM} = $SIG{QUIT} = sub {
	unlink $CONFIG{cache_file};
	for (@PIDS) {
		kill 'TERM', $_;
	}
	exit;
};
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
	page_size      => '512k', # size of perl objects to store
	num_pages      =>  4,     # num of objects
);
my $NODES    = $CACHE->get('NODES');
my $SESSIONS = $CACHE->get('NODES');
my $STATS    = $CACHE->get('STATS');
my $OLD      = $CACHE->get('OLD');

no strict 'refs';
# Build in some shim functions
*{"NODES"}         = sub { $NODES = $CACHE->get('NODES'); return $NODES };
*{"NODES::set"}    = sub { shift; $CACHE->set('NODES', scalar @_ ? @_ : $NODES) };
*{"SESSIONS"}      = sub { $SESSIONS = $CACHE->get('SESSIONS'); return $SESSIONS };
*{"SESSIONS::set"} = sub { shift; $CACHE->set('SESSIONS', scalar @_ ? @_ : $SESSIONS) };
*{"STATS"}         = sub { $STATS = $CACHE->get('STATS'); return $STATS };
*{"STATS::set"}    = sub { shift; $CACHE->set('STATS', scalar @_ ? @_ : $STATS) };
*{"OLD"}           = sub { $OLD = $CACHE->get('OLD'); return $OLD };
*{"OLD::set"}      = sub { shift; $CACHE->set('OLD', scalar @_ ? @_ : $OLD) };
use strict 'refs';

if ($CONFIG{log} =~ m/syslog/i) {
	set syslog      => { facility => $CONFIG{log_facility}, ident => __PACKAGE__, };
}
set logger      => $CONFIG{log};
set log         => $CONFIG{log_level};
set show_errors =>  1;

set serializer   => 'JSON';
set content_type => 'application/json';


get qr|(/wd/hub)?/sessions| => sub {
	if (request->env->{HTTP_ACCEPT} =~ m/json/i) {
		return to_json &SESSIONS;
	} else {
		header 'Content-Type' => "text/plain";
		return to_yaml &SESSIONS;
	}
};
get qr|(/wd/hub)?/nodes| => sub {
	if (request->env->{HTTP_ACCEPT} =~ m/json/i) {
		return to_json &NODES
	} else {
		header 'Content-Type' => "text/plain";
		return to_yaml &NODES;
	}
};
get qr|(/lithium)?/stats| => sub {
	if (request->env->{HTTP_ACCEPT} =~ m/json/i) {
		return to_json &STATS;
	} else {
		header 'Content-Type' => "text/plain";
		return to_yaml &STATS;
	}
};

post qr|(/wd/hub)?/session| => sub {
	my $request = from_json(request->body);
	for (keys %{&NODES}) {
		next unless scalar keys %{$NODES->{$_}{sessions}} < $NODES->{$_}{max_instances};
		next unless $request->{desiredCapabilities}{browserName} eq $NODES->{$_}{browser};
		my $res = $agent->post($NODES->{$_}{url}."/session", Content => request->body);
		if ($res->is_success) {
			$res = from_json($res->content);
			$res->{value}{node} = $NODES->{$_}{url};
			debug "session ($res->{sessionId}) created for ".request->host;

			$NODES->{$_}{sessions}{$res->{sessionId}} = time;
			&SESSIONS->{$res->{sessionId}} = $_; # Reverse hash session -> node
			&STATS->{sessions}++;
			NODES->set; STATS->set; SESSIONS->set;

			return to_json($res);
			last;
		}
	}
	redirect "/next lithium server", 301
		if $CONFIG{pair};
	status 404; return;
};
post '/' => sub {
	forward '/session';
};

del '/session/:session_id' => sub {
	my $session_id = param('session_id');
	debug "deleting session: $session_id";

	my $node = delete &SESSIONS->{$session_id};
	SESSIONS->set;

	&NODES;
	my $res = $agent->delete("$NODES->{$node}{url}/session/$session_id");
	my $end_time = time;
	my $start_time = delete $NODES->{$node}{sessions}{$session_id};
	NODES->set;

	&STATS->{runtime} += $end_time - $start_time;
	STATS->set;

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

	&NODES->{"$node->{configuration}{url}_$node->{capabilities}[0]{browserName}"} =
		{
			url           => $node->{configuration}{url},
			max_instances => $node->{capabilities}[0]{maxInstances},
			browser       => $node->{capabilities}[0]{browserName},
			sessions      => {},
		};
	NODES->set;

	&STATS->{nodes}++; STATS->set;

	return "ok";
};

get qr|(/lithium)?(/v\d)?/health| => sub {
	&NODES; &STATS; &OLD; &SESSIONS;
	header 'Content-Type' => "text/plain";
	return to_yaml {
		name    => __PACKAGE__,
		version => $VERSION,
		checks  => {
			test1 => {
				status  => 'OK',
				message => size($NODES)
			}
		}
	};
};
sub _check_nodes
{
	debug "checking for disconnected nodes";
	&STATS;
	for (keys %{&NODES}) {
		my $res = $agent->get("$NODES->{$_}{url}/status");
		next if $res->is_success;
		my $old_node = delete $NODES->{$_};
		$STATS->{nodes}--;
		NODES->set; STATS->set;
		&OLD->{$_} = $old_node;
		OLD->set;
	}
	for (keys %{&OLD}) {
		my $res = $agent->get("$OLD->{$_}{url}/status");
		next unless $res->is_success;
		my $new_old_node = delete $OLD->{$_};
		OLD->set;
		&STATS->{nodes}++; STATS->set;
		&NODES->{$_} = $new_old_node;
		NODES->set;
	}
}

sub _check_sessions
{
	debug "checking for stale sessions";
	&NODES;
	my $time = time;
	for my $session (keys %{&SESSIONS}) {
		my $node = $SESSIONS->{$session};
		my $start_time = $NODES->{$node}{sessions}{$session};
		if ($CONFIG{idle_session} && ($time - $start_time) > $CONFIG{idle_session}) {
			$agent->delete("$NODES->{$node}{url}/session/$session");
			delete $NODES->{$node}{sessions}{$session};
			delete $SESSIONS->{$session};
			SESSIONS->set; NODES->set;
		}
	}
}

sub _spawn_worker
{
	my ($sub, $dont_loop) = @_;
	my $pid = fork;
	exit 1 if $pid < 0;
	if ($pid == 0) {
		$0 = __PACKAGE__." worker";
		if ($dont_loop) {
			$sub->();
		} else {
			while (1) {
				sleep 30;
				$sub->();
			}
		}
	}
	return $pid;
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
		$0 = __PACKAGE__." master";
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
		$) = getgrnam($CONFIG{gid}) or die "Unable to set group to $CONFIG{gid}: $!";
		$> = getpwnam($CONFIG{uid}) or die "Unable to set user to $CONFIG{uid}: $!";
		open STDOUT, ">/dev/null";
		open STDERR, ">/dev/null";
		open STDIN,  "</dev/null";
		debug "clearing cache file '$CONFIG{cache_file}'";
		$CACHE->empty;
		STATS->set({ nodes => 0, runtime => 0, sessions => 0 });
		NODES->set({});
		SESSIONS->set({});
		OLD->set({});
		my $server = Plack::Handler::Starman->new(
				port              => $CONFIG{port},
				workers           => $CONFIG{workers},
				keepalive_timeout => $CONFIG{keepalive},
				argv              => ['lithium'],
			);
		info "starting ".__PACKAGE__;
		push @PIDS, _spawn_worker(\&_check_sessions);
		push @PIDS, _spawn_worker(\&_check_nodes);
		$pid = fork;
		exit 1 if $pid < 0;
		if ($pid == 0) {
			$server->run(\&app);
		} else {
			push @PIDS, $pid;
		}
		while (1) { sleep 9999; }
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

=head1 LITHIUM

A Selenium grid replacement

=head1 SYNOPSIS

If you have ever tried to deploy a selenium server into your production environment you may or
may not have had significant issue getting it to communication syncronesly with phantomjs.
Lithium is a mostly compatible drop in replacement for aquireing, forwarding WebDriver
sessions to WebDriver/Selenium2 compatible nodes.

Further tight intergation between backend cache and worker threads allows for a prefork http
server model that allows for fast session acquisition and removal, along with useful
performance metrics.

=head1 EXPORT

A list of functions that can be exported.  You can delete this section
if you don't export anything, such as for a purely object-oriented module.

=head1 FUNCTIONS

=head2 app

=head2 run

=head2 stop

=head1 CONFIG

The config file is in yaml format.

=over

=item log

The log type, options are console, file, or syslog.
Default: syslog

=item log_level

The log severity to report on, options are error, info, debug, or core
Default: info

=item log_facility

If the log type is syslog, the log facility to report under, options are found in man syslog
Default: daemon

=item workers

The number of http works to spawn.
Default: 3

=item keepalive

The http session keepalive in millieseconds.
Default: 150

=item port

The http port to listen for node registry and for session assignment.
Default: 8910

=item uid

The user to run under, the user should be added at install time.
Default: lithium

=item gid

The group to run under, the group should be added at install time.
Default: lithium

=item pidfile

The long lived pid file to copy the master process ID to.
Default: /var/run/lithium.pid

=item cache_file

The cache file is a memory mapped file, for a common memory location between the various
lithium processes.
Default: /tmp/lithium-cache.tmp

=back

=head1 ROUTES

=over

=item GET    / /help /lithium/help

Return this help document as a HTML help page.

=item POST   / /session /wd/hub/session

Start a new webdriver session, will return JSON document including the node redirect.

=item POST   /grid/register

Register a new node with Lithium, where a node is a phantomjs or standalone selenium session.

=item DELETE /session/<SESSION ID> /wd/hub/session/<SESSION ID>

End a webdriver session.

=item GET    /stats /lithium/stats

Return the current performance statistics, see STATS for details.

=item GET    /health /v<API VER>/health /lithium/health /lithium/v<API VER>/health

Force Lithium to check its own health, namely connectivity to registered NODES,
available memory in the cache.

=item GET    /sessions /wd/hub/sessions

Get a YAML or JSON document of the current sessions.

=item GET    /nodes /wd/hub/nodes

Get a YAML or JSON document of the currently connected nodes.

=back

=head1 STATS

=over

=item sessions - the total number of started sessions since lithium began.

=item runtime - the cumulative time (seconds), all of the sessions have been running, since start.

=item nodes - the current number of connected nodes (phantomjs instances).

=back

=head1 AUTHOR

Dan Molik, C<< <dmolik at synacor.com> >>

=head1 COPYRIGHT & LICENSE

Copyright 2014 Synacor Inc.

All rights reserved.

=cut

1;
