package lithium;

use strict;
use warnings;
use Dancer;

our $VERSION = '0.01';

set serializer => 'JSON';
set port       => $CONFIG{port};

get '/' => sub {
	# ... hmmm landing page? ... docs ?
};

post '/' => sub {
	# request a session
	return redirect 'path to phantomjs session', 301;
};

post '/wd/hub' => sub {
	# request a session
	
	#lwp call to phantom session

	return redirect 'path to phantomjs session', 301;
};

post '/grid/register' => sub {
	# register a node
	# push to grid list
};

get qr|/lithium(/v\d)?/health| => sub {

};

get '/lithium/stats' => sub {

};

dance;

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
