package Peep::BC;

require 5.005_62;
use strict;
use warnings;
use Carp;

require Exporter;

our @ISA = qw(Exporter);
our %EXPORT_TAGS = ( 'all' => [ qw( ) ] );
our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } );
our @EXPORT = qw( );
our $VERSION = do { my @r = (q$Revision: 1.9 $ =~ /\d+/g); sprintf "%d."."%02d" x $#r, @r };

use Socket;
use Sys::Hostname;
use Peep::Parse;
use Peep::Conf;
use Peep::Log;

use vars qw{ %Leases %Servers %Defaults $Alarmtime };

%Leases = %Servers = ();

%Defaults = (
	type => 0,
	location => 128,
	priority => 0,
	volume => 128,
	dither => 0,
	sound => 0
);

$Alarmtime = 30;

# Peep protocol constants
use constant PROT_MAJORVER => 1;
use constant PROT_MINORVER => 0;
use constant PROT_BCSERVER => 0;
use constant PROT_BCCLIENT => 1;
use constant PROT_SERVERSTILLALIVE => 2;
use constant PROT_CLIENTSTILLALIVE => 3;
use constant PROT_CLIENTEVENT => 4;
use constant PROT_CLASSDELIM => '!';

sub new {

	my $self = shift;
	my $class = ref($self) || $self;
	my $this = {};
	bless $this, $class;

	$this->initialize(@_);

	return $this;

} # end sub new

sub initialize {

	my $self = shift;
	my $client = shift || confess "Error:  Client not found";
	my $configuration = shift || confess "Error:  Configuration not found";

	# put the configuration object in a place where all the other
	# methods can find it
	$self->setConfiguration($configuration);

	my %options = $configuration->getOptionsHash();

	# FIXIT: This is silly and redundant.  The object that instantiates
	# the Peep::BC object already has all of the options set and a
	# configuration object.  Peep::BC shouldn't need to build its own
	# stable of options.  Deal with it later ....

	# Populate the object attributes either by the class default
	# attributes or the options arguments passed in

	for my $key (keys %Defaults) {
		if ($key ne 'dither') {
			if (exists $options{$key}) {
				$self->setOption($key,$options{$key});
			} else {
				$self->setOption($key,$Defaults{$key});
			}
		}
	}

	# Make allowances for the two possible meanings of dither
	# dither is based exclusively on the value of 'type'
	$self->getOption('type') ? $self->setOption('dither',255) : $self->setOption('dither',0);

	# Now initialize our socket
	my $port = $configuration->getClientPort($client);
	$self->logger()->debug(7,"Initializing socket on port $port ...");
	my $addr = INADDR_ANY;
	my $proto = getprotobyname('udp');
	my $paddr = sockaddr_in($port, $addr);
	socket(SOCKET, PF_INET, SOCK_DGRAM, $proto) or confess "Socket error: $!";
	if ($configuration->getOption('autodiscovery')) {
		bind(SOCKET, $paddr)                        or confess "Bind error: $!";
	}
	$self->logger()->debug(7,"\tSocket initialized.");

	#Set the socket option for the broadcast
	setsockopt SOCKET, SOL_SOCKET, SO_BROADCAST | SO_REUSEADDR, 1;

	# Send out our broadcast to let everybody know we're alive
	# Note - we want to send these broadcasts to the servers within
	# the class definition. So, we use getServer() - Mike
	for my $class ($configuration->getClassList()) {
		$self->logger()->debug(9,"Getting broadcast for class [$class]");
		my $broadcasts = $configuration->getServer($class);

		for my $broadcast (@$broadcasts) {
			my ($zone, $port) = ($broadcast->{'name'}, $broadcast->{'port'});
			$self->logger()->debug(9,"Socketing to zone [$zone] and port [$port] ...");
			my $iaddr = inet_aton($zone);
			my $bcaddr = sockaddr_in($port, $iaddr);

			#Assemble the packet and send it
			my $packet = $self->assemble_bc_packet($configuration);
			$self->logger()->debug(9,"Sending a friendly hello to address [$zone:$port] ...");
			defined(send(SOCKET, $packet, 0, $bcaddr)) or confess "Send broadcast error: $!";
			$self->logger()->debug(9,"\tPacket of length ".length($packet)." sent.");
		}
	}

	#Start up the alarm. Once this handler gets started, we'll have it
	#work concurrently with the program to handle host lists
	if ($configuration->getOption('autodiscovery')) {
		$SIG{'ALRM'} = sub { $self->handlealarm() };
		alarm($Alarmtime);
	}

} # end sub initialize

sub getConfiguration {

	my $self = shift;
	confess "Error retrieving configuration:  The configuration has not been set yet."
	unless exists $self->{"__CONFIGURATOR"};
	return $self->{"__CONFIGURATOR"};

} # end sub getConfiguration

sub setConfiguration {

	my $self = shift;
	if (@_) {
		$self->{"__CONFIGURATOR"} = shift;
	} else {
		confess "Cannot set configuration:  No configuration object found.";
	}
	return 1;

} # end sub setConfiguration

# Function to assemble a broadcast packet with an appropriate
# identifier string
sub assemble_bc_packet {

	my $self = shift;
	my $configuration = $self->getConfiguration();
	my $identifier = join PROT_CLASSDELIM, ($configuration->getClassList()), PROT_CLASSDELIM;
	return pack("CCCCA128", PROT_MAJORVER,
		PROT_MINORVER,
		PROT_BCCLIENT, 
		0, 
		$identifier);

} # end sub assemble_bc_packet

# returns a logging object
sub logger {

	my $self = shift;
	if ( ! exists $self->{'__LOGGER'} ) { $self->{'__LOGGER'} = new Peep::Log }
	return $self->{'__LOGGER'};

} # end sub logger

sub close {

	my $self = shift;
	close SOCKET;

} # end sub close

# Send out a packet
sub send {

	my $self = shift;
	my %options = @_;

	$self->logger()->debug(7,"Sending packet to server(s) ...");

	my $configuration = $self->getConfiguration();

	my $type = $options{'type'} || $self->getOption('type');
	my $location = $options{'location'} || $self->getOption('location');
	my $priority = $options{'priority'} || $self->getOption('priority');
	my $volume = $options{'volume'} || $self->getOption('volume');
	my $dither = $options{'dither'} || $self->getOption('dither');
	my $sound = $options{'sound'} || $self->getOption('sound');

	$self->logger()->debug(9,"type=[$type] location=[$location] priority=[$priority] volume=[$volume] dither=[$dither] sound=[$sound]");

	#Now convert the sound name into the number if it isn't a number already
	if ($sound !~ /\d+/) {
		my $hash;
		$hash = $configuration->getEvent($sound) if $configuration->isEvent($sound);
		$hash = $configuration->getState($sound) if $configuration->isState($sound);

		if (ref($hash)) {
			my $index = $hash->{'index'};
			$self->logger()->debug(5,"Sound [$sound] reassigned:  Now it is [$index]");
			$sound = $index;
		} else {
			$self->logger()->log(ref($self),": Warning: Asking Peep to play a non existent sound: [$sound]");
			return;
		}
	}

	if ($configuration->getOption('autodiscovery')) {

		# Now sendout to all the servers in our server list
		for my $server (keys %Servers) {
			my ($serverport,$serverip) = unpack_sockaddr_in($server);
			$serverip = inet_ntoa($serverip);
			$self->logger()->debug(7,"Notifying server [$serverip:$serverport] of event or sound [$sound] ...");
			$self->sendout($type, $sound, $location, $priority, $volume, $dither, $server);
		}

	} else {

		# Just send a packet to the server and port specified on the command-line
		my $port = $configuration->getOption('port') || confess "Error:  Expecting nonzero port!";
		my $host = $configuration->getOption('server') || confess "Error:  Expecting nonzero host!";
		$self->logger()->debug(7,"Notifying server [$host:$port] of event or sound [$sound] ...");
		$host = inet_aton($host);
		my $server = sockaddr_in($port,$host);
		$self->sendout($type, $sound, $location, $priority, $volume, $dither, $server);

	}

} # end sub send

sub sendout {

	my $self = shift;
	my ($type,$sound,$location,$priority,$volume,$dither,$server) 
	    = @_;
	my $mix_in_time = 0;

	my ($serverport,$serverip) = unpack_sockaddr_in($server);
	$serverip = inet_ntoa($serverip);
	$self->logger()->debug(7,"type=[$type] sound=[$sound] location=[$location] priority=[$priority] volume=[$volume] dither=[$dither] server=[$serverip:$serverport]") ;

	#Now we need to build the appropriate network packet
	my $packet = pack("CCCCC8",
		PROT_MAJORVER,
		PROT_MINORVER,
		PROT_CLIENTEVENT,
		0,
		$type, $sound, $location, $priority, $volume, $dither);

	if (not defined(CORE::send(SOCKET, $packet, 0, $server))) {
		$self->logger()->debug(7,"Error sending packet to [$serverip:$serverport]:  $!");
		$self->logger()->debug(7,"You may want to check that the server is accepting connections on port [$serverport].");
	}

	return 1;

} # end sub sendout

sub setOption {

	my $self = shift;
	my $option = shift || confess "option not found";
	my $value = shift;
	confess "value not found" unless defined $value;
	$self->{"__OPTIONS"}->{$option} = $value;
	return 1;

} # end sub setOption

sub getOption {

	my $self = shift;
	my $option = shift || confess "option not found";

	if (exists $self->{"__OPTIONS"}->{$option}) {
		return $self->{"__OPTIONS"}->{$option};
	} else {
		confess "Cannot get the option '$option':  It has not yet been set.";
	}

	return 0;

} # end sub setOption

sub handlealarm {

	#Every tick, we wait until we have some input to respond to, then update
	#our server list. Finally, we purge the server list of any impurities and
	#carry on with out business
	my $self = shift;

	$self->updateserverlist();
	$self->purgeserverlist();

	$SIG{'ALRM'} = sub { $self->handlealarm() };
	alarm($Alarmtime); 

	return 1;

} # end sub handlealarm

sub updateserverlist {

	#Poll to see if we've received anything so we can update the server list 
	#before we send. Then, send out the packet.
	my $self = shift;

	$self->logger()->debug(9,"Updating server list ...");

	my $rin = "";
	my $rout;
	vec($rin, fileno(SOCKET), 1) = 1;

	if (select($rout = $rin, undef, undef, 0.1)) {
		my $packet;

		$self->logger()->debug(9,"\tReading from socket ...");

		my $server = recv(SOCKET, $packet, 256, 0);  # 256 is safe amount to read
		# Adding a defined argument here because recv can produce errors if
		# a broadcast isn't responded to. Plus, we want to continue anyway.
		if (defined($server) and $server ne '') {
			my ($serverport,$serverip) = unpack_sockaddr_in($server);
			$serverip = inet_ntoa($serverip);

			$self->logger()->debug(7,"\tJust received a packet from [$serverip:$serverport] ...");

			#Verify that this is a server bc packet
			my ($majorver, $minorver, $type, $padding) = unpack("CCCC", $packet);

			$self->addnewserver($server, $packet) if $type == PROT_BCSERVER;
			$self->logger()->debug(7,"\tUpdating server with profile [$majorver:$minorver:$type]") if $type == PROT_SERVERSTILLALIVE;
			$self->updateserver($server, $packet) if $type == PROT_SERVERSTILLALIVE;
		}
	}

} # end updateserverlist

sub purgeserverlist {

	my $self = shift;

	$self->logger()->debug(9,"Purging server list ...");

	for my $server (keys %Servers) {
		if ($Servers{$server}->{'expires'} <= time()) {
			delete $Servers{$server};
			$self->logger()->debug(7,"\tServer purged. Number of known servers: " . scalar (keys %Peep::Servers));

			for my $known (keys %Peep::Servers) {
				my ($serverport,$serverip) = unpack_sockaddr_in($server);
				$serverip = inet_ntoa($serverip);
				$self->logger()->debug(7,"\t\t$serverip:$serverport");
			}
		}
	}

} # end sub purgeserverlist

sub addnewserver {

	my $self = shift;

	my ($server, $packet) = @_;

	my $configuration = $self->getConfiguration();

	my ($serverport,$serverip) = unpack_sockaddr_in($server);

	$serverip = inet_ntoa($serverip);

	# Check if this server already exists - because then we shouldn't be
	# doing an add... so abort. This can happen because when the client
	# registers with the server, the server always sends a BC response
	# directly back to the client to make sure that the client really
	# has the server in its hostlist
	if (exists $Servers{$server}) {
		$self->logger()->debug(7,"\tServer [$serverip:$serverport] won't be added to the server list:  It is already in the list.");
		return;
	}

	my ($majorver, $minorver, $type, $padding, $min, $sec, $id) = unpack("CCCCCCA128", $packet);
	my $delim = PROT_CLASSDELIM;

	#Clean up the ID string
	$id =~ /([A-Za-z0-9!\-]*)/;
	my $realid = $1;

	foreach my $class ($configuration->getClassList()) {
		#my $str = quotemeta($class.$delim);
		#       the below is a kludge of the above to get it to work with my
		#       humble conf file - gotta figure this out at some point
			my $str = quotemeta($class);
		$self->logger()->debug(7,"\tChecking server id [$realid] against class descriptor [$str] ....");

		if ($realid =~ /$str/) {
			$self->logger()->debug(7,"\tAdding server [$serverip:$serverport] to the server list.");
			$self->addserver($server, $min, $sec);
		} else {
			$self->logger()->debug(7,"\tNo match found.  Nothing added to server list.");
		}
	}

	return 1;

} # end sub addnewserver

sub addserver {

	my $self = shift;
	my ($server,$leasemin,$leasesec) = @_;

	$Servers{$server}->{'IP'} = $server;
	$Servers{$server}->{'expires'} = time() + $leasemin*60 + $leasesec;

	$self->logger()->debug(7,"\tServer added. Number of known servers: " . scalar(keys %Servers));
	for my $known (keys %Peep::Servers) {
		my ($serverport,$serverip) = unpack_sockaddr_in($known);
		$serverip = inet_ntoa($serverip);
		$self->logger()->debug(7,"\t\t$serverip:$serverport");
	}

	#Let's send it a "BC" to tell it to add us as well
	my ($serverport,$serverip) = unpack_sockaddr_in($server);
	$serverip = inet_ntoa($serverip);
	$self->logger()->debug(7,"\tSending client BC packet to [$serverip:$serverport] ...");
	defined(CORE::send(SOCKET, $self->assemble_bc_packet(), 0, $server)) or confess "Send clientbc error: $!";
	$self->logger()->debug(7,"\tClient BC packet sent successfully.");

	return 1;

} # end sub addserver

sub updateserver {

	my $self = shift;
	my $server = shift;
	my $packet = shift;
	my ($majorver, $minorver, $type, $padding, $min, $sec) = unpack("CCCCCC", $packet);

	$self->logger()->debug(7,"\tServer updated. Number of known servers: " . scalar(keys %Servers));

	$Servers{$server}->{'expires'} = time() + $min*60 + $sec;

	# New send out a client alive
	my $net_packet = pack ("CCCC",
		PROT_MAJORVER,
		PROT_MINORVER,
		PROT_CLIENTSTILLALIVE, 
		0);

	$self->logger()->debug(7,"\tSending client still alive packet ...");
	defined(CORE::send(SOCKET, $net_packet, 0, $server)) or confess "Send client still alive error: $!"; 
	$self->logger()->debug(7,"\tClient still alive packet sent successfully.");

	return 1;

} # end sub updateserver

1;

__END__

=head1 NAME

Peep::BC - Perl extension for Peep: The Network Auralizer

=head1 SYNOPSIS

  use Peep::BC;
  my $bc = new Peep::BC;

=head1 DESCRIPTION

Peep::BC is a library for Peep: The Network Auralizer.

=head2 EXPORT

None by default.

=head2 CONSTANTS

  PROT_MAJORVER

  PROT_MINORVER

  PROT_BCSERVER

  PROT_BCCLIENT

  PROT_SERVERSTILLALIVE

  PROT_CLIENTSTILLALIVE

  PROT_CLIENTEVENT

  PROT_CLASSDELIM

=head2 CLASS ATTRIBUTES

  %Leases

  %Servers

  %Defaults - Default values for options such as 'priority', 'volume',
  'dither', 'sound'.

  $Alarmtime - The amount of time (in seconds) between when the alarm
  handler (see the handlealarm method) is set and the SIGALRM signal
  is sent.

=head2 PUBLIC METHODS

Note that this section is somewhat incomplete.  More
documentation will come soon.

    new(%options) - Peep::BC constructor.  If an option is not
    specified in the %options argument, the equivalent value in the
    %Defaults class attributes is used.

    assemble_bc_packet() - Assembles the BC packet.  Duh.

    logger() - Returns a Peep::Log object used for log messages and
    debugging output.

    send() - Sends a packet including information on sound, location,
    priority, volume etc. to each server specified in the %Servers
    hash.

    sendout() - Used by send() to send the packet.

    handlealarm() - Refreshes and purges the server list.  Schedules
    the next SIGALRM signal to be issued in another $Alarmtime
    seconds.

    updateserverlist() - Polls to see if any of the servers have sent
    alive broadcasts so that the server list can be updated.

    purgeserverlist() - Removes servers from the server list if they
    have not sent an alive broadcast within their given expiration
    time.

    addnewserver($server,$packet) - Adds the server $server based on
    information provided in the packet $packet.  The server is only
    added if it does not exist in the %Servers hash.  The server is
    pysically added by a call to the addserver method.

    addserver($server,$leasemin,$leasesec) - Adds the server $server.
    The server is expired $leasemin minutes and $leasesec seconds
    after being added if it has not sent an alive message in the
    meantime.  Sends the server a client BC packet.

    updateserver($server,$packet) - Updates the expiration time for
    server $server.  Sends the server a client still alive message.

=head2 PRIVATE METHODS

    initialize(%options) - Peep::BC initializer.  Called from the
    constructor.  Performs the following actions:

      o Sets instance attributes via the %options argument
      o Loads configuration information from configuration file
        information passed in through the %options argument
      o Opens a socket and broadcasts an 'alive' message
      o Starts up the alarm.  Every $Alarmtime seconds, the 
        alarm handler updates the server list.

=head1 AUTHOR

Michael Gilfix <mgilfix@eecs.tufts.edu> Copyright (C) 2000

=head1 SEE ALSO

perl(1), peepd(1), Peep::Dumb, Peep::Log, Peep::Parse, Peep::Log.

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

$Log: BC.pm,v $
Revision 1.9  2001/04/17 06:46:21  starky
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

Revision 1.8  2001/04/04 05:37:11  starky
Added some debugging and made other transparent changes.

Revision 1.7  2001/03/31 07:51:34  mgilfix


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

Revision 1.6  2001/03/30 18:34:12  starky
Adjusted documentation and made some modifications to Peep::BC to
handle autodiscovery differently.  This is the last commit before the
0.4.0 release.

Revision 1.5  2001/03/28 02:41:48  starky
Created a new client called 'pinger' which pings a set of hosts to check
whether they are alive.  Made some adjustments to the client modules to
accomodate the new client.

Also fixed some trivial pre-0.4.0-launch bugs.

Revision 1.4  2001/03/27 00:44:19  starky
Completed work on rearchitecting the Peep client API, modified client code
to be consistent with the new API, and added and tested the sysmonitor
client, which replaces the uptime client.

This is the last major commit prior to launching the new client code,
though the API or architecture may undergo some initial changes following
launch in response to comments or suggestions from the user and developer
base.

Revision 1.3  2001/03/19 07:47:37  starky
Fixed bugs in autodiscovery/noautodiscovery.  Now both are supported by
Peep::BC and both look relatively bug free.  Wahoo!

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
