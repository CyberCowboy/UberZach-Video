#!/usr/bin/perl
use strict;
use warnings;
use POSIX qw(ceil floor);
use File::Temp qw( tempfile );

# Prototypes
sub mtime($);

# Config
my $TIMEOUT   = 900;
my $COUNTDOWN = 300;

# App config
my $DELAY    = 60;
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
my $state      = 'INIT';
my $stateLast  = $state;
my $updateLast = 0;
my $projector  = 0;

# Loop forever
while (1) {

	# Monitor the GUI and PLAYING files for changes only
	{
		my $mtime = mtime($DATA_DIR . '/PLAYING');
		if ($mtime > $updateLast) {
			$updateLast = $mtime;
		}
		$mtime = mtime($DATA_DIR . '/GUI');
		if ($mtime > $updateLast) {
			$updateLast = $mtime;
		}
	}

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

	# Calculate the new state
	my $stateLast       = $state;
	my $timeSinceUpdate = time() - $updateLast;
	if ($DEBUG) {
		print STDERR 'Time since update: ' . $timeSinceUpdate . "\n";
	}
	if ($state eq 'INIT') {
		$state = 'OFF';
		if ($projector) {
			$state = 'ON';
		}
	} elsif ($projector) {
		if ($timeSinceUpdate > $TIMEOUT) {
			$state = 'COUNTDOWN';
			if ($timeSinceUpdate > $TIMEOUT + $COUNTDOWN) {
				$state = 'OFF';
			}
		} else {
			$state = 'ON';
		}
	} else {
		if ($timeSinceUpdate < $TIMEOUT) {
			$state = 'ON';
		}
	}

	# If the state changed, do something about if
	if ($state ne $stateLast) {
		if ($DEBUG) {
			print STDERR 'State change: ' . $stateLast . ' => ' . $state . "\n";
		}
		if ($state eq 'OFF') {

			# Turn off the projector
			my ($fh, $tmp) = tempfile($DATA_DIR . '/PROJECTOR_CMD.XXXXXXXX', 'UNLINK' => 0);
			print $fh "OFF\n";
			close($fh);
			rename($tmp, $DATA_DIR . '/PROJECTOR_CMD');
		} elsif ($state eq 'ON') {

			# Do nothing, at least for the moment
		}

	}

	# Always announce a pending shutdown
	if ($state eq 'COUNTDOWN') {
		my $timeLeft = ($TIMEOUT + $COUNTDOWN) - $timeSinceUpdate;
		$timeLeft = ceil($timeLeft / 60);

		my $plural = 's';
		if ($timeLeft == 1) {
			$plural = '';
		}
		system('say', 'Projector powerdown in about ' . $timeLeft . ' minute' . $plural);
	}

	# Wait and loop
	sleep($DELAY);
}

sub mtime($) {
	my ($file) = @_;
	my $mtime = 0;
	if (-r $file) {
		(undef(), undef(), undef(), undef(), undef(), undef(), undef(), undef(), undef(), $mtime, undef(), undef(), undef()) = stat($file);
	}
	return $mtime;
}
