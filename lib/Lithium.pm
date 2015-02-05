package Lithium;

use strict;
use warnings;

use Dancer;
use Dancer::Logger::Syslog;
use Plack::Handler::Starman;

our ($CACHE, $NODES, $SESSIONS, $STATS, $OLD);
require Lithium::Cache;

use YAML::XS qw/LoadFile/;
use Time::HiRes qw/time/;
use Devel::Size qw(size);
use Pod::Simple::HTML;

use LWP::UserAgent;
use HTTP::Request::Common ();
# Add a delete function to LWP, for continuity!
no strict 'refs';
if (!defined *{"LWP::UserAgent::delete"}{CODE}) {
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


our $CONFIG = {
	daemon       =>  1,
	log          => 'syslog',
	log_level    => 'debug',
	log_facility => 'daemon',
	workers      =>  3,
	keepalive    =>  150,
	port         =>  8910,
	daemonize    =>  1,
	gid          => 'lithium',
	uid          => 'lithium',
	pidfile      => '/var/run/lithium.pid',
	cache_file   => '/tmp/lithium-cache.tmp',
	log_file     => '/var/log/lithium.log',
};
my @PIDS;
$SIG{INT} = $SIG{TERM} = $SIG{QUIT} = sub {
	unlink $CONFIG->{cache_file};
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
	$CONFIG->{$_} = $config_file->{$_};
	$CONFIG->{$_} = $OPTIONS{$_} if exists $OPTIONS{$_};
}
for (keys %OPTIONS) {
	$CONFIG->{$_} = $OPTIONS{$_} if exists $OPTIONS{$_};
}

if ($CONFIG->{log} =~ m/syslog/i) {
	set syslog   => { facility => $CONFIG->{log_facility}, ident => __PACKAGE__, };
} elsif($CONFIG->{log} =~ m/file/i) {
	set log_file => $CONFIG->{log_file};
}
set logger      => $CONFIG->{log};
set log         => $CONFIG->{log_level};
set show_errors =>  1;

set serializer   => 'JSON';
set content_type => 'application/json';


get qr/(\/lithium)?\/(help|docs)/ => sub {
	header 'Content-Type' => 'text/html';
	my $p = Pod::Simple::HTML->new;
	my $html;
	$p->html_header_before_title(qq|
<!doctype html>
<html lang="en">
	<head>
		<meta http-equiv="Content-type" content="text/html; charset=utf-8" />
		<title>Lithium - Help
	|);
	$p->html_css(qq|
		<link href='http://fonts.googleapis.com/css?family=Molengo' rel='stylesheet' type='text/css'>
		<style>
			* {
				font-family: Molengo;
			}
			body {
				padding: 0;
				margin: 0;
				background-color: #A9A9A9;
			}
			#background {
				background-color: #FFFFFE;
				height: 100%;
				width: 80%;
				left: 10%;
				padding: 25px 35px;
				margin: 0 auto;
				overflow-x: hidden;
				overflow-y: auto;
				box-shadow: 14px 0px 10px #777, -14px 0px 10px #777;
			}
			h1 {
				border-bottom: 1px solid #A9A9A9;
			}
			p {
				padding-left: 10px;
			}
			dl {
				padding-left: 20px;
			}
		</style>
	|);
	$p->html_header_after_title('</title></head><body><div id="background"><div>');
	$p->html_footer("</div></div></body></html>");
	$p->output_string(\$html);
	$p->parse_file(Cwd::abs_path(__FILE__));
	return $html;
};
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
			NODES($NODES); STATS($STATS); SESSIONS($SESSIONS);

			return to_json($res);
			last;
		}
	}
	#redirect $CONFIG->{pair}, 301
	#	if &CONFIG->{pair};
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
	NODES($NODES);

	&STATS->{runtime} += $end_time - $start_time;
	STATS($STATS);

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
	NODES($NODES);

	&STATS->{nodes}++; STATS($STATS);

	return "ok";
};

