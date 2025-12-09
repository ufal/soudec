package UD;

our $VERSION = v1.6.0;

=head1 VERSION HISTORY

=over 4

=item v1.6.0 (2025-12-09)

- New function C<property> to retrieve a value of a property of a given attribute at a given node (opposite to C<set_property>) 

=item v1.5.0 (2025-12-08)

- Keeping info about being a part of a multiword at each member

=item v1.4.1 (2025-07-15)

- Recovering from calling C<attr> with undef node (returns undef)
- Recovering from calling C<descendants> with undef node (returns an empty array)

=item v1.4.0 (2025-05-11)

- Adding parameter C<delim> to function C<add_property>

=item v1.3.0 (2025-05-10)

- New function C<add_attr> to add a value to a given attribute at a given node

=item v1.2.0 (2025-05-09)

- New functions C<set_property> and C<add_property>; C<add_property> uses a single entry for multiple-values properties

=item v1.1.0 (2025-04-25)

- Hash-based parameters to the C<descendants> function

=item v1.0.0 (2025-04-18)

- Starting sem-versioning

=back

=cut


use strict;
use warnings;

use LWP::UserAgent;
use URI::Escape;
use JSON;
use Tree::Simple;

use mylog;

use Exporter 'import';  # Allows exporting functions

# Functions available at import if specifically mentioned
# our @EXPORT_OK = qw();

# Functions available at import automatically:
our @EXPORT = qw(parse_conllu
                 root
                 descendants
                 attr
                 set_attr
                 add_attr
                 text
                 property
                 set_property
                 add_property
                 misc_property
                 feat_property
                 member_of_array
                 print_tree
                 call_nametag
                 call_udpipe
                );


=head2 parse_conllu

