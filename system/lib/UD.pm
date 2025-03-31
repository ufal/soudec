package UD;

use strict;
use warnings;
use Exporter 'import';  # Allows exporting functions
use Tree::Simple;

# Definitions of functions to be exported
# our @EXPORT_OK = qw();  # Functions available at import if specifically mentioned
our @EXPORT = qw(parse_conllu root descendants attr set_attr text misc_property feat_property member_of_array print_tree);  # Functions available at import automatically



=item

Parses the CONLL-U format into Tree::Simple tree structures (one tree per sentence).
Returns an array of tree tree roots.

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

=item

# not used from Jan Štěpánek's UD TrEd extension:

sub _create_multiword {
    my ($n, $root, $misc, $form) = @_;
    my ($from, $to) = split /-/, $n;
    $root->{multiword} = 'Treex::PML::Factory'->createList([
        @{ $root->{multiword} || [] },
        'Treex::PML::Factory'->createStructure(
            { nodes => 'Treex::PML::Factory'->createList([ $from .. $to ]),
              misc => $misc,
              form => $form}
        )
    ]);
}

=cut


######### Simple::Tree METHODS #########


=item set_attr

Set the value of the given attribute of the given node.

=cut

sub set_attr {
  my ($node, $attr, $value) = @_;
  my $refha_props = $node->getNodeValue();
  $$refha_props{$attr} = $value;
}


=item set_attr

Return the value of the given attribute of the given node.

=cut


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


=item

Return the root of the tree of the given node.

=cut

sub root {
  my $node = shift;

  my $parent = $node->getParent;
  while ($parent and $parent ne 'root' and $parent ne 'ROOT') { # to be sure - the documentation says 'ROOT', in practice its 'root'
    $node = $parent;
    $parent = $node->getParent;
  }
  return $node;
}



=item text

Given a reference to an array of nodes, give surface text they represent.

=cut

sub text {
  my $aref_nodes = shift;
  my @ord_sorted = sort {attr($a, 'ord') <=> attr($b, 'ord')} @$aref_nodes;
  my $text = '';
  my $space_before = '';
  foreach my $token (@ord_sorted) {
    # mylog(0, "surface_text: processing token " . attr($token, 'form') . "\n");
    $text .= $space_before . attr($token, 'form');
    my $SpaceAfter = misc_property($token, 'SpaceAfter') // '';
    $space_before = $SpaceAfter eq 'No' ? '' : ' ';
  }
  return $text;
}


=item misc_property

Returns a value of the given property from the misc attribute. Or undef.

=cut

sub misc_property {
  my ($node, $property) = @_;
  my $misc = attr($node, 'misc') // '';
  # mylog(0, "misc_property: token='" . attr($node, 'form') . "', misc=$misc\n");
  if ($misc =~ /$property=([^|]+)/) {
    my $value = $1;
    # mylog(0, "misc_property: $property=$value\n");
    return $value;
  }
  return undef;
}  



=item feat_property

Returns a value of the given property from the feats attribute. Or undef.

=cut

sub feat_property {
  my ($node, $property) = @_;
  my $feats = attr($node, 'feats') // '';
  # mylog(0, "feat_property: feats=$feats\n");
  if ($feats =~ /$property=([^|]+)/) {
    my $value = $1;
    # mylog(0, "feat_property: $property=$value\n");
    return $value;
  }
  return undef;
}  


=item print_tree

Simple recursive printing of a subtree of a given node. If a second parameter is given, it is used as a prefix for each output line.

=cut

sub print_tree {
    my ($node, $pre) = @_;
    $pre = '' unless defined $pre;
    my @children = $node->getAllChildren();
    foreach my $child (@children) {
        my $ord = attr($child, 'ord') // 'no_ord';
        my $form = attr($child, 'form') // 'no_form';
	#mylog(0, "$ord$pre$form\n");
	print STDERR "$ord$pre$form\n";
        print_tree($child, $pre . "\t");
    }
}


=item member_of_array

Checks if a given scalar is a member of a given array (passed as a reference).

=cut

sub member_of_array {
  my ($m, $aref) = @_;
  return 0 if (!$m or !$aref);
  foreach my $a (@$aref) {
    if ($m eq $a) {
      return 1;
    }
  }
  return 0;
}


1;
