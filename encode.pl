#!/usr/bin/perl
use strict;
use warnings;

# Includes
use IPC::Open3;
use File::Basename;

# Parameters
my @video_params    = ('--markers', '--large-file', '--optimize', '--encoder', 'x264', '--detelecine', '--decomb', '--loose-anamorphic', '--modulus', '16', '--x264opts', 'b-adapt=2:rc-lookahead=50');
my $FORMAT          = 'mp4';
my $QUALITY         = 20;
my $HD_QUALITY      = 20;
my $HD_WIDTH        = 1350;
my $MIN_VIDEO_WIDTH = 100;
my $MAX_CROP_DIFF   = .1;
my $MAX_DURA_DIFF   = 5;
my $HAVE_DTS        = 0;
my $HB_EXEC         = $ENV{'HOME'} . '/bin/video/HandBrakeCLI';
my $DEBUG           = 0;

# Runtime debug mode
if (defined($ENV{'DEBUG'}) && $ENV{'DEBUG'}) {
	$DEBUG = 1;
}

# Command-line parameters
my ($in_file, $out_file, $title) = @ARGV;
if (!defined($in_file) || length($in_file) < 1 || !-r $in_file) {
	die('Usage: ' . basename($0) . " in_file [out_file] [title]\n");
}

# Scan for title/track info
my %titles = &scan($in_file);

# Allow external subtitles for single-title files
if (scalar(keys(%titles)) == 1) {
	my $srt_file = $in_file;
	$srt_file =~ s/\.\w{2,3}$/.srt/;
	if (-r $srt_file) {
		if ($DEBUG) {
			print STDERR 'Adding subtitles from: ' . $srt_file . "\n";
		}
		push(@video_params, '--srt-file', $srt_file);
	}
}

# Allow encoding of a specific title
if ($title) {
	if ($title =~ /^\d+$/ && $title > 0) {
		if (!defined($titles{$title})) {
			die(basename($0) . ': Invalid title number: ' . $title . "\n");
		}
		my $selected_title = $titles{$title};
		%titles = ();
		$titles{$title} = $selected_title;
	} elsif ($title =~ /main/i) {
		my $max_title    = 0;
		my $max_duration = 0;
		foreach my $title (keys(%titles)) {
			if (!$titles{$title}{'duration'}) {
				warn(basename($0) . ': Unknown duration for title: ' . $title . "\n");
				next;
			}
			my $new_max = 0;
			if (abs($titles{$title}{'duration'} - $max_duration) < $MAX_DURA_DIFF) {
				if ($titles{$title}{'aspect'} > $titles{$max_title}{'aspect'}) {
					$new_max = 1;
				} elsif ($titles{$title}{'size'}[0] > $titles{$max_title}{'size'}[0] || $titles{$title}{'size'}[1] > $titles{$max_title}{'size'}[1]) {
					$new_max = 1;
				}
			} elsif ($titles{$title}{'duration'} > $max_duration) {
				$new_max = 1;
			}
			if ($new_max) {
				$max_duration = $titles{$title}{'duration'};
				$max_title    = $title;
			}
		}
		my $selected_title = $titles{$max_title};
		%titles = ();
		$titles{$max_title} = $selected_title;
	}
}

# Ensure we have an output file name
# Allow forced use of MKV wrapper if the output file name is provided and ends in .MKV
if (!defined($out_file) || length($out_file) < 1) {
	$out_file = $in_file;
} else {
	my ($force_format) = $out_file =~ /\.(\w{2,3})$/;
	if (lc($force_format) eq 'mkv') {
		$FORMAT = 'mkv';
	}
}

