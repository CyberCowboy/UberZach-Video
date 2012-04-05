#!/usr/bin/perl
use strict;
use warnings;
use POSIX qw(ceil floor);
use File::Temp qw( tempfile );

# App config
my $DELAY    = 5;
my $TEMP_DIR = `getconf DARWIN_USER_TEMP_DIR`;
chomp($TEMP_DIR);
my $DATA_DIR = $TEMP_DIR . '/plexMonitor';

# Debug
my $DEBUG = 0;
if ($ENV{'DEBUG'}) {
	$DEBUG = 1;
}

# Sanity check
if (!-d $DATA_DIR) {
	die("Bad config\n");
}

# State
my $state     = 'INIT';
my $stateLast = $state;
my $projector = 0;

# Loop forever
while (1) {

	# Monitor the PROJECTOR file for state only
	{
		$projector = 0;
		my $fh;
		open($fh, $DATA_DIR . '/PROJECTOR')
		  or die("Unable to open PROJECTOR\n");
		my $text = <$fh>;
		close($fh);
		if ($text =~ /1/) {
			$projector = 1;
		}
		if ($DEBUG) {
			print STDERR 'Projector: ' . $projector . "\n";
		}
	}

	# Monitor the AMPLIFIER file for state only
	{
		$stateLast = 'OFF';
		my $fh;
		open($fh, $DATA_DIR . '/AMPLIFIER')
		  or die("Unable to open AMPLIFIER\n");
		my $text = <$fh>;
		close($fh);
		if ($text =~ /1/) {
			$stateLast = 'ON';
		}
		if ($DEBUG) {
			print STDERR 'Amplifier: ' . $stateLast . "\n";
		}
	}

	# Calculate the new state -- track the projector power state
	if ($projector) {
		$state = 'ON';
	} else {
		$state = 'OFF';
	}

	# If the state changed, do something about if
	if ($state ne $stateLast) {
		if ($DEBUG) {
			print STDERR 'State change: ' . $stateLast . ' => ' . $state . "\n";
		}
		if ($state eq 'OFF' || $state eq 'ON') {
			my ($fh, $tmp) = tempfile($DATA_DIR . '/AMPLIFIER_CMD.XXXXXXXX', 'UNLINK' => 0);
			print $fh $state . "\n";
			close($fh);
			rename($tmp, $DATA_DIR . '/AMPLIFIER_CMD');
		}
	}

	# Wait and loop
	sleep($DELAY);
}
