package Peep::Conf;

require 5.005_62;
use strict;
use warnings;
use Carp;
use Data::Dumper;
use Peep::Log;

require Exporter;

our @ISA = qw( Exporter );

# Items to export into callers namespace by default. Note: do not export
# names by default without a very good reason. Use EXPORT_OK instead.
# Do not simply export all your public functions/methods/constants.

# This allows declaration	use Peep::Conf ':all';
# If you do not need this, moving things directly into @EXPORT or @EXPORT_OK
# will save memory.
our %EXPORT_TAGS = ( 'all' => [ qw( ) ] );
our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } );
our @EXPORT = qw( );
our $VERSION = do { my @r = (q$Revision: 1.7 $ =~ /\d+/g); sprintf "%d."."%02d" x $#r, @r };

sub new {

	my $self = shift;
	my $class = ref($self) || $self;
	my $this = {};
	bless $this, $class;
	return $this;

} # end sub new

# returns a logging object
sub logger {

	my $self = shift;
	if ( ! exists $self->{'__LOGGER'} ) { $self->{'__LOGGER'} = new Peep::Log }
	return $self->{'__LOGGER'};

} # end sub logger

sub setApp {

	my $self = shift;
	my $app = shift || confess "Cannot set app:  No app information found";
	$self->{"__APP"} = $app;
	$self->logger()->debug(1,"The application [$app] identified itself.");
	return 1;

} # end sub setApp

sub getApp {

	my $self = shift;

	if (exists $self->{"__APP"}) {
		return $self->{"__APP"};
	} else {
		confess "Cannot get app:  No app information has been set.";
	}

} # end sub getApp

sub setClientPort {

	my $self = shift;
	my $client = shift || confess "Cannot set port:  No client information found";
	my $port = shift || confess "Cannot set port:  No port information found";
	$self->{"__PORT"}->{$client} = $port;
	return 1;

} # end sub setClientPort

sub getClientPort {

	my $self = shift;
	my $client = shift || confess "Cannot get port:  No client information found";

	if (exists $self->{"__PORT"}->{$client}) {
		return $self->{"__PORT"}->{$client};
	} elsif ($self->optionExists('port')) {
		return $self->getOption('port');
	} else {
		confess "Cannot get port:  No port information has been defined for the client [$client].";
	}

} # end sub getClientPort

sub addBroadcast {

	my $self = shift;
	my $class = shift || confess "Cannot add broadcast:  No class identifier found";
	my $value = shift || confess "Cannot add broadcast:  No broadcast information found";

	confess "Cannot add broadcast for class [$class]:  Either the IP or port number has not been identified."
		unless ref($value) eq 'HASH' and exists $value->{'ip'} and exists $value->{'port'};

	my $broadcast = $value->{'ip'} . ':' . $value->{'port'};

	push @{$self->{"__BROADCAST"}->{$class}}, $value;

	return 1;

} # end sub addBroadcast

sub getBroadcastList {

	my $self = shift;

	confess "Cannot get broadcast list:  No broadcast information has been set." 
		unless exists $self->{"__BROADCAST"};

	my @broadcasts = sort keys % { $self->{"__BROADCAST"} };

	my @return;

	for my $class (@broadcasts) {
		push @return, @{$self->{"__BROADCAST"}->{$class}};
	}

	return wantarray ? @return : [@return];

} # end sub getBroadcastList

sub getBroadcast {

	my $self = shift;
	my $class = shift || confess "Cannot get broadcast:  No class identifier found";

	confess "Cannot get information for the broadcast class [$class]:  No information has been set."
		unless exists $self->{"__BROADCAST"} && exists $self->{"__BROADCAST"}->{$class};

	return wantarray ? @{$self->{"__BROADCAST"}->{$class}} : $self->{"__BROADCAST"}->{$class};

} # end sub getBroadcast

sub addServer {

	my $self = shift;
	my $class = shift || confess "Cannot add server:  No class identifier found";
	my $value = shift || confess "Cannot add server:  No server information found";

	confess "Cannot add server for class [$class]:  Either the name or port number has not been identified."
		unless ref($value) eq 'HASH' and exists $value->{'name'} and exists $value->{'port'};

	push @{$self->{"__SERVER"}->{$class}}, $value;

	return 1;

} # end sub addServer

sub getServerList {

	my $self = shift;

	confess "Cannot get server list:  No server information has been set." 
		unless exists $self->{"__SERVER"};

	my @servers = keys % { $self->{"__SERVER"} };

	my @return;

	for my $class (@servers) {
		push @return, @{$self->{"__SERVER"}->{$class}};
	}

	return wantarray ? @return : [@return];

} # end sub getServerList

sub getServer {

	my $self = shift;
	my $class = shift || confess "Cannot get server:  No class identifier found";

	confess "Cannot get information for the server in class [$class]:  No information has been set."
		unless exists $self->{"__SERVER"} && exists $self->{"__SERVER"}->{$class};

	return wantarray ? @{$self->{"__SERVER"}->{$class}} : $self->{"__SERVER"}->{$class};

} # end sub getServer

sub addClass {

	my $self = shift;
	my $key = shift || confess "Cannot add class:  No class identifier found";
	my $value = shift || confess "Cannot add class:  No class information found";

	confess "Cannot set class [$key]:  Expecting an array ref (instead of [$value])."
		unless ref($value) eq 'ARRAY';

	$self->{"__CLASS"}->{$key} = $value;

	return 1;

} # end sub addClass

sub getClassList {

	my $self = shift;

	confess "Cannot get class list:  No class information has been set." 
		unless exists $self->{"__CLASS"};

	my @classes = keys % { $self->{"__CLASS"} };

	return wantarray ? @classes : [@classes];

} # end sub getClassList

sub getClass {

	my $self = shift;
	my $key = shift || confess "no class identifier found";

	confess "Cannot get information for the class [$key]:  No information has been set."
		unless exists $self->{"__CLASS"} && exists $self->{"__CLASS"}->{$key};

	return wantarray ? @ { $self->{"__CLASS"}->{$key} } : $self->{"__CLASS"}->{$key};

} # end sub getClass

sub addClientClass {

	my $self = shift;
	my $client = shift || confess "Cannot add client class:  No client identifier found";
	my $value = shift || confess "Cannot add client class:  No class identifier found";

	push @ { $self->{"__CLIENTCLASS"}->{$client} }, $value;

	return 1;

} # end sub addClientClasses

sub getClientClassList {

	my $self = shift;
	my $client = shift || confess "Cannot add client classes:  No client identifier found";

	confess "Cannot get class list:  No class information has been set." 
		unless exists $self->{"__CLIENTCLASS"}->{$client};

	my @classes = @ { $self->{"__CLIENTCLASS"}->{$client} };

	return wantarray ? @classes : [@classes];

} # end sub getClientClasses

sub addEvent {

	my $self = shift;
	my $name = shift || confess "Cannot add event:  No event identifier found";
	my $value = shift || confess "Cannot add event:  No event information found";

	confess "Cannot set event [$name]:  Expecting a hash ref (instead of [$value])."
		unless ref($value) eq 'HASH';

	$self->{"__EVENT"}->{$name} = $value;

	return 1;

} # end sub addEvent

sub getEventList {

	my $self = shift;

	confess "Cannot get event list:  No event information has been set." 
		unless exists $self->{"__EVENT"};

	my @events = keys % { $self->{"__EVENT"} };

	return wantarray ? @events : [@events];

} # end sub getEventList

sub getEvent {

	my $self = shift;
	my $name = shift || confess "Cannot get event:  No event identifier found";

	confess "Cannot get information for the event [$name]:  No information has been set."
		unless exists $self->{"__EVENT"} && exists $self->{"__EVENT"}->{$name};

	return wantarray ? @ { $self->{"__EVENT"}->{$name} } : $self->{"__EVENT"}->{$name};

} # end sub getEvent

sub isEvent {

	my $self = shift;
	my $name = shift || confess "Cannot check event:  No event identifier found";

	return exists $self->{"__EVENT"} && exists $self->{"__EVENT"}->{$name};

} # end sub isEvent

sub setConfigurationText {

	my $self = shift;
	my $client = shift;
	my @text = @_;

	confess "Cannot set configuration text:  No client found."
		unless $client;

	confess "Cannot set configuration text:  No text found."
		unless @text;

	$self->{"__CONFIGURATIONTEXT"}->{$client} = join '', @text;

	$self->logger()->debug(1,"Configuration text of " .
		length($self->{"__CONFIGURATIONTEXT"}->{$client}) .
		" added to client [$client].");

	return 1;

} # end sub setConfigurationText

sub getConfigurationText {

	my $self = shift;
	my $client = shift;

	confess "Cannot get configuration text:  It has not been set yet."
		unless exists $self->{"__CONFIGURATIONTEXT"}->{$client};

	return $self->{"__CONFIGURATIONTEXT"}->{$client};

} # end sub getConfigurationText

sub addState {

	my $self = shift;
	my $name = shift || confess "Cannot add state:  No state identifier found";
	my $value = shift || confess "Cannot add state:  No state information found";

	confess "Cannot set state [$name]:  Expecting a hash ref (instead of [$value])."
		unless ref($value) eq 'HASH';

	$self->{"__STATE"}->{$name} = $value;

	return 1;

} # end sub addState

sub getStateList {

	my $self = shift;

	confess "Cannot get state list:  No state information has been set." 
		unless exists $self->{"__STATE"};

	my @states = keys % { $self->{"__STATE"} };

	return wantarray ? @states : [@states];

} # end sub getStateList

sub getState {

	my $self = shift;
	my $name = shift || confess "Cannot get state:  No state identifier found";

	confess "Cannot get information for the state [$name]:  No information has been set."
		unless exists $self->{"__STATE"} && exists $self->{"__STATE"}->{$name};

	return wantarray ? @ { $self->{"__STATE"}->{$name} } : $self->{"__STATE"}->{$name};

} # end sub getState

sub isState {

	my $self = shift;
	my $name = shift || confess "Cannot check state:  No state identifier found";

	return exists $self->{"__STATE"} && exists $self->{"__STATE"}->{$name};

} # end sub isState

sub addClientEvent {

	my $self = shift;
	my $name = shift || confess "Cannot add client event:  No client event identifier found";
	my $value = shift || confess "Cannot add client event:  No client event information found";

	confess "Cannot set client event [$name]:  Expecting a hash ref (instead of [$value])."
		unless ref($value) eq 'HASH';

	my $clientevent = $value->{'name'};

	push @ { $self->{"__CLIENTEVENT"}->{$name} }, $value;

	return 1;

} # end sub addClientEvent

sub getClientEventList {

	my $self = shift;

	confess "Cannot get clientevent list:  No clientevent information has been set." 
		unless exists $self->{"__CLIENTEVENT"};

	my @clientevents;

	for my $client (keys % { $self->{"__CLIENTEVENT"} }) {
		push @clientevents, @ { $self->{"__CLIENTEVENT"}->{$client} };
	}

	return wantarray ? @clientevents : [@clientevents];

} # end sub getClientEventList

sub getClientEvents {

	my $self = shift;
	my $name = shift || confess "Cannot get clientevent:  No clientevent identifier found";

	confess "Cannot get information for the clientevent [$name]:  No information has been set."
		unless exists $self->{"__CLIENTEVENT"} && exists $self->{"__CLIENTEVENT"}->{$name};

	return wantarray ? @ { $self->{"__CLIENTEVENT"}->{$name} } : $self->{"__CLIENTEVENT"}->{$name};

} # end sub getClientEvents

sub addClientHost {

	my $self = shift;
	my $name = shift || confess "Cannot add client host:  No client host identifier found";
	my $value = shift || confess "Cannot add client host:  No client host information found";

	confess "Cannot set client host [$name]:  Expecting a hash ref (instead of [$value])."
		unless ref($value) eq 'HASH';

	my $clienthost = $value->{'name'};

	push @ { $self->{"__CLIENTHOST"}->{$name} }, $value;

	return 1;

} # end sub addClientHost

sub getClientHostList {

	my $self = shift;

	confess "Cannot get clienthost list:  No clienthost information has been set." 
		unless exists $self->{"__CLIENTHOST"};

	my @clienthosts;

	for my $client (keys % { $self->{"__CLIENTHOST"} }) {
		push @clienthosts, @ { $self->{"__CLIENTHOST"}->{$client} };
	}

	return wantarray ? @clienthosts : [@clienthosts];

} # end sub getClientHostList

sub getClientHosts {

	my $self = shift;
	my $name = shift || confess "Cannot get clienthost:  No clienthost identifier found";

	confess "Cannot get information for the clienthost [$name]:  No information has been set."
		unless exists $self->{"__CLIENTHOST"} && exists $self->{"__CLIENTHOST"}->{$name};

	return wantarray ? @ { $self->{"__CLIENTHOST"}->{$name} } : $self->{"__CLIENTHOST"}->{$name};

} # end sub getClientHosts

sub optionExists {

	my $self = shift;
	my $option = shift || confess "Cannot determine existence of option:  Option name not specified.";
	return exists $self->{"__OPTIONS"}->{$option};

} # end sub optionExists

sub setOption {

	my $self = shift;
	my $option = shift || confess "Cannot set option:  Option name not specified.";
	if (@_) {
		my $value = shift;
		$self->{"__OPTIONS"}->{$option} = $value;
		return 1;
	} else {
		confess "Cannot set option [$option]:  The option value was not found.";
	}

} # end sub setOption

sub getOption {

	my $self = shift;
	my $option = shift || confess "Cannot get option:  Option name not specified.";
	confess "Cannot get option [$option]:  The option value has not been set yet."
		unless exists $self->{"__OPTIONS"}->{$option};
	return $self->{"__OPTIONS"}->{$option};

} # end sub option

sub getOptions {

	# returns the names of all of the currently set options
	my $self = shift;
	return wantarray 
		? ( keys % { $self->{"__OPTIONS"} } )
		: [ keys % { $self->{"__OPTIONS"} } ];

} # end sub getOptions

sub getOptionsHash {

	# returns the names of all of the currently set options
	my $self = shift;
	my %return;
	for my $option (keys % { $self->{"__OPTIONS"} }) {
		$return{$option} = $self->getOption($option);
	}
	return % { $self->{"__OPTIONS"} };

} # end sub getOptionHash

1;

__END__

=head1 NAME

Peep::Conf - Perl extension for providing an object representation of
configuration information for Peep: The Network Auralizer.

=head1 SYNOPSIS

  use Peep::Conf;
  my $conf = new Peep::Conf;
  $conf->setBroadcast($class0,$value0);
  $conf->setBroadcast($class1,$value1);
  $conf->getBroadcastList();

=head1 DESCRIPTION

Peep::Conf provides an object interface for Peep configuration
information, typically extracted from a Peep configuration file (e.g.,
/etc/peep.conf) by the Peep::Parse module.

=head1 EXPORT

None by default.

=head1 PUBLIC METHODS

  setApp($appname) - A unique identifier associated with a client
  configuration.  Typically the name of the application using the
  configuration information; e.g., logparser.

  getApp() - Returns the identifier set with setApp.

  getPort() - Returns the port set with setPort.

  setPort($port) - Sets a port number.  Typically the client broadcast
  port.

  getBroadcastList() - Returns a list of all broadcast names
  associated with all classes.

  getBroadcast($class) - Gets the broadcast string for the class
  $class.

  addBroadcast($class,$value) - Adds the broadcast string
  (consisting of IP/domain and port) named $name for the class $class.

  getClassList() - Returns a list of all class names that have
  associated server lists.

  getClass($class) - Returns a list of servers associated with the
  class $class.

  setClass($class,$arrayref) - Associates the class $class with the
  list of servers given in $arrayref.

  getEventList() - Returns a list of all event names.

  getEvent($event) - Returns the event information for the event with
  name $event.

  setEvent($event,$hashref) - Associates the event $event with the
  information contained in $hashref.

  getStateList() - Returns a list of all state names.

  getState($state) - Returns the state information associated with the
  state $state.

  setState($event,$hashref) - Associates the state $state with the
  information contained in $hashref.

  setConfigurationText($text) - Sets the configuration text to $text.

  getConfigurationText() - Returns the configuration text.

  setClientEvent($name,$arrayref) - Sets the events associated with
  the client $name.

  getClientEvents($name) - Returns the events associated with the client $name.

  getClientEventList() - Returns all events associated with all clients.

=head1 AUTHOR

Collin Starkweather Copyright (C) 2001

=head1 SEE ALSO

perl(1), peepd(1), Peep::BC, Peep::Parse, Peep::Log.

http://peep.sourceforge.net

=head1 TERMS AND CONDITIONS

You should have received a file COPYING containing license terms
along with this program; if not, write to Michael Gilfix
(mgilfix@eecs.tufts.edu) for a copy.

This version of Peep is open source; you can redistribute it and/or
modify it under the terms listed in the file COPYING.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

=head1 CHANGE LOG

$Log: Conf.pm,v $
Revision 1.7  2001/04/17 06:46:21  starky
Hopefully the last commit before submission of the Peep client library
to the CPAN.  Among the changes:

o The clients have been modified somewhat to more elagantly
  clean up pidfiles in response to sigint and sigterm signals.
o Minor changes have been made to the documentation.
o The Peep::Client module searches through a host of directories in
  order to find peep.conf if it is not immediately found in /etc or
  provided on the command line.
o The make test script conf.t was modified to provide output during
  the testing process.
o Changes files and test.pl files were added to prevent specious
  complaints during the make process.

Revision 1.6  2001/03/31 07:51:35  mgilfix


  Last major commit before the 0.4.0 release. All of the newly rewritten
clients and libraries are now working and are nicely formatted. The server
installation has been changed a bit so now peep.conf is generated from
the template file during a configure - which brings us closer to having
a work-out-of-the-box system.

Revision 1.6  =head1 CHANGE LOG
 
$Log: Conf.pm,v $
Revision 1.7  2001/04/17 06:46:21  starky
Hopefully the last commit before submission of the Peep client library
to the CPAN.  Among the changes:

o The clients have been modified somewhat to more elagantly
  clean up pidfiles in response to sigint and sigterm signals.
o Minor changes have been made to the documentation.
o The Peep::Client module searches through a host of directories in
  order to find peep.conf if it is not immediately found in /etc or
  provided on the command line.
o The make test script conf.t was modified to provide output during
  the testing process.
o Changes files and test.pl files were added to prevent specious
  complaints during the make process.

Revision 1.6  2001/03/31 07:51:35  mgilfix


  Last major commit before the 0.4.0 release. All of the newly rewritten
clients and libraries are now working and are nicely formatted. The server
installation has been changed a bit so now peep.conf is generated from
the template file during a configure - which brings us closer to having
a work-out-of-the-box system.

Revision 1.7  2001/03/31 02:17:00  mgilfix
Made the final adjustments to for the 0.4.0 release so everything
now works. Lots of changes here: autodiscovery works in every
situation now (client up, server starts & vice-versa), clients
now shutdown elegantly with a SIGTERM or SIGINT and remove their
pidfiles upon exit, broadcast and server definitions in the class
definitions is now parsed correctly, the client libraries now
parse the events so they can translate from names to internal
numbers. There's probably some other changes in there but many
were made :) Also reformatted all of the code, so it uses
consistent indentation.