# Encode each title
foreach my $title (keys(%titles)) {
	if ($DEBUG) {
		print STDERR 'Setting options for title: ' . $title . "\n";
	}

	# Parse the title's audio and subtitle tracks
	my $scan  = $titles{$title};
	my @audio = &audioOptions($scan);
	my @subs  = &subOptions($scan);

	# Skip tracks that have no video
	if (scalar(@{ $scan->{'size'} }) < 2 || $scan->{'size'}[0] < $MIN_VIDEO_WIDTH) {
		print STDERR basename($0) . ': No video detected in: ' . $in_file . ':' . $title . ". Skipping title...\n";
		next;
	}

	# Skip tracks that have no audio
	if (scalar(@{ $scan->{'audio'} }) < 1) {
		print STDERR basename($0) . ': No audio detected in: ' . $in_file . ':' . $title . ". Skipping title...\n";
		next;
	}

	# Reduce the quality if the image size is particularly large
	my $title_quality = $QUALITY;
	if ($scan->{'size'}[0] > $HD_WIDTH) {
		$title_quality = $HD_QUALITY;
	}

	# Override unlikely autocrop values
	if (   abs($scan->{'crop'}[0] - $scan->{'crop'}[1]) > $scan->{'size'}[0] * $MAX_CROP_DIFF
		|| abs($scan->{'crop'}[2] - $scan->{'crop'}[3]) > $scan->{'size'}[0] * $MAX_CROP_DIFF)
	{
		print STDERR basename($0) . ': Overriding unlikely autocrop values: ' . join(':', @{ $scan->{'crop'} }) . "\n";
		my @crop = (0, 0, 0, 0);
		$scan->{'crop'} = \@crop;
	}

	# Require the MKV format whenever we have DTS audio
	my $title_format = $FORMAT;
	if ($HAVE_DTS) {
		$title_format = 'mkv';
	}

	# Select a file name extension that matches the format
	my $title_out_file = $out_file;
	$title_out_file =~ s/\.(?:\w{2,3}|dvdmedia)$//i;
	if ($title_format eq 'mkv') {
		$title_out_file .= '.mkv';
	} else {
		$title_out_file .= '.m4v';
	}

	# Force the title number into the output file name if there are multiple titles to be encoded
	if (scalar(keys(%titles)) > 1) {
		my $title_text = sprintf('%02d', $title);
		$title_out_file =~ s/(\.\w{2,3})$/\-${title_text}${1}/;
	}

	# Sanity check
	if (uc($title_out_file) eq uc($in_file)) {
		$title_out_file =~ s/(\.\w{2,3})$/-recode${1}/;
	}
	if (-e $title_out_file) {
		print STDERR basename($0) . ': Output file exists: ' . $title_out_file . ". Skipping...\n";
		next;
	}

	# Build the arugment list
	my @args = ($HB_EXEC);
	push(@args, '--title',   $title);
	push(@args, '--input',   $in_file);
	push(@args, '--output',  $title_out_file);
	push(@args, '--format',  $title_format);
	push(@args, '--quality', $title_quality);
	push(@args, '--crop',    join(':', @{ $scan->{'crop'} }));
	push(@args, @video_params);
	push(@args, @audio);
	push(@args, @subs);

	# Run it
	if ($DEBUG) {
		print STDERR join(' ', @args) . "\n";
	}
	my $child_out = '';
	my $child_in  = '';
	my $pid       = open3($child_in, $child_out, $child_out, @args);
	close($child_in);
	while (<$child_out>) {
		if ($DEBUG) {
			print STDERR $_;
		}
	}
	waitpid($pid, 0);
	close($child_out);

	# Provide the new file name if requested
	if ($ENV{'RECODE_OUTFILE'}) {
		print $title_out_file;
	}
}

# Cleanup
exit(0);

sub subOptions($) {
	my ($scan) = @_;

	# Find English subtitles
	my @keep = ();
	foreach my $track (@{ $scan->{'subtitle'} }) {
		if (my ($lang) = $track->{'description'} =~ /\b(English|Unknown|Closed\s+Captions)\b/i) {
			push(@keep, $track->{'index'});
			if ($DEBUG) {
				print STDERR 'Found ' . $lang . ' subtitle in track ' . $track->{'index'} . "\n";
			}
		}
	}

	# Send back the argument string (if any)
	if (scalar(@keep) < 1) {
		return '';
	}
	return ('--subtitle', join(',', @keep));
}

