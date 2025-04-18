package mylog;

our $VERSION = v1.0.0;

use strict;
use warnings;
use Exporter 'import';  # Allows exporting functions

our @EXPORT = qw(mylog); 

our $logging_level = 0; # default logging level
our $name = 'MyLog'; # default prefix for logging


=item log

A function to print log (debug) info based on global $logging_level (0=full, 1=limited, 2=minimal, 3=none).
The message only gets printed (to STDERR) if given $level is greater than or equal to global $logging_level.

=cut

sub mylog {
  my ($level, $msg) = @_;
  if ($level >= $logging_level) {
    print STDERR "$name: $msg";
  }
}


1;
