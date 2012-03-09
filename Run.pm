#!/usr/bin/perl
use strict;
use warnings;

#-----------------------------------------------------------------------------
## @file Run.pm
#  @brief A module for running perl scripts in threaded environment
#  @see Run.pm

## @class Run


# Package
package Run;

# Globals
my $DEBUG = 0;

#----------------------------------------------------------------------
## @fn runAndWar(@)
#  @brief Run and warn
#  @param args array
#  @return 1 is successful, 0 if not
sub runAndWarn(@) {
	my (@args) = (@_);
	if ($DEBUG) {
		print STDERR "Run::runAndWarn()\n";
	}

	# Run
	my $res = Run::run(@args);

	# Die on any error
	if ($res == -1) {
		warn('Unable to execute program: ' . join(' ', @args) . ': ' . $! . "\n");
		return 0;
	} elsif ($res & 127) {
		warn('Child exited on signal: ' . join(' ', @args) . ': ' . ($res & 127) . "\n");
		return 0;
	} elsif ($res != 0) {
		warn('Child exited with non-zero value: ' . join(' ', @args) . ': ' . ($res >> 8) . "\n");
		return 0;
	}

	# If we get here, all is well
	return 1;
}

#----------------------------------------------------------------------
## @fn runAndCheck(@)
#  @brief Run and check
#  @param args
#  @return 1 if successful, 0 if not
sub runAndCheck(@) {
	my (@args) = (@_);
	if ($DEBUG) {
		print STDERR "Run::runAndCheck()\n";
	}

	# Run
	my $res = Run::run(@args);

	# Die on any error
	if ($res == -1) {
		die('Unable to execute program: ' . join(' ', @args) . ': ' . $! . "\n");
	} elsif ($res & 127) {
		die('Child exited on signal: ' . join(' ', @args) . ': ' . ($res & 127) . "\n");
	} elsif ($res != 0) {
		die('Child exited with non-zero value: ' . join(' ', @args) . ': ' . ($res >> 8) . "\n");
	}

	# If we get here, all is well
	return 1;
}

#----------------------------------------------------------------------
## @fn run(@)
#  @brief Run
#  @param args arry
#  @return results
sub run(@) {
	my (@args) = (@_);
	if ($DEBUG) {
		print STDERR 'Run::run: ' . join(' ', @args) . "\n";
	}

	# Run
	system { $args[0] } @args;

	# Return the result
	return $?;
}

# Packages must return true
return 1;