get qr|(/lithium)?(/v\d)?/health| => sub {
	&NODES; &STATS; &OLD; &SESSIONS;
	my $health = {
		name    => __PACKAGE__,
		version => $VERSION,
		checks  => {
			'Disconnected Nodes' => {
				status  => 'Ok',
				message => 'No nodes are disconnected.',
			}
		}
	};
	
	if (scalar keys %{&OLD} > 0) {
		my @disconnected = keys %$OLD;
		$health->{checks}{'Disconnected Nodes'} = {
			status  => "WARN",
			message => "Following node[s] are disconnected: ".join(", ", @disconnected),
		}
	}

	if (request->env->{HTTP_ACCEPT} =~ m/json/i) {
		return to_json $health;
	} else {
		header 'Content-Type' => "text/plain";
		return to_yaml $health;
	}
};


sub check_nodes
{
	debug "checking for disconnected nodes";
	&STATS;
	for (keys %{&NODES}) {
		my $res = $agent->get("$NODES->{$_}{url}/status");
		next if $res->is_success;
		my $old_node = delete $NODES->{$_};
		$STATS->{nodes}--;
		NODES($NODES); STATS($STATS);
		&OLD->{$_} = $old_node;
		OLD($OLD);
	}
	debug "checking stale nodes to see if they are back up";
	for (keys %{&OLD}) {
		my $res = $agent->get("$OLD->{$_}{url}/status");
		next unless $res->is_success;
		my $new_old_node = delete $OLD->{$_};
		OLD($OLD);
		&STATS->{nodes}++; STATS->set;
		&NODES->{$_} = $new_old_node;
		NODES($NODES);
	}
}

sub check_sessions
{
	debug "checking for stale sessions";
	&NODES;
	my $time = time;
	for my $session (keys %{&SESSIONS}) {
		my $node = $SESSIONS->{$session};
		my $start_time = $NODES->{$node}{sessions}{$session};
		if ($CONFIG->{idle_session} && ($time - $start_time) > $CONFIG->{idle_session}) {
			$agent->delete("$NODES->{$node}{url}/session/$session");
			delete $NODES->{$node}{sessions}{$session};
			delete $SESSIONS->{$session};
			SESSIONS($SESSIONS); NODES($NODES);
		}
	}
}


=head1 LITHIUM

A Selenium grid replacement

=head2 SYNOPSIS

If you have ever tried to deploy a selenium server into your production environment you
probably had significant issues getting it to communicate synchronously with phantomjs.
Lithium is a mostly compatible drop in replacement for acquiring, forwarding WebDriver
sessions to WebDriver/Selenium2 compatible nodes.

Further tight intergation between backend cache and worker threads allows for a prefork http
server model that allows for fast session acquisition and removal, along with useful
performance metrics.

=head2 CONFIG

The config file is in yaml format.

=over

=item B<daemon>

Daemonize lithium, IE: fork to background, set to 0|no|off|false to not daemonize.

Default: Yes

=item B<log>

The log type, options are console, file, or syslog.

Default: syslog

=item B<log_level>

The log severity to report on, options are error, info, debug, or core

Default: info

=item B<log_facility>

If the log type is syslog, the log facility to report under, options are found in man syslog

Default: daemon

=item B<workers>

The number of http works to spawn.

Default: 3

=item B<keepalive>

The http session keepalive in millieseconds.

Default: 150

=item B<port>

The http port to listen for node registry and for session assignment.

Default: 8910

=item B<uid>

The user to run under, the user should be added at install time.

Default: lithium

=item B<gid>

The group to run under, the group should be added at install time.

Default: lithium

=item B<pidfile>

The long lived pid file to copy the master process ID to.

Default: /var/run/lithium.pid

=item B<cache_file>

The cache file is a memory mapped file, for a common memory location between the various
lithium processes.

Default: /tmp/lithium-cache.tmp

=item B<pair>

The lithium server pair URL to redirect in the event that all nodes are busy.

Default: None.

=item B<idle_session>

The time in seconds to wait for an active session to declare it dead and clean up after it.

Default: <Disabled>

=back

