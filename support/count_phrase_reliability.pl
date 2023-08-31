#!/usr/bin/perl

#######################################################################
# Counting reliability of phrases out of the err log (coming via STDIN)
#
# Expecting lines such as:
# RELIABILITY_COUNT       rozhodnout      no_constraint   FALSE_POSITIVE
# RELIABILITY_COUNT       mít     to-za   HIT
# RELIABILITY_COUNT       informovat      no_constraint   HIT_PARTIAL
#
# For now, it ignores the constraints. Also, a partial hit is a hit.
#
#######################################################################

use strict;
use warnings;
use utf8;
use open qw(:std :utf8);
# STDIN and STDOUT in UTF-8
binmode STDIN, ':encoding(UTF-8)';
binmode STDOUT, ':encoding(UTF-8)';

my %lemma2hits;
my %lemma2total;

while (<>) {
  if (/^RELIABILITY_COUNT\t(\S+)\t(\S+)\t(\S+)$/) {
    my ($lemma, $constraint, $hit) = ($1, $2, $3);
    $lemma2total{$lemma}++;
    if ($hit =~ /HIT/) {
      $lemma2hits{$lemma}++;
    }
  }
}

foreach my $lemma (sort keys(%lemma2total)) {
  my $hits = $lemma2hits{$lemma} || 0;
  my $total = $lemma2total{$lemma};
  print "$lemma\t$total\t$hits\n";
}
