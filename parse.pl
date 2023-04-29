#!/usr/bin/perl
use strict;
use warnings;
use utf8;
use open qw(:std :utf8);
use LWP::UserAgent;
use URI::Escape;
use JSON;

my $file_name = shift @ARGV;

open my $file_handle, '<:encoding(utf8)', $file_name
  or die "Nepodařilo se otevřít soubor '$file_name' pro čtení: $!";

# Načtení obsahu souboru do proměnné
my $file_content = do { local $/; <$file_handle> };

close $file_handle;

#print STDERR $file_content;

# Parsuj file s použitím UDPipe REST API
my $conll_data = call_udpipe($file_content);

# Ulož výsledek do souboru
open(OUT, '>:encoding(utf8)', "$file_name.conll") or die "Cannot open file $file_name.conll for writing: $!";
print OUT $conll_data;
close(OUT);

use Tree::Simple;

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
if ($root) {
    _create_structure($root);
    push(@trees, $root);
    #print STDERR "End of sentence id='" . attr($root, 'id') . "'.\n\n";
    $root = undef;
    #warn "Emtpy line missing at the end of input\n";
}
# end of Jan Štěpánek's modified cycle for reading UD CONLL


foreach my $tree (@trees) {
  print STDERR "Sentence id=" . attr($tree, 'id') . ": " . attr($tree, 'text') . "\n";
  print_children($tree, "\t");
}




# the following function is modified from Jan Štěpánek's UD TrEd extension
sub _create_structure {
    my ($root) = @_;
    my %node_by_ord = map +(attr($_, 'ord') => $_), $root->getAllChildren;
    foreach my $node ($root->getAllChildren) {
        my $head = attr($node, 'head');
        print STDERR "_create_structure: head $head\n";
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

######### TREE METHODS #########

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
        # print STDERR "Výsledek: $result\n";
        return $result;
    } else {
        print STDERR "Chyba: " . $res->status_line . "\n";
        return '';
    }
}

