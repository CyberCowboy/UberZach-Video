#!/usr/bin/perl
use strict;
use warnings;
use File::Basename;
use Time::HiRes qw( usleep );
use File::Temp qw( tempfile );

# App config
my $TEMP_DIR = `getconf DARWIN_USER_TEMP_DIR`;
chomp($TEMP_DIR);
my $DATA_DIR = $TEMP_DIR . '/plexMonitor';
my $EXEC_DIR = $ENV{'HOME'} . '/bin/video';

# Debug
my $DEBUG = 0;
if ($ENV{'DEBUG'}) {
	$DEBUG = 1;
}

# Command-line arguments
my ($DELAY) = @ARGV;
if (!$DELAY) {
	$DELAY = 0;
}
$DELAY = int($DELAY) * 1000000;    # Microseconds;

# Sanity check
if (!-d $EXEC_DIR || !-d $TEMP_DIR) {
	die("Bad config\n");
}

# Mode
my $MODE = 'PLAYING';
my $CMD  = 'plex-playing';
if (basename($0) =~ /GUI/i) {
	$MODE = 'GUI';
	$CMD  = 'plex-gui';
}

# Add the data directory as needed
if (!-d $DATA_DIR) {
	mkdir($DATA_DIR);
}

# Loop forever (unless no delay is set)
my $dataLast = '';
do {
	my $changed = 0;

	# Run the monitor command
	my $cmd = $EXEC_DIR . '/' . $CMD;
	my $data = `$cmd`;

	# Compare this data set to the last
	if ($data ne $dataLast) {
		$changed = 1;
	}

	# If anything changed, save the data to disk
	if ($changed) {
		my ($fh, $tmp) = tempfile($DATA_DIR . '/' . $MODE . '.XXXXXXXX', 'UNLINK' => 0);
		print $fh $data;
		close($fh);
		rename($tmp, $DATA_DIR . '/' . $MODE);
	}

	# Special handling for PLAYING mode -- it's a bit of a hack, but it saves a lot of code other places
	if ($changed && $MODE eq 'PLAYING') {
		my $playing = 0;
		if ($data =~ /PlayStatus\:Playing/) {
			$playing = 1;
		}
		my ($fh, $tmp) = tempfile($DATA_DIR . '/PLAY_STATUS.XXXXXXXX', 'UNLINK' => 0);
		print $fh $playing;
		close($fh);
		rename($tmp, $DATA_DIR . '/PLAY_STATUS');
	}

	# Delay and loop
	usleep($DELAY);
} until ($DELAY == 0);

# Exit cleanly
exit(0);
