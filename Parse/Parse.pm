package Peep::Parse;

require 5.005_62;
use strict;
use warnings;
use Carp;
use Data::Dumper;
use Peep::Log;
use Peep::Conf;

require Exporter;

our @ISA = qw(Exporter);
our %EXPORT_TAGS = ( 'all' => [ qw( ) ] );
our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } );
our @EXPORT = qw( );
our $VERSION = do { my @r = (q$Revision: 1.6 $ =~ /\d+/g); sprintf "%d."."%02d" x $#r, @r };

sub new {

	my $self = shift;
	my $class = ref($self) || $self;
	my $this = {};
	bless $this, $class;

} # end sub new

# On spawning a new configuration file parser, we expect to get
# a reference to a hash that contains:
#   'config' => Which is a pointer to the configuration file
#   'app'    => The application for which to get the configuration
sub loadConfig {
	my $self = shift;
	my $configuration = shift || confess "Error:  No configuration object found.";

	$self->setConfigObject($configuration);

	confess "Peep couldn't find the configuration file '", $configuration->getOption('config'), "': $!" 
		unless -e $configuration->getOption('config');

	$self->parseConfig();

#    print STDERR "Returning ", ref($self->configObject()), " object:\n\n", Dumper($self->configObject());

	return 1;

} # end sub loadConfig

sub setConfigObject {

	my $self = shift;
	$self->{"__CONFIGOBJECT"} = shift || confess "Error:  No configuration object found.";
	return 1;

} # end sub setConfigObject

sub configObject {

	my $self = shift;
	unless (exists $self->{"__CONFIGOBJECT"}) {
		confess "Error:  The configuration object has not been set yet.";
	}
	return $self->{"__CONFIGOBJECT"};

} # end sub configObject

sub parseConfig {

	my $self = shift;

	my $configfile = $self->configObject()->getOption('config');

	open FILE, "<$configfile" || confess "Could not open [$configfile]:  $!";
	while (my $line = <FILE>) {
		my $msg = $line;
		chomp $msg;
		$msg = substr $msg, 0, 40;
		$self->logger()->debug(9,"Parsing [$configfile] line [$msg ...]");
		next if $line =~ /^\s*#/;
		$self->parseClass(\*FILE, $1)  if $line =~ /^\s*class (.*)/;
		$self->parseClient(\*FILE, $1) if $line =~ /^\s*client (.*)/;
		$self->parseEvents(\*FILE, $1)     if $line =~ /^\s*events/;
		$self->parseStates(\*FILE, $1)     if $line =~ /^\s*states/;
	}
	close FILE;

} # end sub parseConfig

sub parseClass {
	my $self = shift;
	my $file      = shift || confess "file not found";
	my $classname = shift || confess "classname not found";
	my (@broadcast, @servers, $newbroadcast);
	my %servports;

	$self->logger()->debug(1,"Parsing class [$classname] ...");

	while (my $line = <$file>) {
		if ($line =~ /^\s*end/) {
			#Then check if we should make an entry
			if (@broadcast && @servers) {
				$self->configObject()->addClass($classname,\@servers);

				#We need the same broadcast zones as the servers but
				#We need the different server ports.
				foreach my $server (@servers) {
					my ($name, $port) = split /:/, $server;
					$self->configObject()->addServer($classname,{ name => $name, port => $port });
					$self->logger()->debug(1,"\tServer [$name:$port] added.");
					$servports{$port} = 1; #define the key
				}
				foreach my $zone (@broadcast) {
					my ($ip, $port) = split /:/, $zone;
					$self->logger()->debug(1,"\tBroadcast [$ip:$port] added.");
					$self->configObject()->addBroadcast($classname,{ ip => $ip, port => $port });
				}
			}
			return;
		}

		push (@broadcast, split(/\s+/, $1) ) if $line =~ /^\s*broadcast (.*)/;
		push (@servers, split (/\s+/, $1) ) if $line =~ /^\s*server (.*)/;

	}

} # end sub parseClass

sub parseClient {

	my $self = shift;

	my $file   = shift || confess "Cannot parse client:  File not found";
	my $client = shift || confess "Cannot parse client:  Client not found";
	my %classes;

	$self->logger()->debug(1,"Parsing client [$client] ...");

	# Let's figure out which classes we're part of and grab the
	# program's configuration
	while (my $line = <$file>) {

		last if $line =~ /^\s*end client $client/;
		next if $line =~ /^\s*#/;

		if ($line =~ /^\s*class(.*)/) {
			my $class = $1;
			$class =~ s/\s+//g;
			my @classes = split /\s+/, $class;
			foreach my $one (@classes) {
				$classes{$one} = $self->configObject()->getClass($one);
			}
		}

		if ($line =~ /^\s*port (\d+)/) {
			my $port = $1;
			$port =~ s/\s+//g;
			$self->configObject()->setClientPort($client,$port);
			$self->logger()->debug(1,"\tPort [$port] set for client [$client].");
		}

		# Note that config specifically looks for "end config" because
		# it may contain several starts and ends
		if ($line =~ /^\s*config/) {
			my @config;

			while (my $line = <$file>) {
				last if $line =~ /^\s*end config/;
				push @config, $line;
	    }

			$self->parseClientConfig($client,@config);
			# I believe the parseClientEvents makes this redundant
			$self->configObject()->setConfigurationText($client,join '', @config);
		}
	}

	# Now let's swap in the valid classes
	for my $class (keys %classes) { $self->configObject()->addClientClass($client,$class); }

} # end sub parseClient

sub parseEvents {

	my $self = shift;
	my $file = shift || confess "Cannot parse events:  File not found.";

	$self->logger()->debug(1,"Parsing events ...");

	my $i = 0;
	# Skip right to the end
	while (my $line = <$file>) {
		last if $line =~ /^\s*end/;
		next if $line =~ /^\s*#/;
		my ($eventname, $file, $nsounds) = split /\s+/, $line;

		$self->configObject()->addEvent($eventname,{
			file => $file,
			sounds => $nsounds,
			index => $i++
		});

		$self->logger()->debug(1,"\tEvent [$eventname] added.");
	}

} # end sub parseEvents

sub parseClientConfig {

	my $self = shift;
	my $client = shift || confess "Cannot parse client configuration:  Client not identified.";
	my @text = @_;

	$self->logger()->debug(1,"\tParsing configuration for client [$client] ...");

	while (my $line = shift @text) {
		next if $line =~ /^\s*#/;
		next if $line =~ /^\s*$/;

		if ($line =~ /^\s*default/) {
			@text = $self->parseClientDefault($client,@text);
		} elsif ($line =~ /^\s*events/) {
			@text = $self->parseClientEvents($client,@text);
		} elsif ($line =~ /^\s*hosts/) {
			@text = $self->parseClientHosts($client,@text);
		} else {
			$line =~ /^\s*(\w+)\s+(\S+)/;
			$self->logger()->debug(1,"\t\tClient option [$1] has been set to value [$2].");
			$self->configObject()->setOption($1,$2);
		}
	}

} # end sub parseClientConfig

sub parseClientEvents {

	my $self = shift;
	my $client = shift || confess "Cannot parse client events:  Client not identified.";
	my @text = @_;

	$self->logger()->debug(1,"\t\tParsing events for client [$client] ...");

	while (my $line = shift @text) {
		next if $line =~ /^\s*#/;
		last if $line =~ /^\s*end/;

		my $name;
		$line =~ /([\w-]+)\s+([a-zA-Z])\s+(\d+)\s+(\d+)\s+"(.*)"/;

		my $clientEvent = {
			'name' => $1,
			'option-letter' => $2,
			'location' => $3,
			'priority' => $4,
			'regex' => $5
	};

		$self->configObject()->addClientEvent($client,$clientEvent);
		$self->logger()->debug(1,"\t\t\tClient event [$1] added.");

	}

	return @text;

} # end sub parseClientEvents

sub parseClientHosts {

	my $self = shift;
	my $client = shift || confess "Cannot parse client hosts:  Client not identified.";
	my @text = @_;

	$self->logger()->debug(1,"\t\tParsing hosts for client [$client] ...");

	while (my $line = shift @text) {
		next if $line =~ /^\s*$/;
		next if $line =~ /^\s*#/;
		last if $line =~ /^\s*end/;

		$line =~ /^\s*([\w\-\.]+)\s+([\w-]+)/;

		my ($name,$event) = ($1,$2);

		my $clientHost = {
			name => $name,
			event => $event
		};

		$self->configObject()->addClientHost($client,$clientHost);
		$self->logger()->debug(1,"\t\t\tClient host [$name] added.");

	}

	return @text;

} # end sub parseClientHosts

sub parseClientDefault {

	my $self = shift;
	my $client = shift || confess "Cannot parse client defaults:  Client not identified.";
	my @text = @_;

	$self->logger()->debug(1,"\tParsing defaults for client '$client' ...");

	while (my $line = shift @text) {
		next if $line =~ /^s*#/;
		last if $line =~ /^\s*end/;

		if ($line =~ /^\s*events(.*)/) {
			my $events = $1;
			$events =~ s/\s+//g;

			if ($self->configObject()->optionExists('events')) {
				$self->logger()->debug(1,"\t\tEvent string [$events] not set:  It was set previously.");
			} else {
				$self->configObject()->setOption('events',$events);
				$self->logger()->debug(1,"\t\tEvent string set to [$events].");
			}
		}

		if ($line =~ /^\s*logfile(.*)/) {
			my $logfile = $1;
			$logfile =~ s/\s+//g;

			if ($self->configObject()->optionExists('logfile')) {
				$self->logger()->debug(1,"\t\tLog file [$logfile] not set:  It was set previously.");
			} else {
				$self->configObject()->setOption('logfile',$logfile);
				$self->logger()->debug(1,"\t\tLog file set to [$logfile].");
			}
		}

	}

	return @text;

} # end sub parseClientDefault

sub parseStates {

	my $self = shift;

	my $file = shift || confess "Cannot parse states:  File not found.";

	$self->logger()->debug(1,"Parsing states ...");

	my $i = 0;
	# Skip right to the end 
	while (my $line = <$file>) {
		last if $line =~ /^\s*end/;
		next if $line =~ /^\s*#/;
		my ($statename, $file, $sounds, $fade) = split /\s+/, $line;

		$self->configObject()->addState($statename,{
			file => $file,
			sounds => $sounds,
			fade => $fade,
			index => $i++
		});

		$self->logger()->debug(1,"\tState [$statename] added.");
	}

} # end sub parseStates

# returns a logging object
sub logger {
	my $self = shift;
	if ( ! exists $self->{'__LOGGER'} ) { $self->{'__LOGGER'} = new Peep::Log }
	return $self->{'__LOGGER'};
} # end sub logger

1;

__END__

=head1 NAME

Peep::Parse - Perl extension for parsing configuration files for Peep:
The Network Auralizer.

=head1 SYNOPSIS

  use Peep::Parse;
  my $parser = new Peep::Parse;

  # loadConfig returns a Peep::Conf object

  my $config = $parser->loadConfig(config => '/etc/peep.conf', app => 'LogParser');

  # all of the configuration information in /etc/peep.conf
  # is now available through the observer methods in the
  # Peep::Conf object

=head1 DESCRIPTION

Peep::Parse parses a Peep configuration file and returns a Peep::Conf
object whose accessors contain all the information found in the
configuration file.

=head2 EXPORT

None by default.

=head2 METHODS

  loadConfig(%options) - loads configuration information found in the
  file $options{'config'} for application $options{'app'}.  Returns a
  Peep::Conf object.

  parseConfig($config) - parses the configuration file $config.

  parseClass($filehandle,$classname) - parses the class definition
  section of a configuration file.

  parseClient($filehandle,$client) - parses the client definition
  section of a configuration file.

  parseEvents($filehandle) - parses the event definition section of a
  configuration file.

  parseState($filehandle) - parses the state definition section of a
  configuration file.

  parseClientEvents($filehandle) - parses the client event definition
  section of a configuration file.

  parseClientDefault($filehandle) - parses the client defaults section
  of a configuration file.

  logger() - returns a Peep::Log object for logging and debugging.

  configObject() - returns a Peep::Conf object for storing and
  retrieving configuration information.

=head1 AUTHOR

Michael Gilfix Copyright (C) 2000

=head1 SEE ALSO

perl(1), peepd(1), Peep::BC, Peep::Dumb, Peep::Log, Peep::Conf.

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

$Log: Parse.pm,v $
Revision 1.6  2001/03/31 07:51:35  mgilfix


  Last major commit before the 0.4.0 release. All of the newly rewritten
clients and libraries are now working and are nicely formatted. The server
installation has been changed a bit so now peep.conf is generated from
the template file during a configure - which brings us closer to having
a work-out-of-the-box system.

Revision 1.6   2001/03/31 02:17:00  mgilfix
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

Revision 1.5  2001/03/28 02:54:20  starky
Fixed a bug in the regex in the parseClientHosts method.

Revision 1.4  2001/03/28 02:41:48  starky
Created a new client called 'pinger' which pings a set of hosts to check
whether they are alive.  Made some adjustments to the client modules to
accomodate the new client.

Also fixed some trivial pre-0.4.0-launch bugs.

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

