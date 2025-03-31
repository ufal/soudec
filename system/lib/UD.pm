package UD;

use strict;
use warnings;
use Exporter 'import';  # Umožňuje export funkcí
use Tree::Simple;

# Definice exportovaných funkcí
# our @EXPORT_OK = qw();  # Funkce, které budou dostupné při importu, pokud specificky zmíněny
our @EXPORT = qw(parse_conllu root descendants attr set_attr);  # Funkce, které budou dostupné při importu automaticky


=item

Parses the CONLL-U format into Tree::Simple tree structures (one tree per sentence)

=cut

sub parse_conllu {
  my $conllu_string = shift;

  my @lines = split("\n", $conllu_string);

  my @trees = (); # array of trees in the document

  my $root; # a single root

  my $min_start = 10000; # from indexes of the tokens, we will get indexes of the sentence
  my $max_end = 0;

  my $multiword = ''; # store a multiword line to keep with the following token

  my $gord = 0; # global ord of a token in the document
  # the following cycle for reading UD CONLL is modified from Jan Štěpánek's UD TrEd extension
  foreach my $line (@lines) {
      chomp($line);
      # print STDERR "Line: $line\n";
      if ($line =~ /^\d+\.\d+/) { # a generated zero - ignore for now (this is a hack!)
        next;
      }
      if ($line =~ /^#/ && !$root) {
          $root = Tree::Simple->new({}, Tree::Simple->ROOT);
          # print STDERR "Beginning of a new sentence!\n";
      }

      if ($line =~ /^#\s*newdoc/) { # newdoc
          set_attr($root, 'newdoc', $line); # store the whole line incl. e.g. id = ...
      } elsif ($line =~ /^#\s*newpar/) { # newpar
          set_attr($root, 'newpar', $line); # store the whole line incl. e.g. id = ...
      } elsif ($line =~ /^#\s*sent_id\s=\s*(\S+)/) {
          my $sent_id = $1; # substr $sent_id, 0, 0, 'PML-' if $sent_id =~ /^(?:[0-9]|PML-)/;
          set_attr($root, 'id', $sent_id);
      } elsif ($line =~ /^#\s*text\s*=\s*(.*)/) {
          set_attr($root, 'text', $1);
          #print STDERR "Reading sentence '$1'\n";
      } elsif ($line =~ /^#/) { # other comment, store it as well (all other comments in one attribute other_comment with newlines included)
          my $other_comment_so_far = attr($root, 'other_comment') // '';
          set_attr($root, 'other_comment', $other_comment_so_far . $line . "\n");
          
      } elsif ($line =~ /^$/) { # empty line, i.e. end of a sentence
          _create_structure($root);
          set_attr($root, 'start', $min_start);
          set_attr($root, 'end', $max_end);
          $min_start = $min_start = 10000;
          $max_end = 0;
          push(@trees, $root);
          #print STDERR "End of sentence id='" . attr($root, 'id') . "'.\n\n";
          $root = undef;

      } else { # a token
          my ($n, $form, $lemma, $upos, $xpos, $feats, $head, $deprel,
              $deps, $misc) = split (/\t/, $line);
          $_ eq '_' and undef $_
              for $xpos, $feats, $deps, $misc;

          # $misc = 'Treex::PML::Factory'->createList( [ split /\|/, ($misc // "") ]);
          #if ($n =~ /-/) {
          #    _create_multiword($n, $root, $misc, $form);
          #    next
          #}
          if ($n =~ /-/) { # a multiword line, store it to keep with the next token
            $multiword = $line;
            next;
          }
          
          #$feats = _create_feats($feats);
          #$deps = [ map {
          #    my ($parent, $func) = split /:/;
          #    'Treex::PML::Factory'->createContainer($parent,
          #                                            {func => $func});
          #} split /\|/, ($deps // "") ];

          my $node = Tree::Simple->new({});
          set_attr($node, 'ord', $n);
          $gord++; # the global ord of the token in the document
          set_attr($node, 'gord', $gord);
          set_attr($node, 'form', $form);
          set_attr($node, 'lemma', $lemma);
          set_attr($node, 'deprel', $deprel);
          set_attr($node, 'upostag', $upos);
          set_attr($node, 'xpostag', $xpos);
          set_attr($node, 'feats', $feats);
          set_attr($node, 'deps', $deps); # 'Treex::PML::Factory'->createList($deps),
          set_attr($node, 'misc', $misc);
          set_attr($node, 'head', $head);
          
          if ($multiword) { # the previous line was a multiword, store it at the current token
            set_attr($node, 'multiword', $multiword);
            $multiword = '';
          }
          
          if ($misc and $misc =~ /TokenRange=(\d+):(\d+)\b/) {
            my ($start, $end) = ($1, $2);
            set_attr($node, 'start', $start);
            set_attr($node, 'end', $end);
            $min_start = $start if $start < $min_start;
            $max_end = $end if $end > $max_end;          
          }
          
          $root->addChild($node);
          
      }
  }
  # If there wasn't an empty line at the end of the file, we need to process the last tree here:
  if ($root) {
      _create_structure($root);
      set_attr($root, 'start', $min_start);
      set_attr($root, 'end', $max_end);
      push(@trees, $root);
      #print STDERR "End of sentence id='" . attr($root, 'id') . "'.\n\n";
      $root = undef;
      #warn "Emtpy line missing at the end of input\n";
  }
  # end of Jan Štěpánek's modified cycle for reading UD CONLL

  # Now let us add pointers to immediately left and right nodes in the sentence surface order
  # And also pointers at roots to left and right neigbouring trees
  my $prev_tree = undef;
  foreach my $tree (@trees) {
    # pointers to left and right trees at roots
    if ($prev_tree) {
      set_attr($prev_tree, 'right', $tree);
      set_attr($tree, 'left', $prev_tree);
    }
    $prev_tree = $tree;
    # pointers at nodes to left and right nodes
    my @ordered_nodes = sort {attr($a, 'ord') <=> attr($b, 'ord')} descendants($tree);
    my $prev_node = undef;
    foreach my $node (@ordered_nodes) {
      set_attr($node, 'left', $prev_node);
      if ($prev_node) {
        set_attr($prev_node, 'right', $node);
      }
      $prev_node = $node;
    }
    set_attr($ordered_nodes[-1], 'right', undef);
  }

  return @trees;
}


