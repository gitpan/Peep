package Peep;

require 5.005_62;
use strict;
use warnings;

require Exporter;

our @ISA = qw(Exporter);

our %EXPORT_TAGS = ( 'all' => [ qw( ) ] );
our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } );
our @EXPORT = qw( );
our $VERSION = '0.4.0';

# This module serves no useful purpose at this time other than as a
# placeholder for documentation

1;

__END__

=head1 NAME

Peep - Perl extension for Peep:  The Network Auralizer.

=head1 DESCRIPTION

Peep is an open source free software network monitoring tool issued
under the Gnu Public License that presents information via audio
output.  Network diagnosis with Peep is made not only based on single
network events, but the network as a whole "sounds normal."

This document serves as an introduction to the Peep clients and the
Peep client architecture.

=head1 INTRODUCTION

Peep is built on a client-server model in which the clients generate
"events" based on user-defined criteria (e.g., whether a packet denial
has been logged or a broken link on a web site was found).  One or
several Peep servers are then notified of the events by clients, at
which time an audio signal is generated.

The clients, which include such applications as C<logparser> and
C<sysmonitor> and for which this document constitutes introductory
documentation, are written in Perl, IMHO about the coolest language
ever.  The bulk of the client code is composed of a set of Perl
modules comprising objects and base classes for use by Peep clients
and their derivatives.

The server, C<peepd>, is written in C.

Both the client and server are available for download free of charge
from the Peep homepage located at

  http://peep.sourceforge.net

The Peep client modules and executables are also available on the CPAN
(Comprehensive Perl Archive Network) for installation via the
time-honored

  perl -MCPAN -e "install Peep"

In fact, this is the preferred method of installation of the Peep
clients.

Consult the core Peep documentation for more information on
installation and usage of Peep.

The Peep client library is composed of the following modules:

  Perl Modules
  ------------

  Peep                 A non-functional module.  Simply holds 
                       POD documentation for Peep; in fact, 
                       it holds the documentation that you are
                       reading right now!

  Peep::Conf           The Peep configuration object.  An  
                       object representation of peep.conf.

  Peep::Parse          The Peep configuration file parser.  Reads  
                       peep.conf and populates Peep::Conf 
                       appropriately.

  Peep::BC             The Peep broadcast module.  Used to notify Peep  
                       servers that an event has been generated.

  Peep::Log            Provides utility methods for logging, debugging,
                       and benchmarking.

  Peep::Client         Base and utility class for Peep clients and 
                       client modules.

  Peep::Client::Log    Utility class for the logparser client.

  Peep::Client::System Utility class for the sysmonitor client.

  Peep::Peck           Utility class for the peck client.

  Clients
  -------

  logparser            Generates events based on matching regular
                       expressions to tailed logs (e.g., 
                       C</var/log/messages>).

  sysmonitor           Generates events based on system events (e.g.,
                       load average exceeding 2.0).

  peck                 Generates ad hoc Peep events.  Primarily for 
                       testing purposes.

  keytest              Generates ad hoc Peep events.  Primarily for 
                       fun.

Please refer to the individual modules of the Peep distribution (e.g.,
Peep::BC) or the Peep client executables (e.g., logparser) for further
documentation.

=head1 CREATING A CUSTOM PEEP CLIENT

Please note that the Peep client API has not yet been finalized, and
is subject to change.  If you have any problems with your custom-built
client as a result of changes made to the client API, please contact
Collin Starkweather at collin.starkweather@colorado.edu.

The Peep::Client module makes constructing a custom Peep client a breeze.

The Peep::Client::Log and Peep::Client::System modules are excellent
references.  Pay particular attention to the Start methods in each and
thier usage of the Peep::BC module, which notifies the Peep server of
Peep client events.

A Peep client by no means has to be a module, however.  It can just as
easily be created as a script.  The Peep::Client::Log and
Peep::Client::System modules, which correspond to the logparser and
system clients, were created as modules simply for ease of
distribution.

Basically, the same formula is used for each client.  

0) This goes without saying, but I will say it anyway.  First you have
   to instantiate a Peep::Client object.  For convenience, we will
   also create a Peep::Log object for logging and debugging messages.
   Creating the logging object is by no means necessary.

     use Peep::Client;
     use Peep::Log;
     my $client = new Peep::Client.
     my $log    = new Peep::Log;
   
