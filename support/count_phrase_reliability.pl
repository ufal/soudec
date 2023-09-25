#!/usr/bin/perl

#######################################################################
# Counting reliability of phrases out of the err log (coming via STDIN)
#
# Expecting lines such as:
# RELIABILITY_COUNT       rozhodnout      no_constraint   FALSE_POSITIVE
# RELIABILITY_COUNT       mít     to-za   HIT
# RELIABILITY_COUNT       informovat      no_constraint   HIT_PARTIAL
#
# A partial hit is a hit.
#
#######################################################################

use strict;
use warnings;
use utf8;
use open qw(:std :utf8);
# STDIN and STDOUT in UTF-8
binmode STDIN, ':encoding(UTF-8)';
binmode STDOUT, ':encoding(UTF-8)';

my %lemma_constraint2hits;
my %lemma_constraint2total;

while (<>) {
  if (/^RELIABILITY_COUNT\t(\S+)\t(\S+)\t(\S+)$/) {
    my ($lemma, $constraint, $hit) = ($1, $2, $3);
    $lemma_constraint2total{"$lemma\t$constraint"}++;
    if ($hit =~ /HIT/) {
      $lemma_constraint2hits{"$lemma\t$constraint"}++;
    }
  }
}

foreach my $lemma_constraint (sort keys(%lemma_constraint2total)) {
  my $hits = $lemma_constraint2hits{$lemma_constraint} || 0;
  my $total = $lemma_constraint2total{$lemma_constraint};
  $lemma_constraint =~ s/NoConstraint//;
  print "$total\t$hits\t$lemma_constraint\n";
}