Revision 1.5  2001/03/28 02:41:48  starky
Created a new client called 'pinger' which pings a set of hosts to check
whether they are alive.  Made some adjustments to the client modules to
accomodate the new client.

Also fixed some trivial pre-0.4.0-launch bugs.

Revision 1.4  2001/03/27 05:49:04  starky
Modified the getClientPort method to accept the 'port' option as
specified on the command line if no client has been specified in the
conf file.

Revision 1.3  2001/03/27 00:44:19  starky
Completed work on rearchitecting the Peep client API, modified client code
to be consistent with the new API, and added and tested the sysmonitor
client, which replaces the uptime client.

This is the last major commit prior to launching the new client code,
though the API or architecture may undergo some initial changes following
launch in response to comments or suggestions from the user and developer
base.

Revision 1.2  2001/03/18 17:17:46  starky
Finally got LogParser (now called logparser) running smoothly.

Revision 1.1  2001/03/16 18:31:59  starky
Initial commit of some very broken code which will eventually comprise
a rearchitecting of the Peep client libraries; most importantly, the
Perl modules.

A detailed e-mail regarding this commit will be posted to the Peep
develop list (peep-develop@lists.sourceforge.net).

Contact me (Collin Starkweather) at

  collin.starkweather@colorado.edu

or

  collin.starkweather@collinstarkweather.com

with any questions.


=cut