# the following function is modified from Jan Štěpánek's UD TrEd extension
sub _create_structure {
    my ($root) = @_;
    my %node_by_ord = map +(attr($_, 'ord') => $_), $root->getAllChildren;
    # mylog(0, "_create_structure: \%node_by_ord:\n");
    foreach my $ord (sort {$a <=> $b} keys(%node_by_ord)) {
      # mylog(0, "_create_structure:   - $ord: " . attr($node_by_ord{$ord}, 'form') . "\n");
    }
    foreach my $node ($root->getAllChildren) {
        my $head = attr($node, 'head');
        # mylog(0, "_create_structure: head $head\n");
        if ($head) { # i.e., head is not 0, meaning this node should not be a child of the technical root
            my $parent = $node->getParent();
            $parent->removeChild($node);
            my $new_parent = $node_by_ord{$head};
            $new_parent->addChild($node);
        }
    }
}



######### Simple::Tree METHODS #########

sub set_attr {
  my ($node, $attr, $value) = @_;
  my $refha_props = $node->getNodeValue();
  $$refha_props{$attr} = $value;
}

sub attr {
  my ($node, $attr) = @_;
  my $refha_props = $node->getNodeValue();
  return $$refha_props{$attr};
}


=item descendants

Returns all descendants of the given node in the dfo; on the same level, the nodes are sorted by attribute 'ord'

=cut

sub descendants {
  my $node = shift;
  my @descendants = ();
  my @children = sort {attr($a, 'ord') <=> attr($b, 'ord')} $node->getAllChildren;
  foreach my $child (@children) {
    push(@descendants, $child);
    push(@descendants, descendants($child));
  }
  return @descendants;
}


sub root {
  my $node = shift;

  my $parent = $node->getParent;
#  while ($parent and $parent ne 'root' and $parent ne 'ROOT') { # to be sure - the documentation says 'ROOT', in practice its 'root'
  while ($parent and $parent ne 'root' and $parent ne 'ROOT') { # to be sure - the documentation says 'ROOT', in practice its 'root'
    # mylog(0, "root: found a parent\n");
    $node = $parent;
    $parent = $node->getParent;
  }
  return $node;
}


1;