sub audioOptions($) {
	my ($scan) = @_;

	# Type the audio tracks
	my $oat      = undef();
	my $mpg      = undef();
	my @channels = ();
	my @pcm      = ();
	my @ac3      = ();
	my @dts      = ();
	my @aac      = ();
	foreach my $track (@{ $scan->{'audio'} }) {
		my ($language, $codec, $chans, $iso) = $track->{'description'} =~ /^([^\(]+)\s+\(([^\)]+)\)\s+\((\d+\.\d+\s+ch|Dolby\s+Surround)\)(?:\s+\(([^\)]+)\))?/;
		if (!defined($chans)) {
			print STDERR 'Could not parse audio description: ' . $track->{'description'} . "\n";

			# Temporarily exit on parsing errors -- at least until we're sure about this new parser
			exit(1);
			next;
		}
		if ($chans =~ /(\d+\.\d+)\s+ch/i) {
			$chans = $1;
		} elsif ($chans =~ /Dolby\s+Surround/i) {
			$chans = 3.1;
		}
		if ($DEBUG) {
			print STDERR 'Found audio track: codec => ' . $codec . ', channels => ' . $chans . ', language => ' . $language . ', ISO => ' . $iso . "\n";
		}

		# Record the number of channels in each track
		$channels[ $track->{'index'} ] = $chans;

		if ($codec =~ /AC3/i) {
			if ($language =~ /\b(Chinese|Espanol|Francais|Japanese|Korean|Portugues|Thai)\b/i) {
				if ($DEBUG) {
					print STDERR 'Skipping AC3 in track ' . $track->{'index'} . ' due to language: ' . $language . "\n";
				}
				next;
			}
			push(@ac3, $track->{'index'});
			if ($DEBUG) {
				print STDERR 'Found AC3 in track ' . $track->{'index'} . "\n";
			}
		} elsif ($codec =~ /AAC/i) {
			push(@aac, $track->{'index'});
			if ($DEBUG) {
				print STDERR 'Found AAC in track ' . $track->{'index'} . "\n";
			}
		} elsif ($codec =~ /MP3/i || $codec =~ /MPEG/i) {
			$mpg = $track->{'index'};
			if ($DEBUG) {
				print STDERR 'Found MPEG/MP3 in track ' . $track->{'index'} . "\n";
			}
		} elsif ($codec =~ /PCM_[SF]\d+/i) {
			push(@pcm, $track->{'index'});
			if ($DEBUG) {
				print STDERR 'Found PCM in track ' . $track->{'index'} . "\n";
			}
		} elsif ($codec =~ /DTS/i) {
			if ($codec =~ /DTS\-MA/i) {
				if ($DEBUG) {
					print STDERR 'Skipping DTS-MA in track ' . $track->{'index'} . " due to poor DTS-MA support in HandBrake\n";
				}
				next;
			}
			push(@dts, $track->{'index'});
			if ($DEBUG) {
				print STDERR 'Found DTS in track ' . $track->{'index'} . "\n";
			}
		} elsif ($codec =~ /MP2/i) {
			$oat = $track->{'index'};
			if ($DEBUG) {
				print STDERR 'Found other audio (' . $track->{'description'} . ') in track ' . $track->{'index'} . "\n";
			}
		}
	}

	# We should sort the different codecs by number of channels
	# But so far I've had good luck just taking the first track with the best codec

	# Pick a stereo/mixdown plan based on the available track types
	my $stereo  = undef();
	my $mixdown = undef();
	if (scalar(@dts) > 0) {
		$mixdown = $dts[0];
	} elsif (scalar(@aac) > 0) {
		$mixdown = $aac[0];
	} elsif (scalar(@ac3) > 0 || scalar(@pcm) > 0) {
		if (scalar(@pcm) < 1) {
			$mixdown = $ac3[0];
		} elsif (scalar(@ac3) < 1) {
			$mixdown = $pcm[0];
		} elsif ($channels[ $pcm[0] ] >= $channels[ $ac3[0] ]) {
			$mixdown = $pcm[0];
		} elsif ($channels[ $pcm[0] ] >= $channels[ $ac3[0] ]) {
			$mixdown = $pcm[0];
		}
	} elsif (defined($mpg) && $mpg > 0) {
		$stereo = $mpg;
	} elsif (defined($oat) && $oat > 0) {
		$stereo = $oat;
	}

	# Sanity check
	if (!(defined($mixdown) && $mixdown > 0) && !(defined($stereo) && $stereo > 0)) {
		print STDERR basename($0) . ": No usable audio tracks in title\n";
		return ();
	}

	# Stereo/mixdown track first
	my @audio_tracks = ();
	if (defined($mixdown) && $mixdown > 0) {
		if ($DEBUG) {
			print STDERR 'Mixing down track (track #' . $mixdown . ") to stereo\n";
		}
		my %track = ('index' => $mixdown, 'encoder' => 'ca_aac');
		push(@audio_tracks, \%track);
	} elsif (defined($stereo) && $stereo > 0) {
		if ($DEBUG) {
			print STDERR 'Using existing stereo track: ' . $stereo . "\n";
		}
		my %track = ('index' => $stereo, 'encoder' => 'ca_aac');
		push(@audio_tracks, \%track);
	}

	# Always keep DTS if we found it
	$HAVE_DTS = 0;
	if (scalar(@dts) > 0) {
		$HAVE_DTS = 1;
		foreach my $dts_track (@dts) {
			if ($DEBUG) {
				print STDERR 'Keeping DTS passthru track: ' . $dts_track . "\n";
			}
			my %track = ('index' => $dts_track, 'encoder' => 'copy:dts');
			push(@audio_tracks, \%track);
		}
	}

	# Always keep AAC if we found it (and liked it)
	# Passthru would be great, but HandBrake does not do AAC passthru
	foreach my $aac_track (@aac) {
		if ($DEBUG) {
			print STDERR 'Keeping AAC track as CoreAudio AAC: ' . $aac_track . "\n";
		}
		my %track = ('index' => $aac_track, 'encoder' => 'ca_aac');
		push(@audio_tracks, \%track);
	}

	# Always keep PCM if we found it (but recode to AAC)
	foreach my $pcm_track (@pcm) {
		if ($DEBUG) {
			print STDERR 'Keeping PCM track as AAC: ' . $pcm_track . "\n";
		}
		my %track = ('index' => $pcm_track, 'encoder' => 'ca_aac');
		push(@audio_tracks, \%track);
	}

	# Always keep AC3 if we found it (and liked it)
	foreach my $ac3_track (@ac3) {
		if ($DEBUG) {
			print STDERR 'Keeping AC3 passthru track: ' . $ac3_track . "\n";
		}
		my %track = ('index' => $ac3_track, 'encoder' => 'copy:ac3');
		push(@audio_tracks, \%track);
	}

	# Consolidate from the hashes
	my @tracks   = ();
	my @encoders = ();
	foreach my $track (@audio_tracks) {
		push(@tracks,   $track->{'index'});
		push(@encoders, $track->{'encoder'});
	}

	# Send back the argument strings
	return ('--audio', join(',', @tracks), '--aencoder', join(',', @encoders));
}

