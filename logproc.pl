#!/usr/bin/perl
#	@(#) logproc - Process log files
#	Copyright (C) 2004,2009 Nick Andrew <nick@nick-andrew.net>
#	Released under the terms of the GNU General Public License
#
# Usage: find path -type f -print | logproc [-d] ctlfile
#

use strict;

use Getopt::Std qw(getopts);

use vars qw($opt_d);

select(STDOUT);
$| = 1;

getopts('d');

my $real = 1;

if ($opt_d) {
	$real = 0;
}

my $ctlfile = shift @ARGV;

if (! $ctlfile) {
	usage();
	die "Need to specify control file"
}

my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
$mon ++;
$year += 1900;
my $yyyymm = sprintf "%04d-%02d", $year, $mon;
my $yyyymmdd = sprintf "%04d-%02d-%02d", $year, $mon, $mday;

my @paths = parseConfig($ctlfile);

while (<STDIN>) {
	chomp;

	my $fn = $_;
	checkPath($fn);
}

exit(0);

# ---------------------------------------------------------------------------
# Parse the config file
# Return output list
# ---------------------------------------------------------------------------

sub parseConfig {
	my ($ctlfile) = @_;

	my @paths;

	open(C, "<$ctlfile") || die "ctlfile: $ctlfile: $!";

	while (<C>) {
		chomp;

		next if (/^$/);
		next if (/^#/);

		my ($regex,$crit,$disp,@rest) = split(/\|/);

		my $ref = {
			regex => $regex,
			disp => $disp,
			target => undef,
			mtime => undef,
			cmd => undef,
		};

		# Parse criteria
		my ($count,$type) = ($crit =~ /(\d+)(.)/);

		if ($type eq 'y') {
			$ref->{target} = sprintf("%04d", $year - $count);
		} elsif ($type eq 'm') {
			my $y = $year;
			my $m = $mon - $count;

			while ($m < 1) {
				$y--;
				$m += 12;
			}

			$ref->{target} = sprintf("%04d-%02d", $y, $m);
		} elsif ($type eq 'd') {
			my $then = time - 86400 * $count;
			my($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime($then);
			$ref->{mtime} = $then;
		}


		if ($disp eq "discard") {
		} elsif ($disp eq "exec") {
			$ref->{cmd} = $rest[0];
		} else {
			print STDERR "Unknown disposition: $regex|$crit|$disp\n";
			next;
		}

		push(@paths, $ref);
	}

	close(C);

	return @paths;
}

# ---------------------------------------------------------------------------
# Check a single pathname ($fn) against our set of regular expressions
# ---------------------------------------------------------------------------

sub checkPath {
	my ($fn) = @_;

#	print "\nChecking $fn\n";

	# File mtime (filled in later)
	my $mtime;

	foreach my $ref (@paths) {
		my $regex = $ref->{regex};

#		print "Trying: $regex\n";

		if ($fn =~ /^$regex/) {

			my $disp = $ref->{disp};
#			print "Match: $fn (disp is $disp)\n";

			if ($disp eq "ignore") {
				last;
			}

			if (! $mtime) {
				my @s = stat($fn);
				if (!@s) {
					print STDERR "Unable to stat $fn : $!\n";
					return;
				}

				$mtime = $s[9];
			}

			if (defined $ref->{mtime}) {
#				print "Checking mtime: $mtime\n";
				if ($mtime >= $ref->{mtime}) {
					last;
				}
			}

			if (defined $ref->{target}) {
				# Convert mtime to ISO8601 format
				my ($ssec,$smin,$shour,$smday,$smon,$syear,@srest) = localtime($mtime);
				$smon ++;
				$syear += 1900;
				my $mstr = sprintf "%04d-%02d-%02d %02d:%02d:%02d", $syear, $smon, $smday, $shour, $smin, $ssec;
#				print "Checking mstr: $mstr\n";
				if ($mstr ge $ref->{target}) {
					next;
				}
			}

			# All tests passed

			if ($disp eq "discard") {
				print "Unlink $fn\n";

				if ($real) {
					unlink($fn);
				}

			} elsif ($disp eq "exec") {
				my $run = sprintf($ref->{cmd}, $fn);
				print "Execute $run\n";

				if ($real) {
					system($run);
				}

			} else {
				print "Unknown disposition: $disp\n";
			}

			# We matched, so we're done checking.
			last;
		}
	}

}

# ---------------------------------------------------------------------------
# Output a usage message
# ---------------------------------------------------------------------------

sub usage {
	die "Usage: logproc [-d] ctlfile";
}
