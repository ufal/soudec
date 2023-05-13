#!/usr/bin/perl
use strict;
use warnings;
use utf8;
use open qw(:std :utf8);
use LWP::UserAgent;
use URI::Escape;
use JSON;
use Tree::Simple;

my $MIN_RELIABILITY = 10; # minimal required phrase reliability

my ($file_name, $spolehlivost_frazi) = @ARGV;

# Let us first read the file with reliability of citation phrases

my %phrase2reliability; # reliability of the phrase in percents (in how many percents it was used in training data as a citation phrase)
my %phrase2se_si; # does the phrase require "se/si" to be a citation phrase? (maybe not needed and not yet implemented!)

open (PHRASES, '<:encoding(utf8)', $spolehlivost_frazi)
  or die "Nepodařilo se otevřít soubor '$spolehlivost_frazi' pro čtení: $!";

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
    print STDERR "Phrase $phrase ($se_si) with reliability $reliability_percent\n";
    $phrase2reliability{$phrase} = $reliability_percent;
    $phrase2se_si{$phrase} = $se_si;
  }
  else {
    print STDERR "Unknown format of a line in file $spolehlivost_frazi:\n$line\n";
  }
}


# Now let us read the text file where citations should be searched for

open my $file_handle, '<:encoding(utf8)', $file_name
  or die "Cannot open file '$file_name' for reading: $!";

# Načtení obsahu souboru do proměnné
my $file_content = do { local $/; <$file_handle> };

close $file_handle;

#print STDERR $file_content;


# Let us parse the file using UDPipe REST API

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


# Let us parse the CONLL format into Tree::Simple tree structures (one per sentence)

my @lines = split("\n", $conll_data);

my @trees = (); # array of trees in the document

my $root; # a single root

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
        
        $root->addChild($node);
        
    }
}
# If there wasn't an empty line at the end of the file, we need to process the last tree here:
if ($root) {
    _create_structure($root);
    push(@trees, $root);
    #print STDERR "End of sentence id='" . attr($root, 'id') . "'.\n\n";
    $root = undef;
    #warn "Emtpy line missing at the end of input\n";
}
# end of Jan Štěpánek's modified cycle for reading UD CONLL


# Now we have dependency trees of the sentences; let us search for citation phrases

foreach $root (@trees) {
  print STDERR "\n====================================================================\n";
  print STDERR "Sentence id=" . attr($root, 'id') . ": " . attr($root, 'text') . "\n";
  # print_children($root, "\t");
  
  my @nodes = descendants($root);
  foreach my $node (@nodes) {
    my $form_lc = lc(attr($node, 'form'));
    my $reliability = $phrase2reliability{$form_lc};
    if ($reliability) {
      print STDERR "Found phrase $form_lc with reliability $reliability\n";
      if ($reliability > $MIN_RELIABILITY) {
        print STDERR " - reliability is greater than threshold $MIN_RELIABILITY\n";
        if ($form_lc eq 'podle') { # special treatment
          my $parent = $node->getParent;
          my $source = attr($parent, 'form');
          print STDERR " - SOURCE parent: $source\n";
        }
        else {
          my @children = $node->getAllChildren;
          my @nsubj = grep {attr($_, 'deprel') eq 'nsubj'} @children;
          if (@nsubj) {
            my $subject = attr($nsubj[0], 'form');
            print STDERR " - SOURCE nsubj: $subject\n";
          }
        }
      }
    }
  }
}








# the following function is modified from Jan Štěpánek's UD TrEd extension
sub _create_structure {
    my ($root) = @_;
    my %node_by_ord = map +(attr($_, 'ord') => $_), $root->getAllChildren;
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
  my $refha_props = $node->getNodeValue($node);
  $$refha_props{$attr} = $value;
}

sub attr {
  my ($node, $attr) = @_;
  my $refha_props = $node->getNodeValue($node);
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
  

######### PARSING THE TEXT WITH UDPIPE #########

=item call_udpipe

Calling UDPipe REST API; the text to be parsed is passed in the argument
Returns the parsed output in UD CONLL format

=cut

sub call_udpipe {
    my $text = shift;

    # Nastavení URL pro volání REST::API s parametry
    my $url = 'http://lindat.mff.cuni.cz/services/udpipe/api/process?tokenizer&tagger&parser&data=' . uri_escape_utf8($text);

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
