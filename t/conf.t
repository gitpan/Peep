#!/usr/bin/perl


BEGIN { $Test::Harness::verbose++; $|++; print "1..3\n"; }
END {print "not ok\n", exit 1 unless $loaded;}

use Peep::Log;
use Peep::Conf;
use Peep::Parse;

$loaded = 1;

print "ok\n";

$Peep::Log::debug = 0;

my ($conf,$parser);

eval {

	$conf = new Peep::Conf;
	$parser = new Peep::Parse;

};

if ($@) {
	print "not ok:  $@\n";
	exit 1;
} else {
	print "ok\n";
}

$Test::Harness::verbose += 1;
$Peep::Log::debug = 1;

print STDERR "\nTesting Peep configuration file parser:\n";

eval { 

	$conf->setApp('logparser');
	$conf->setOption('config','./peep.conf');
	$parser->loadConfig($conf);

};

if ($@) {
	print STDERR "not ok:  $@";
	exit 1;
} else {
	print "ok\n";
	exit 0;
}

