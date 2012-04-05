#!/usr/bin/perl
use strict;
use warnings;
use Device::SerialPort;
use File::Basename;
use File::Temp qw( tempfile );

# Prototypes
sub sendQuery($$);
sub clearBuffer($);
sub collectUntil($$);

# Device parameters
my ($DEV, $PORT, $CRLF, $DELIMITER, %CMDS, $STATUS_ON);
if (basename($0) =~ /PROJECTOR/i) {
	$DEV       = 'PROJECTOR';
	$PORT      = '/dev/tty.Projector-DevB';
	$CRLF      = "\r\n";
	$DELIMITER = ':';
	%CMDS      = (
		'INIT'   => '',
		'ON'     => 'PWR ON',
		'OFF'    => 'PWR OFF',
		'STATUS' => 'PWR?'
	);
	$STATUS_ON = 'PWR=01';
} elsif (basename($0) =~ /AMPLIFIER/i) {
	$DEV       = 'AMPLIFIER';
	$PORT      = '/dev/tty.Amplifier-DevB';
	$CRLF      = "\r\n";
	$DELIMITER = "\r";
	%CMDS      = (
		'INIT'   => '',
		'ON'     => 'PWON',
		'OFF'    => 'PWSTANDBY',
		'STATUS' => 'PW?'
	);
	$STATUS_ON = 'PWON';
} else {
	die("No device specified\n");
}

# App config
my $BYTE_TIMEOUT    = 500;
my $SILENCE_TIMEOUT = $BYTE_TIMEOUT * 10;
my $TEMP_DIR        = `getconf DARWIN_USER_TEMP_DIR`;
chomp($TEMP_DIR);
my $DATA_DIR = $TEMP_DIR . '/plexMonitor';
my $CMD_FILE = $DATA_DIR . '/' . $DEV . '_CMD';

# Debug
my $DEBUG = 0;
if ($ENV{'DEBUG'}) {
	$DEBUG = 1;
}

# Command-line arguments
my ($DELAY) = @ARGV;
if (!$DELAY) {
	$DELAY = 15;
}

# Sanity check
if (!-r $PORT || !-d $DATA_DIR) {
	die("Bad config\n");
}

# Port init
my $port = new Device::SerialPort($PORT)
  or die('Unable to open ' . $DEV . " serial connection\n");
$port->read_const_time($BYTE_TIMEOUT);
$port->lookclear();

# Init (clear any previous state)
sendQuery($port, $CMDS{'INIT'});

# Track the power state
# Check for new commands
my $power     = -1;
my $powerLast = $power;
while (1) {

	# Check for queued commands
	my $cmd = undef();
	if (-r $CMD_FILE) {
		if ($DEBUG) {
			print STDERR 'Found ' . $DEV . " command file\n";
		}

		# Open and immediately unlink the file (to de-queue the command)
		my $fh;
		open($fh, $CMD_FILE);
		unlink($CMD_FILE);

		# If we got the file open before it disappeared
		if ($fh) {
			my $text = <$fh>;
			close($fh);
			$text =~ s/^\s+//;
			$text =~ s/\s+$//;
			if ($DEBUG) {
				print STDERR 'Got command: ' . $text . "\n";
			}

			# Only accept valid commands
			foreach my $name (keys(%CMDS)) {
				if ($name eq $text) {
					$cmd = $name;
					last;
				}
			}
		}

		# Send commands
		if ($cmd) {
			if ($DEBUG) {
				print STDERR 'Sending command: ' . $cmd . "\n";
			}
			my $result = sendQuery($port, $CMDS{$cmd});
		}
	}

	# Check the power state
	$powerLast = $power;
	$power     = 0;
	my $result = sendQuery($port, $CMDS{'STATUS'});
	if ($result && $result eq $STATUS_ON) {
		$power = 1;
	}

	# If something has changed, save the state to disk
	if ($powerLast != $power) {
		if ($DEBUG) {
			print STDERR 'New ' . $DEV . ' power state: ' . $power . "\n";
		}
		my ($fh, $tmp) = tempfile($DATA_DIR . '/' . $DEV . '.XXXXXXXX', 'UNLINK' => 0);
		print $fh $power . "\n";
		close($fh);
		rename($tmp, $DATA_DIR . '/' . $DEV);
	}

	# Delay and loop
	sleep($DELAY);
}

# Cleanup
$port->close();
undef($port);
exit(0);

sub sendQuery($$) {
	my ($port, $query) = @_;

	# Read until the queue is clear (i.e. no data available)
	# Since we don't have flow control this always causes one read timeout
	$port->lookclear();
	clearBuffer($port);

	# Send the command
	my $bytes = $port->write($query . $CRLF);
	if ($DEBUG) {
		print STDERR "\tWrote (" . $bytes . '): ' . $query . "\n";
	}

	# Wait for a reply (delimited or timeout)
	return collectUntil($port, $DELIMITER);
}

sub clearBuffer($) {
	my ($port) = @_;
	my $byte = 1;
	while (length($byte) > 0) {
		$byte = $port->read(1);
		if ($DEBUG && length($byte)) {
			print STDERR "\tIgnored: " . $byte . "\n";
		}
	}
}

sub collectUntil($$) {
	my ($port, $char) = @_;
	if (length($char) != 1) {
		die('Invalid collection delimiter: ' . $char . "\n");
	}

	# This byte-by-byte reading is not efficient, but it's safe
	# Allow reading forever as long as we don't exceed the silence timeout
	my $count  = 0;
	my $string = '';
	while ($count < $SILENCE_TIMEOUT / $BYTE_TIMEOUT) {
		my $byte = $port->read(1);
		if (length($byte)) {
			$count = 0;
			$string .= $byte;

			if ($DEBUG) {
				print STDERR "\tRead: " . $byte . "\n";
			}

			if ($byte eq $char) {
				last;
			}
		} else {
			$count++;
		}
	}

	# Return undef if there was no data (as opposed to just a delimiter and/or whitespace)
	if (length($string) < 1) {
		if ($DEBUG) {
			print STDERR "Read: <NO DATA>\n";
		}
		return undef();
	}

	# Translate CRLF and CR to LF
	$string =~ s/\r\n/\n/g;
	$string =~ s/\r/\n/g;

	# Strip the trailing delimiter
	$string =~ s/${char}$//;

	# Strip leading or trailing whitespace
	$string =~ s/^\s+//;
	$string =~ s/\s+$//;

	# Return our clean string
	if ($DEBUG) {
		print STDERR 'Read: ' . $string . "\n";
	}
	return $string;
}
