#!/usr/bin/perl
use strict;
use warnings;
use utf8;
use open qw(:std :utf8);
use LWP::UserAgent;
use URI::Escape;
use JSON;
use Tree::Simple;
use List::Util qw(min max);

my $MIN_RELIABILITY = 10; # minimal required phrase reliability

my ($file_name, $spolehlivost_frazi, $ann) = @ARGV;

print STDERR "\n####################################################################\n";

# Let us first read the file with reliability of citation phrases

my %phrase2reliability; # reliability of the phrase in percents (in how many percents it was used in training data as a citation phrase)
my %phrase2se_si; # does the phrase require "se/si" to be a citation phrase? (maybe not needed and not yet implemented!)

open (PHRASES, '<:encoding(utf8)', $spolehlivost_frazi)
  or die "Nepodařilo se otevřít soubor '$spolehlivost_frazi' pro čtení: $!";

print STDERR "Reading phrases and their reliability from $spolehlivost_frazi\n";
my $phrases_count = 0;
while (<PHRASES>) {
  chomp();
  my $line = $_;
  if ($line =~ /^(\d+)\t(\d+)\t(\S+)\t(\S*)$/) {
    my $all_occurrences = $1;
    my $used_as_citation_phrase = $2;
    my $phrase = $3;
    my $se_si = $4;
    my $reliability = $used_as_citation_phrase / $all_occurrences;
    my $reliability_percent = 100 * sprintf("%.2f", $reliability);
    # print STDERR "Phrase $phrase ($se_si) with reliability $reliability_percent\n";
    $phrases_count++;
    $phrase2reliability{$phrase} = $reliability_percent;
    $phrase2se_si{$phrase} = $se_si;
  }
  else {
    print STDERR "Unknown format of a line in file $spolehlivost_frazi:\n$line\n";
  }
}
print STDERR "$phrases_count phrases have been read from file $spolehlivost_frazi:\n";


###################################################################################
# If an .ann file with manual annotation is provided for measuring the success rate, read the file now
# e.g.
# T16	anonymous-partial 1360 1365	vědců
# T23	PHRASE 1354 1359	podle
###################################################################################

# hashes to keep info about manual annotation
my %h_ann_phrase_range2text; # '1354:1359' => 'podle'
my %h_ann_source_range2text; # '1360:1365' => 'vědců'
my %h_ann_source_range2type; # '1360:1365' => 'anonymous-partial'

# similar hashes to collect info about automatic recognition, to be compared with manual
my %h_phrase_range2text;
my %h_source_range2text;
my %h_source_range2type;


if ($ann) {
  open my $ann_handle, '<:encoding(utf8)', $ann
    or die "Cannot open file '$ann' for reading: $!";
  print STDERR "Reading manual annotation from $ann\n";
  while(my $line = <$ann_handle>) {
    if ($line =~ /^\S+\t(\S+)\ (\d+) (\d+)\t(.+)$/) {
      my ($event, $start, $end, $text) = ($1, $2, $3, $4);
      if ($event =~ /PHRASE/) {
        $h_ann_phrase_range2text{"$start:$end"} = $text;
      }
      else {
        $h_ann_source_range2text{"$start:$end"} = $text;
        $h_ann_source_range2type{"$start:$end"} = $event;        
      }
    }
  }
  close($ann_handle);
  print STDERR " - PHRASES:\n";
  foreach my $range (keys(%h_ann_phrase_range2text)) {
    print STDERR "   - $range - $h_ann_phrase_range2text{$range}\n";
  }
  print STDERR " - SOURCES:\n";
  foreach my $range (keys(%h_ann_source_range2text)) {
    print STDERR "   - $range - $h_ann_source_range2text{$range} - $h_ann_source_range2type{$range}\n";
  }
}


###################################################################################
# Now let us read the text file where citations should be searched for
###################################################################################

open my $file_handle, '<:encoding(utf8)', $file_name
  or die "Cannot open file '$file_name' for reading: $!";

# Načtení obsahu souboru do proměnné
my $file_content = do { local $/; <$file_handle> };

close $file_handle;

#print STDERR $file_content;