sub scan($) {
	my ($in_file) = @_;

	# Fork to scan the file
	my $child_out = '';
	my $pid = open3('<&STDIN', $child_out, $child_out, $HB_EXEC, '--title', '0', '--input', $in_file);

	# Loop through the output
	my $scan;
	my %titles       = ();
	my $inTitle      = 0;
	my $zone         = '';
	my $dca_stream   = -1;
	my %dca_lossless = ();
	while (<$child_out>) {

		if (!$inTitle && m/scan thread found (\d+) valid title/i) {
			if ($DEBUG) {
				print STDERR 'Found ' . $1 . " titles in source\n";
			}
		} elsif (m/^\s+Stream \#0\.(\d+)\(\w+\)\:\s+(.*)/) {
			my $stream = $1;
			my $desc   = $2;
			$dca_stream = -1;
			if ($desc =~ /Audio\:\s+dca/) {
				$dca_stream = $stream;
			}
		} elsif ($dca_stream >= 0 && m/^\s+title\s*\:\s+(.*)/) {
			if ($1 =~ /Lossless/i) {
				$dca_lossless{$dca_stream} = 1;
				if ($DEBUG) {
					print STDERR 'Found DTS Lossless audio in stream: ' . $dca_stream . "\n";
				}
			}
			$dca_stream = -1;
		} elsif (m/^\s*\+\s+title\s+(\d+)\:/) {

			# Save the current title (if any)
			if ($inTitle) {
				$titles{$inTitle} = $scan;
			}

			# Grab the new title number
			$inTitle = $1;

			# Init the data collectors
			my @audio    = ();
			my @crop     = ();
			my @subtitle = ();
			my @size     = ();
			my %tmp      = (
				'audio'    => \@audio,
				'crop'     => \@crop,
				'subtitle' => \@subtitle,
				'size'     => \@size,
				'duration' => 0,
				'aspect'   => 0
			);
			$scan = \%tmp;

			if ($DEBUG) {
				print STDERR 'Found data for title ' . $1 . "\n";
			}
		} elsif ($inTitle) {
			if (/^\s*\+\s+size: (\d+)x(\d+)/) {
				push(@{ $scan->{'size'} }, $1, $2);
				if ($DEBUG) {
					print STDERR 'Size: ' . join('x', @{ $scan->{'size'} }) . "\n";
				}
				if (/\s+display aspect\: (\d*\.\d+)/) {
					$scan->{'aspect'} = $1;
					if ($DEBUG) {
						print STDERR 'Aspect: ' . $scan->{'aspect'} . "\n";
					}
				}
			} elsif (/^\s*\+\s+duration\:\s+(\d+)\:(\d+)\:(\d+)/) {
				$scan->{'duration'} = ($1 * 3600) + ($2 * 60) + $3;
				if ($DEBUG) {
					print STDERR 'Duration: ' . $scan->{'duration'} . "\n";
				}
			} elsif (/^\s*\+\s+autocrop\:\s+(\d+)\/(\d+)\/(\d+)\/(\d+)/) {
				push(@{ $scan->{'crop'} }, $1, $2, $3, $4);
				if ($DEBUG) {
					print STDERR 'Crop: ' . join('/', @{ $scan->{'crop'} }) . "\n";
				}
			} elsif ($zone ne 'audio' && /^\s*\+\s+audio\s+tracks\:\s*$/) {
				$zone = 'audio';
			} elsif ($zone eq 'audio' && /^\s*\+\s+(\d+)\,\s+(.*)/) {
				my %track = ('index' => $1, 'description' => $2);
				if ($dca_lossless{ $track{'index'} }) {
					$track{'description'} =~ s/\(DTS\)/\(DTS-MA\)/;
				}
				push(@{ $scan->{'audio'} }, \%track);
				if ($DEBUG) {
					print STDERR 'Audio Track #' . $track{'index'} . ': ' . $track{'description'} . "\n";
				}
			} elsif ($zone ne 'subtitle' && /^\s*\+\s+subtitle\s+tracks\:\s*$/) {
				$zone = 'subtitle';
			} elsif ($zone eq 'subtitle' && m/^\s*\+\s+(\d+)\,\s+(.*)$/) {
				my %track = ('index' => $1, 'description' => $2);
				push(@{ $scan->{'subtitle'} }, \%track);
				if ($DEBUG) {
					print STDERR 'Subtitle Track #' . $track{'index'} . ': ' . $track{'description'} . "\n";
				}
			}
		}
	}

	# Save the last title (if any)
	if ($inTitle) {
		$titles{$inTitle} = $scan;
	}

	# Cleanup the scan process
	waitpid($pid, 0);
	close($child_out);

	# Sanity check
	if (scalar(keys(%titles)) < 1) {
		die(basename($0) . ': Did not find any titles in file: ' . $in_file . "\n");
	}

	# Return
	return %titles;
}