Parses the CoNLL-U format into Tree::Simple tree structures (one tree per sentence).
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
  my $multiword_ord = ''; # token number range of the current multiword (e.g., '5-6')
  my $multiword_end = ''; # last token number of the current multiword (e.g., 6)

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
            $multiword_ord = $n;
            my ($start, $end) = split('-', $n);
            $multiword_end = $end;
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
          if ($multiword_end and $n<=$multiword_end) { # a part of the current multiword
            set_attr($node, 'multiword_part', $multiword_ord);
            if ($n == $multiword_end) {
              $multiword_ord = '';
              $multiword_end = '';
            }
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
    if (@ordered_nodes) { # not an empty tree
      set_attr($ordered_nodes[-1], 'right', undef);
    }
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

# not used from Jan Štěpánek's UD TrEd extension:

# sub _create_multiword {
#    my ($n, $root, $misc, $form) = @_;
#    my ($from, $to) = split /-/, $n;
#    $root->{multiword} = 'Treex::PML::Factory'->createList([
#        @{ $root->{multiword} || [] },
#        'Treex::PML::Factory'->createStructure(
#            { nodes => 'Treex::PML::Factory'->createList([ $from .. $to ]),
#              misc => $misc,
#              form => $form}
#        )
#    ]);
# }


######### Simple::Tree METHODS #########


=head2 set_attr

Set the value of the given attribute at the given node.

=cut

sub set_attr {
  my ($node, $attr, $value) = @_;
  my $refha_props = $node->getNodeValue();
  $$refha_props{$attr} = $value;
}


=head2 add_attr

Adds the value to the given attribute at the given node. The values are separated by C<delim> (default: ';').

=cut

sub add_attr {
  my ($node, $attr, $value, $delim) = @_;
  $delim = ';' if not defined $delim;
  my $refha_props = $node->getNodeValue();
  my $prev_value = $$refha_props{$attr} // '';
  $prev_value .= $delim if $prev_value;
  $$refha_props{$attr} = "$prev_value$value";
}


=head2 attr

Return the value of the given attribute of the given node.

=cut


sub attr {
  my ($node, $attr) = @_;
  return undef if !$node;
  my $refha_props = $node->getNodeValue();
  return $$refha_props{$attr};
}


=head2 descendants

Returns all descendants of the given node in the dfo.
The hash reference as the second parameter can carry these parameters:
 sort_children: if defined and true, the children are always sorted by attribute 'ord'
 exclude_coord: if defined and true, descendants are given in the UD linguistic sense, i.e., coordination at first level is excluded
 include_root: if defined and true, the given node is included as well

=cut

sub descendants {
  my ($node, $haref_params) = @_;
  
  return () if !$node;
  
  # Use empty hash reference if the second argument is not given (or is not a hash ref)
  $haref_params = {} unless defined $haref_params && ref($haref_params) eq 'HASH';

  # A copy of the parameters without include_root and exclude_coord for recursion (both should happen only at first level)
  my %params_for_recursion = %$haref_params;
  delete $params_for_recursion{include_root};
  delete $params_for_recursion{exclude_coord};
  
  my @descendants = ();
  if ($haref_params->{include_root}) {
    push(@descendants, $node);
  }

  my @children;
  if ($haref_params->{sort_children}) {
    @children = sort {attr($a, 'ord') <=> attr($b, 'ord')} $node->getAllChildren;
  }
  else {
    @children = $node->getAllChildren;
  }
  
  foreach my $child (@children) {

    if ($haref_params->{exclude_coord}) { # coordinated nodes should not be included
      my $deprel = attr($child, 'deprel') // '';
      next if $deprel eq 'conj'; # skip the coordinated node
    }
    
    push(@descendants, $child);
    push(@descendants, descendants($child, \%params_for_recursion));
  }
  return @descendants;
}


=head2 root

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



=head2 text

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


=head2 property

From the given attribute at the given node (e.g., 'misc'), it gets the value of the given property (or undef if not set).

=cut

sub property {
  my ($node, $attr, $property) = @_;
  # mylog(0, "property: '$attr', '$property', '$value'\n");
  my $attr_value = attr($node, $attr);
  return undef if !$attr_value;
  # mylog(0, "property: attr_value: '$attr_value'\n");
  my @attr_properties = grep {$_ =~ /^$property\b/} grep {$_ ne ''} grep {defined} split('\|', $attr_value);
  return undef if !scalar(@attr_properties);
  my $attr_property = $attr_properties[0]; # expect each property to appear only once
  if ($attr_property =~ /$property=(.+)/) {
    my $value = $1;
    return $value;
  }
  return undef;
}


=head2 set_property

In the given attribute at the given node (e.g., 'misc'), it sets the value of the given property (replaces the previous one if present)

=cut

sub set_property {
  my ($node, $attr, $property, $value) = @_;
  # mylog(0, "set_property: '$attr', '$property', '$value'\n");
  my $orig_value = attr($node, $attr) // '';
  # mylog(0, "set_property: orig_value: '$orig_value'\n");
  my @values = grep {$_ !~ /^$property\b/} grep {$_ ne ''} grep {defined} split('\|', $orig_value);
  if ($value) { # if $value is empty, the property name shouldn't be mentioned at all
    push(@values, "$property=$value");
  }
  my @sorted = sort @values;
  my $new_value = join('|', @sorted);
  set_attr($node, $attr, $new_value);
}


=head2 add_property

In the given attribute at the given node (typically, 'misc'), it sets the value of the given property (keeps the previous one if present).
It uses a single property name for multiple values and separates the values by a given delimiter (default: ';').

=cut

sub add_property {
  my ($node, $attr, $property, $value, $delim) = @_;
  $delim = ';' if !$delim;
  # mylog(0, "add_property: '$attr', '$property', '$value', '$delim'\n");
  return if !$value;

  my $orig_attr_value = attr($node, $attr) // '';
  # mylog(0, "add_property: orig_value: '$orig_attr_value'\n");
  my @items = grep {$_ ne ''} grep {defined} split('\|', $orig_attr_value);
  my $found = 0;
  my @new_items = ();
  foreach my $item (@items) { # looking for the property
    if ($item =~ /^$property\b/) { # found the property!
      $found = 1;
      if ($item !~ /=.*\b$value\b/) { # the value not yet in the property
        $item .= "$delim$value";
      }
    }
    push(@new_items, $item);
  }
 
  if (!$found) { # not found - we need to add the new item and sort the items (otherwise the order did not change and we just use the changed list)
    push(@new_items, "$property=$value");
    @new_items = sort @new_items;
  }
  my $new_attr_value = join('|', @new_items);
  set_attr($node, $attr, $new_attr_value);
}


=head2 misc_property

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



=head2 feat_property

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


=head2 print_tree

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


=head2 member_of_array

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


########################################################################
## PARSING THE TEXT WITH UDPIPE
########################################################################


our $udpipe_service_url = 'http://lindat.mff.cuni.cz/services/udpipe/api';
our $nametag_service_url = 'http://lindat.mff.cuni.cz/services/nametag/api';

# Translation of language codes to UDPipe models: 
my %lang2model = (
   'cs' => 'czech',
   'en' => 'english',
   'de' => 'german',
   'es' => 'spanish'
);


=head2 call_udpipe

Calling UDPipe REST API; the input to be processed is passed in the first argument.
The second argument gives the language of the input ('cs', 'en', 'de', 'es').
The third argument ('txt'/'presegmented'/'conllu') gives the input format.
The optional fourth argument ('segment'/'parse'/'all') chooses between the two tasks (or does both, 'all' is default). The 'parse' option expects CoNLL-U input data format.
Returns the output in CoNLL-U format.

=cut

sub call_udpipe {
    my ($text, $language, $input_format, $task) = @_;
    $task = 'all' unless defined $task;
    
    my $model_default = $lang2model{$language};
    if (!$model_default) {
      mylog(2, "call_udpipe: Undefined default model for language '$language'!\n");
    }

    my $model;
    my $input;
    my $tagger;
    my $parser;

    if ($task eq 'segment') {
      $input = 'tokenizer=ranges';
      if ($input_format eq 'presegmented') {
        $input .= ';presegmented';
      }
      $model = "&model=$model_default";
      if ($language eq 'cs') {
        $model = '&model=czech-pdtc1.0'; # longer sentences
      }
      $tagger = '';
      $parser = '';
    }
    elsif ($task eq 'parse') {
      $input = 'input=conllu';
      $model = "&model=$model_default";
      $tagger = '&tagger';
      $parser = '&parser';    
    }
    elsif ($task eq 'all') {
      $input = 'tokenizer=ranges';
      if ($input_format eq 'presegmented') {
        $input .= ';presegmented';
      }
      $model = "&model=$model_default";
      $tagger = '&tagger';
      $parser = '&parser';    
    }

    # Funkční volání metodou POST, i když podivně kombinuje URL-encoded s POST

    # Nastavení URL pro volání REST::API s parametry
    #my $url = "http://lindat.mff.cuni.cz/services/udpipe/api/process?$input$model$tagger$parser";
    my $url = "$udpipe_service_url/process?$input$model$tagger$parser";
    mylog(2, "Call UDPipe: URL=$url\n");
    
    my $ua = LWP::UserAgent->new;

    # Define the data to be sent in the POST request
    my $data = "data=" . uri_escape_utf8($text);

    my $req = HTTP::Request->new('POST', $url);
    $req->header('Content-Type' => 'application/x-www-form-urlencoded');
    $req->content($data);


    # Odeslání požadavku a získání odpovědi
    my $res = $ua->request($req);

    # Zkontrolování, zda byla odpověď úspěšná
    if ($res->is_success) {
        # Získání odpovědi v JSON formátu
        my $json_response = decode_json($res->content);
        # Zpracování odpovědi
        my $result = $json_response->{result};
        # print STDERR "UDPipe result:\n$result\n";
        return $result;
    } else {
        mylog(2, "call_udpipe: URL: $url\n");
        mylog(1, "call_udpipe: Text: $text\n");
        mylog(2, "call_udpipe: Chyba: " . $res->status_line . "\n");
        return '';
    }
}



########################################################################
## RECOGNITION OF NAMED ENTITIES WITH NAMETAG
########################################################################

=head2 call_nametag

Calling NameTag REST API; the text to be searched is passed in the argument in UD CONLL format
Returns the text in UD CONLL-NE format.
This function just splits the input conll format to individual sentences (or a few of sentences if $max_sentences is set to a larger number than 1) and calls function call_nametag_part on this part of the input, to avoid the NameTag error caused by a too large argument.

=cut

sub call_nametag {
    my $conll = shift;
    
    my $result = '';
    
    # Let us call NameTag api for each X sentences separately, as too large input produces an error.
    my $max_sentences = 1000;
    
    my $conll_part = '';
    my $sent_count = 0;
    foreach my $line (split /\n/, $conll) {
      #mylog(0, "Processing line $line\n");
      $conll_part .= $line . "\n";
      if ($line =~ /^\s*$/) { # empty line means end of sentence
        #mylog(0, "Found an empty line.\n");
        $sent_count++;
        if ($sent_count eq $max_sentences) {
          $result .= call_nametag_part($conll_part);
          $conll_part = '';
          $sent_count = 0;
        }
      }
    }
    if ($conll_part) { # We need to call NameTag one more time
      $result .= call_nametag_part($conll_part);    
    }
    return $result;
}


=head2 call_nametag_part

Now actually calling NameTag REST API for a small part of the input (to avoid error caused by a long argument).
Returns the text in UD CONLL-NE format.
If an error occurs, the function just returns the input conll text unchanged.

=cut

sub call_nametag_part {
    my $conll = shift;

    # Funkční volání metodou POST, i když podivně kombinuje URL-encoded s POST

    # Nastavení URL pro volání REST::API s parametry
    my $url = "$nametag_service_url/recognize?input=conllu&output=conllu-ne";
    mylog(2, "Call NameTag: URL=$url\n");

    my $ua = LWP::UserAgent->new;

    # Define the data to be sent in the POST request
    my $data = "data=" . uri_escape_utf8($conll);

    my $req = HTTP::Request->new('POST', $url);
    $req->header('Content-Type' => 'application/x-www-form-urlencoded');
    $req->content($data);


    # Odeslání požadavku a získání odpovědi
    my $res = $ua->request($req);

    # Zkontrolování, zda byla odpověď úspěšná
    if ($res->is_success) {
        # Získání odpovědi v JSON formátu
        my $json_response = decode_json($res->content);
        # Zpracování odpovědi
        my $result = $json_response->{result};
        # mylog(0, "NameTag result:\n$result\n");
        return $result;
    } else {
        mylog(2, "call_nametag_part: URL: $url\n");
        mylog(2, "call_nametag_part: Chyba: " . $res->status_line . "\n");
        return $conll; 
    }
}


1;