###################################################################################
# Let us parse the file using UDPipe REST API
###################################################################################

my $conll_data = call_udpipe($file_content);

# Store the result to a file (just to have it, not needed for further processing)
open(OUT, '>:encoding(utf8)', "$file_name.conll") or die "Cannot open file '$file_name.conll' for writing: $!";
print OUT $conll_data;
close(OUT);

# Now let us add info about named entities using NameTag REST API

my $conll_data_ne = call_nametag($conll_data);

# Store the result to a file (just to have it, not needed for further processing)
open(OUT, '>:encoding(utf8)', "$file_name.conllne") or die "Cannot open file '$file_name.conllne' for writing: $!";
print OUT $conll_data_ne;
close(OUT);


###################################################################################
# Let us parse the CONLL format into Tree::Simple tree structures (one per sentence)
###################################################################################

my @lines = split("\n", $conll_data);

my @trees = (); # array of trees in the document

my $root; # a single root

my $min_start = 10000; # from indexes of the tokens, we will get indexes of the sentence
my $max_end = 0;

# the following cycle for reading UD CONLL is modified from Jan Štěpánek's UD TrEd extension
foreach my $line (@lines) {
    chomp($line);
    #print STDERR "Line: $line\n";
    if ($line =~ /^#/ && !$root) {
        $root = Tree::Simple->new({}, Tree::Simple->ROOT);
        #print STDERR "Beginning of a new sentence!\n";
    }

    if ($line =~ /^#\s*sent_id\s=\s*(\S+)/) {
        my $sent_id = $1; # substr $sent_id, 0, 0, 'PML-' if $sent_id =~ /^(?:[0-9]|PML-)/;
        set_attr($root, 'id', $sent_id);

    } elsif ($line =~ /^#\s*text\s*=\s*(.*)/) {
        set_attr($root, 'text', $1);
        #print STDERR "Reading sentence '$1'\n";

    } elsif ($line =~ /^$/) {
        _create_structure($root);
        set_attr($root, 'start', $min_start);
        set_attr($root, 'end', $max_end);
        $min_start = $max_end = 0;
        push(@trees, $root);
        #print STDERR "End of sentence id='" . attr($root, 'id') . "'.\n\n";
        $root = undef;

    } elsif ($line =~ /^#\s+new(doc|par)(?:\s+id = (.*))?/) {
        my $docparid = '';
        if ($2) {
          $docparid = $2;
        }
        set_attr($root, "$1", "docparid");

    } elsif ($line =~ /^#/) {
        #$root->{comment} = 'Treex::PML::Factory'->createList([@{ $root->{comment} || [] }, substr $_, 1 ]);

    } else {
        my ($n, $form, $lemma, $upos, $xpos, $feats, $head, $deprel,
            $deps, $misc) = split (/\t/, $line);
        $_ eq '_' and undef $_
            for $xpos, $feats, $deps, $misc;

        # $misc = 'Treex::PML::Factory'->createList( [ split /\|/, ($misc // "") ]);
        #if ($n =~ /-/) {
        #    _create_multiword($n, $root, $misc, $form);
        #    next
        #}
        next if $n =~ /-/; # For now, let us get rid of joined tokens (e.g. 5-6)

        #$feats = _create_feats($feats);
        #$deps = [ map {
        #    my ($parent, $func) = split /:/;
        #    'Treex::PML::Factory'->createContainer($parent,
        #                                            {func => $func});
        #} split /\|/, ($deps // "") ];

        my $node = Tree::Simple->new({});
        set_attr($node, 'ord', $n);
        set_attr($node, 'form', $form);
        set_attr($node, 'lemma', $lemma);
        set_attr($node, 'deprel', $deprel);
        set_attr($node, 'upostag', $upos);
        set_attr($node, 'xpostag', $xpos);
        set_attr($node, 'feats', $feats);
        set_attr($node, 'deps', $deps); # 'Treex::PML::Factory'->createList($deps),
        set_attr($node, 'misc', $misc);
        set_attr($node, 'head', $head);
        
        if ($misc =~ /TokenRange=(\d+):(\d+)\b/) {
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



###################################################################################
# Now we have dependency trees of the sentences; let us search for citation phrases
###################################################################################


foreach $root (@trees) {
  print STDERR "\n====================================================================\n";
  print STDERR "Sentence id=" . attr($root, 'id') . ": " . attr($root, 'text') . "\n";
  # print_children($root, "\t");
  
  my @nodes = descendants($root);
  foreach my $node (@nodes) {
    my $form_lc = lc(attr($node, 'form'));
    my $reliability = $phrase2reliability{$form_lc};
    if ($reliability) {
      print STDERR "Found phrase '$form_lc' with reliability $reliability\n";
      if ($reliability > $MIN_RELIABILITY) {
        print STDERR " - reliability is greater than threshold $MIN_RELIABILITY\n";
        evaluate_single_event('phrase', $node);
        if ($form_lc eq 'podle') { # special treatment
          my $parent = $node->getParent;
          my $source = attr($parent, 'form');
          my @whole_source_nodes = get_whole_source_nodes($parent);
          my $whole_source = get_text(@whole_source_nodes);
          print STDERR " - SOURCE parent: $source\n - WHOLE SOURCE: $whole_source\n";
          evaluate_single_event('source', @whole_source_nodes);
        }
        else {
          my @children = $node->getAllChildren;
          my @nsubj = grep {attr($_, 'deprel') eq 'nsubj'} @children;
          if (@nsubj) {
            my $subject = attr($nsubj[0], 'form');
            my @whole_source_nodes = get_whole_source_nodes($nsubj[0]);
            my $whole_source = get_text(@whole_source_nodes);
            print STDERR " - SOURCE nsubj: $subject\n - WHOLE SOURCE: $whole_source\n";
            evaluate_single_event('source', @whole_source_nodes);
          }
        }
      }
    }
  }
}


###################################################################################
# Now evaluate the results and print info to STDERR
# (from there it will be collected over multiple texts externally)
#
# hashes to keep info about manual annotation:
# my %h_ann_phrase_range2text; # '1354:1359' => 'podle'
# my %h_ann_source_range2text; # '1360:1365' => 'vědců'
# my %h_ann_source_range2type; # '1360:1365' => 'anonymous-partial'
#
# similar hashes for automatic recognition, to be compared with manual:
# my %h_phrase_range2text;
# my %h_source_range2text;
# my %h_source_range2type;
###################################################################################

# phrases:

my @a_phrase_ranges = keys(%h_phrase_range2text);
foreach my $ann_phrase_range (keys(%h_ann_phrase_range2text)) {
  my $text = $h_ann_phrase_range2text{$ann_phrase_range};
  my $sentence = get_sentence($ann_phrase_range);
  if ($h_phrase_range2text{$ann_phrase_range}) {
    print_eval('EVALUATION-EXACT-PHRASE-HIT', $ann_phrase_range, $text, $ann_phrase_range, $text, $sentence);
    print_eval('EVALUATION-PARTIAL-PHRASE-HIT', $ann_phrase_range, $text, $ann_phrase_range, $text, $sentence);
  }
  else {
    print_eval('EVALUATION-EXACT-PHRASE-FALSE-NEGATIVE', 'N/A', 'N/A', $ann_phrase_range, $text, $sentence);
    my $partial_phrase_range = partial_match($ann_phrase_range, \%h_phrase_range2text);
    if ($partial_phrase_range) {
      my $partial_text = $h_phrase_range2text{$partial_phrase_range};
      print_eval('EVALUATION-PARTIAL-PHRASE-HIT', $partial_phrase_range, $partial_text, $ann_phrase_range, $text, $sentence);
    }
    else {
      print_eval('EVALUATION-PARTIAL-PHRASE-FALSE-NEGATIVE', 'N/A', 'N/A', $ann_phrase_range, $text, $sentence);
    }
  }
}

foreach my $phrase_range (keys(%h_phrase_range2text)) {
  next if $h_ann_phrase_range2text{$phrase_range}; # exact hit, already reported
  my $text = $h_phrase_range2text{$phrase_range};
  my $sentence = get_sentence($phrase_range);
  print_eval('EVALUATION-EXACT-PHRASE-FALSE-POSITIVE', $phrase_range, $text, 'N/A', 'N/A', $sentence);
  
  next if partial_match($phrase_range, \%h_ann_phrase_range2text); # partial hit, already reported
  print_eval('EVALUATION-PARTIAL-PHRASE-FALSE-POSITIVE', $phrase_range, $text, 'N/A', 'N/A', $sentence);
}

# sources:

my @a_source_ranges = keys(%h_source_range2text);
foreach my $ann_source_range (keys(%h_ann_source_range2text)) {
  my $text = $h_ann_source_range2text{$ann_source_range};
  my $sentence = get_sentence($ann_source_range);
  if ($h_source_range2text{$ann_source_range}) {
    print_eval('EVALUATION-EXACT-SOURCE-HIT', $ann_source_range, $text, $ann_source_range, $text, $sentence);
    print_eval('EVALUATION-PARTIAL-SOURCE-HIT', $ann_source_range, $text, $ann_source_range, $text, $sentence);
  }
  else {
    print_eval('EVALUATION-EXACT-SOURCE-FALSE-NEGATIVE', 'N/A', 'N/A', $ann_source_range, $text, $sentence);
    my $partial_source_range = partial_match($ann_source_range, \%h_source_range2text);
    if ($partial_source_range) {
      my $partial_text = $h_source_range2text{$partial_source_range};
      print_eval('EVALUATION-PARTIAL-SOURCE-HIT', $partial_source_range, $partial_text, $ann_source_range, $text, $sentence);
    }
    else {
      print_eval('EVALUATION-PARTIAL-SOURCE-FALSE-NEGATIVE', 'N/A', 'N/A', $ann_source_range, $text, $sentence);
    }
  }
}

foreach my $source_range (keys(%h_source_range2text)) {
  next if $h_ann_source_range2text{$source_range}; # exact hit, already reported
  my $text = $h_source_range2text{$source_range};
  my $sentence = get_sentence($source_range);
  print_eval('EVALUATION-EXACT-SOURCE-FALSE-POSITIVE', $source_range, $text, 'N/A', 'N/A', $sentence);
  
  next if partial_match($source_range, \%h_ann_source_range2text); # partial hit, already reported
  print_eval('EVALUATION-PARTIAL-SOURCE-FALSE-POSITIVE', $source_range, $text, 'N/A', 'N/A', $sentence);
}



=item print_eval

Prints a single evaluation out to STDERR in TSV and HTML formats.

=cut

sub print_eval {
  my ($type, $auto_range, $auto_text, $ann_range, $ann_text, $sentence) = @_;
  # first print the simple TSV evaluation line:
  print STDERR "TSV-$type\t$auto_range\t$auto_text\t$ann_range\t$ann_text\t$sentence\n";
  # now produce the HTML evaluation line:
  my $color = 'green'; # default for HIT
  if ($type =~ /NEGATIVE/) {
    $color = 'blue';
  }
  elsif ($type =~ /POSITIVE/) {
    $color = 'red';
  }
  my $background = 'white'; # default for sources
  if ($type =~ /PHRASE/) {
    $background = 'beige';
  }
  print STDERR "<tr style=\"color: $color; background-color: $background\"><td>HTML-$type</td><td>$auto_text</td><td>$ann_text</td><td>$sentence</td></tr>\n";
}



=item get_sentence

Given a range of text indexes (e.g. "124:129"), it returns the sentence to which the range belongs.

=cut

sub get_sentence {
  my $range = shift;
  if ($range =~ /^(\d+):(\d+)/) {
    my ($start, $end) = ($1, $2);
    foreach $root (@trees) { # go through all sentences
      if (attr($root, 'start') <= $start and attr($root, 'end') >= $end) { # we found the tree
        return attr($root, 'text');
      }
    }
  }
  else {
    return 'N/A';
  }
}


=item partial_match

Returns range from keys of given hash that at least partially overlaps with the given range.
Otherwise returns undef.

=cut

sub partial_match {
  my ($range, $rh_range2text) = @_;
  if ($range =~ /^(\d+):(\d+)$/) {
    my ($start, $end) = ($1, $2);
    my @ranges = keys(%$rh_range2text);
    foreach my $r (@ranges) {
      if ($r =~ /^(\d+):(\d+)$/) {
        my ($s, $e) = ($1, $2);
        next if ($e<$start or $end<$s);
        return $r;
      }
    }
  }
  return undef;
}

=item evaluate_single_event

Checks the event (source or phrase) with the given nodes representing a text for presence in the manual annotation.
Prints immediate info about matching/missing
and collects info about automatic annotation in these hashes:
my %h_phrase_range2text;
my %h_source_range2text;
my %h_source_range2type; (not yet used)

=cut

sub evaluate_single_event {
  my ($event, @nodes) = @_;
  return if !$ann; # do nothing if no manuall annotation was provided
  
  my $eval;
  my $range = get_range(@nodes);
  my $text = get_text(@nodes);
  
  if ($event eq 'source') {
    $h_source_range2text{$range} = get_text(@nodes);
    if ($h_ann_source_range2text{$range}) {
      $eval = "HIT";
    }
    else {
      my $partial_source_range = partial_match($range, \%h_ann_source_range2text);
      if ($partial_source_range) {
        my $partial_text = $h_ann_source_range2text{$partial_source_range};
        $eval = "PARTIAL: '$text' vs. manual '$partial_text'\n";
      }
      else {
        $eval = "MISS";
      }
    }
  }
  else { # phrase
    $h_phrase_range2text{$range} = get_text(@nodes);
    if ($h_ann_phrase_range2text{$range}) {
      $eval = "HIT";
    }
    else {
      my $partial_phrase_range = partial_match($range, \%h_ann_phrase_range2text);
      if ($partial_phrase_range) {
        my $partial_text = $h_ann_phrase_range2text{$partial_phrase_range};
        $eval = "PARTIAL: '$text' vs. manual '$partial_text'\n";
      }
      else {
        $eval = "MISS";
      }
    }
  }
  print STDERR "   - evaluation: $eval\n";
}


=item get_range

Returns a text index range for an array of nodes
For now it ignores a possibility of non-contiguous ranges

=cut

sub get_range {
  my @nodes = @_;
  my $start = min(map {attr($_, 'start')} @nodes);
  my $end = max(map {attr($_, 'end')} @nodes);
  return "$start:$end";
}


=item get_text

Given an array of nodes, it gives their surface text

=cut

sub get_text {
  my @nodes = @_;
  my @nodes_ordered = sort {attr($a, 'ord') <=> attr($b, 'ord')} @nodes;
  my $text = join(' ', map {attr($_, 'form')} @nodes_ordered);
  return $text;
}


=item get_whole_source

For the given source node, it collects all nodes representing the whole source.

=cut

sub get_whole_source_nodes {
  my $node = shift;
  my @source_nodes = get_source_nodes($node);
  push(@source_nodes, $node);
  return @source_nodes;
}


=item get_source_nodes

It recursively adds sons whith deprel nmod, amod, flat, case (with exception of 'podle') and acl:relcl (acl:relcl with the whole subtree right away)

=cut

sub get_source_nodes {
  my $node = shift;
  
  if (attr($node, 'deprel') eq 'acl:relcl') { # rel. clause, e.g. "lidé, které Radiožurnál oslovil"
    return descendants($node);
  }
  
  my @source_sons = grep {attr($_, 'lemma') ne 'podle'}
                    grep {attr($_, 'deprel') =~ /^(nmod|amod|flat|case|acl:relcl)$/}
                    $node->getAllChildren;
  my @whole_source_nodes = @source_sons;
  foreach my $son (@source_sons) {
    push(@whole_source_nodes, get_source_nodes($son));
  }
  return @whole_source_nodes;
}


# the following function is modified from Jan Štěpánek's UD TrEd extension
sub _create_structure {
    my ($root) = @_;
    my %node_by_ord = map +(attr($_, 'ord') => $_), $root->getAllChildren;
    # print STDERR "_create_structure: \%node_by_ord:\n";
    foreach my $ord (sort {$a <=> $b} keys(%node_by_ord)) {
      # print STDERR "_create_structure:   - $ord: " . attr($node_by_ord{$ord}, 'form') . "\n";
    }
    foreach my $node ($root->getAllChildren) {
        my $head = attr($node, 'head');
        # print STDERR "_create_structure: head $head\n";
        if ($head) { # i.e., head is not 0, meaning this node should not be a child of the technical root
            my $parent = $node->getParent();
            $parent->removeChild($node);
            my $new_parent = $node_by_ord{$head};
            $new_parent->addChild($node);
        }
    }
}

# print children recursively
sub print_children {
    my ($node, $pre) = @_;
    my @children = $node->getAllChildren();
    foreach my $child (@children) {
        my $ord = attr($child, 'ord') // 'no_ord';
        my $form = attr($child, 'form') // 'no_form';
        print STDERR "$ord$pre$form\n";
        print_children($child, $pre . "\t");
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

sub descendants {
  my $node = shift;
  my @children = $node->getAllChildren;
  foreach my $child ($node->getAllChildren) {
    push (@children, descendants($child));
  }
  return @children;
}
  
sub root {
  my $node = shift;
  while ($node->getParent) {
    $node = $node->getParent;
  }
  return $node;
}


######### PARSING THE TEXT WITH UDPIPE #########

=item call_udpipe

Calling UDPipe REST API; the text to be parsed is passed in the argument
Returns the parsed output in UD CONLL format

=cut

sub call_udpipe {
    my $text = shift;

    # Nastavení URL pro volání REST::API s parametry
    my $url = 'http://lindat.mff.cuni.cz/services/udpipe/api/process?tokenizer=ranges&tagger&parser&data=' . uri_escape_utf8($text);

    # Vytvoření instance LWP::UserAgent
    my $ua = LWP::UserAgent->new;

    # Vytvoření požadavku
    my $req = HTTP::Request->new('GET', $url);
    $req->header('Content-Type' => 'application/json');

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
        print STDERR "Chyba: " . $res->status_line . "\n";
        return '';
    }
}

######### NAMED ENTITIES WITH NAMETAG #########

=item call_nametag

Calling NameTag REST API; the text to be searched is passed in the argument in UD CONLL format
Returns the text in UD CONLL-NE format.
This function just splits the input conll format to individual sentences (or a few of sentences if $max_sentences is set to a larger number than 1) and calls function call_nametag_part on this part of the input, to avoid the NameTag error caused by a too large argument.

=cut

sub call_nametag {
    my $conll = shift;
    
    my $result = '';
    
    # Let us call NameTag api for each X sentences separately, as too large input produces an error.
    my $max_sentences = 1; # 5 was too large at first attempt, so let us hope 1 is safe enough.
    
    my $conll_part = '';
    my $sent_count = 0;
    foreach my $line (split /\n/, $conll) {
      #print STDERR "Processing line $line\n";
      $conll_part .= $line . "\n";
      if ($line =~ /^\s*$/) { # empty line means end of sentence
        #print STDERR "Found an empty line.\n";
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

=item call_nametag_part

Now actuall calling NameTag REST API for a small part of the input (to avoid error caused by a long argument).
Returns the text in UD CONLL-NE format.
If an error occurs, the function just returns the input conll text unchanged.

=cut

sub call_nametag_part {
    my $conll = shift;

    # Nastavení URL pro volání REST::API s parametry
    my $url = 'http://lindat.mff.cuni.cz/services/nametag/api/recognize?input=conllu&output=conllu-ne&data=' . uri_escape_utf8($conll);

    # Vytvoření instance LWP::UserAgent
    my $ua = LWP::UserAgent->new;

    # Vytvoření požadavku
    my $req = HTTP::Request->new('GET', $url);
    $req->header('Content-Type' => 'application/json');

    # Odeslání požadavku a získání odpovědi
    my $res = $ua->request($req);

    # Zkontrolování, zda byla odpověď úspěšná
    if ($res->is_success) {
        # Získání odpovědi v JSON formátu
        my $json_response = decode_json($res->content);
        # Zpracování odpovědi
        my $result = $json_response->{result};
        # print STDERR "NameTag result:\n$result\n";
        return $result;
    } else {
        print STDERR "NameTag error: " . $res->status_line . "\n";
        return $conll; 
    }
}