=head2 STATS

=over

=item I<< B<sessions> >>

The total number of started sessions since lithium started. [COUNTER]

=item I<< B<runtime> >>

The cumulative time (seconds), of all of the sessions that
have been running, since lithium has been started. [COUNTER]

=item I<< B<nodes> >>

The current number of connected nodes (phantomjs instances). [GAUGE]

=back

=head2 ROUTES

The following is a compact and exhaustive list of the API's available http paths,
otherwise known as Dancer routes.

=over

=item I<GET> B</ /help /lithium/help>

Return this help document as a HTML help page.

=item I<POST> B</ /session /wd/hub/session>

Start a new webdriver session, will return JSON document including the node redirect.

=item I<POST> B</grid/register>

Register a new node with Lithium, where a node is a phantomjs or standalone selenium session.

=item I<DELETE> B</session/[SESSION ID] /wd/hub/session/[SESSION ID]>

End a webdriver session.

=item I<GET> B</stats /lithium/stats>

Return the current performance statistics, see L</STATS> for details.

=item I<GET> B</health /v[API VER]/health /lithium/health /lithium/v[API VER]/health>

Force Lithium to check its own health, namely connectivity to registered NODES,
available memory in the cache.

=item I<GET> B</sessions /wd/hub/sessions>

Get a YAML or JSON document of the current sessions.

=item I<GET> B</nodes /wd/hub/nodes>

Get a YAML or JSON document of the currently connected nodes.

=back

=head2 FUNCTIONS

=over

=item I<app>

Return a PSGI compatible Dancer object.

=item I<run>

Start up Lithium, i.e: fork and save pid.

=item I<stop>

Find lithium via the pidfile and kill--int the master process.

=item I<STATS>

Get the STATS oject from the cache.

See the L</STATS> section for more details.

=item I<< STATS->set >>

Save the STATS oject to the cache.

=item I<NODES>

Get the NODES oject from the cache.

=item I<< NODES->set >>

Save the NODES oject to the cache.

=item I<SESSIONS>

Get the SESSIONS oject from the cache.

The SESSIONS object consists of a key value store
where the key is the SESSION ID and where the value
is the originating node.

=item I<< SESSIONS->set >>

Save the SESSIONS oject to the cache.

=item I<OLD>

Get the OLD oject from the cache.

=item I<< OLD->set >>

Save the OLD oject to the cache.

=item I<CONFIG>

Get the CONFIG oject from the cache, see the L</CONFIG> section for details.

=item I<< CONFIG->set >>

Save the CONFIG oject to the cache.

=back

=head2 Required Modules

=over

=item L<Dancer|https://metacpan.org/pod/Dancer>

=item L<Dancer::Logger::Syslog|https://metacpan.org/pod/Dancer::Logger::Syslog>

=item L<Starman|https://metacpan.org/pod/Starman>

=item L<Cache::FastMmap|https://metacpan.org/pod/Cache::FastMmap>

=item L<YAML::XS|https://metacpan.org/pod/distribution/YAML-LibYAML/lib/YAML/XS.pod>

=item L<Time::HiRes|https://metacpan.org/pod/Time::HiRes>

=item L<Devel::Size|https://metacpan.org/pod/Devel::Size>

=item L<Pod::Simple::HTML|https://metacpan.org/pod/Pod::Simple::HTML>

=item L<LWP::UserAgent|https://metacpan.org/pod/LWP::UserAgent>

=item L<HTTP::Request::Common|https://metacpan.org/pod/HTTP::Request::Common>

=back

=head2 REFERENCES

=over

=item L<WebDriver Wire Protocol|https://code.google.com/p/selenium/wiki/JsonWireProtocol>

=item L<Phantomjs|http://phantomjs.org/>

=item L<Ghostdriver|https://github.com/detro/ghostdriver>

=back

=head2 AUTHOR

Dan Molik, C<< <dmolik at synacor.com> >>

=head2 COPYRIGHT & LICENSE

Copyright 2014 Synacor Inc.

All rights reserved.

=cut

1;