1) Tell Peep::Client what command-line options to parse.  For more
   information on how to define command-line options, see
   Getopt::Long, which Peep::Client uses to parse the options.

   To do this, create a hash of options.  For more information on the
   format of the options, see the documentation for Getopt::Long.

   For example, if you want to use the options 'foo' and 'bar', with
   'foo' accepting a string and 'bar' a binary flag (implying that nobar
   is the negation of the option):

     my $foo = ''; # be sure to initialize your options
     my $bar = 0;
     my %options = (
       'foo=s' => \$foo, # =s implies a string is expected
       'bar!'  => \$bar  # ! implies negation with nobar
     );

   Note that Peep::Client accepts a set of default command-line
   options common to all Peep clients and provides accessors to obtain
   the values assigned to each.  These include

     debug
     daemon
     autodiscover
     config 
     output
     pidfile
     server
     port
     silent
     help

   Explanations of each are included elsewhere in this documentation.

2) Parse the command-line options and get their values.  This is done
   with the C<Peep::Client-E<gt>parseopts()> method:

     $client->parseopts(%options);

   As part of our example, we will print or log the values of 'foo' and
   'bar' for the user to see.  Note that following the parsing of the
   default command-line options by the Peep::Client object,

   o The log class has been initialized to log to whatever file was 
     specified by the 'logfile' option (or STDERR if none was specified),
     and 
   o Debugging levels that were specified on the command-line have 
     been set.

     $log->log("You specified the option [foo] to be [$foo]."); 
     $log->log("You specified the option [bar] to be [$bar].");

   You may also want to take specific actions based on the values of
   the options.

3) Parse the Peep configuration file.  This is done with the
   C<Peep::Client-E<gt>>parseconf()> method:

     $client->parseconf();

   The name of the configuration file can be specified on the command
   line with the C<option>.  (This is one of the set of standard
   options that the Peep::Client object parses).  If it is not passed
   in as a command-line argument, it defaults to C</etc/peep.conf>.

   After you have parsed the configuration file, you can get a
   configuration object which has all of your option and configuration
   information.

   The C<Peep::Client-E<gt>getconf()> method returns a Peep::Conf Peep
   configuration object populated with all of the information
   specified in the Peep configuration file:

     my $conf = $client->getconf();

   See the Peep::Conf documentation for more detail.

4) Register a callback.  This should be a reference to a subroutine,
   and is registered by using the C<Peep::Client-E<gt>callback()> method:

     $client->callback(sub { &MyLoop($foo,$bar) });

   Typically, you would have a call to the C<Peep::BC-E<gt>send()> method
   somewhere in your loop.  See the Peep::BC (BC stands for BroadCast)
   documentation for more information.

   More detailed information on creating the looping subroutine can be
   found below.

5) Finally, enter the main loop:

     $client->MainLoop(); # executes the callback once

   If your client is an event-driven client (that is, if it processes
   its own events), then MainLoop should be called with no arguments,
   in which case it executes the callback once.

   If your client is a looping client (that is, if it enters into an
   infinite loop which is called at regular intervals), then call
   MainLoop with an argument indicating how many seconds you want
   between calls to the callback; e.g.,

     $client->MainLoop(10); # execute the callback every 10 seconds

That is all there is to it!

=head1 CREATING THE CALLBACK FOR YOUR CLIENT APPLICATION

Coming soon.

=head1 DEFAULT CLIENT OPTIONS

Coming soon.

=head1 AUTHOR

Michael Gilfix <mgilfix@eecs.tufts.edu> Copyright (C) 2001

Collin Starkweather <collin.starkweather@colorado.edu>

=head1 ACKNOWLEDGEMENTS

Many thanks to the folks at SourceForge for creating a robust
development environment to support open source projects such as Peep.

If you are not familiar with SourceForge, please visit their site at

  http://www.sourceforge.net

=head1 SEE ALSO

perl(1), peepd(1), logparser, sysmonitor, peck.

=head1 RELATED SOFTWARE

For those interested in a robust network and systems monitoring
tools, your humble author has found Big Brother to be a valuable
resource which is complementary to Peep.

You can find more information on Big Brother at

  http://www.bigbrother.com

Those who enjoy Peep may also enjoy checking out logplay, which is
similar in concept but fills a different niche.

You can find more information on logplay at

  http://projects.babblica.net/logplay

=cut
