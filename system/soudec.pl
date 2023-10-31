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
use Getopt::Long; # reading arguments
use POSIX qw(strftime); # naming a file with date and time
use File::Basename;

# STDIN and STDOUT in UTF-8
binmode STDIN, ':encoding(UTF-8)';
binmode STDOUT, ':encoding(UTF-8)';

my $VER = '1.0'; # version of the program

# a list of keywords to classify a source as anonymous
my %keywords_anonymous = ('zdroj' => 1,
                          'pozorovatel' => 1,
                          'informace' => 1,
                          'mnohý' => 1
                         );

my %keywords_anonymous_partial = ('část' => 1,
                                  'některý' => 1,
                                  'většina' => 1,
                                  'řada' => 1,
                         );

# a hasn to keep classes of already seen surnames
my %surname2class;
                         
# default minimal required phrase reliability
my $MIN_RELIABILITY_DEFAULT = 10;
# default output format
my $OUTPUT_FORMAT_DEFAULT = 'txt';
# default input format
my $INPUT_FORMAT_DEFAULT = 'txt';
# default phrase reliability file
my $PHRASE_RELIABILITY_FILE_DEFAULT = 'resources/phrases_reliability.csv';

# variables for arguments
my $input_file;
my $ann_file;
my $stdin;
my $input_format;
my $phrase_reliability_file;
my $min_phrase_reliability;
my $output_format;
my $store_conllu;
my $version;
my $help;

# getting the arguements
GetOptions(
    'i|input-file=s'  => \$input_file, # the name of the input file
    'a|ann-file=s'  => \$ann_file, # the name of the file with manual annotation
    'si|stdin'      => \$stdin, # should the input be read from STDIN?
    'if|input-format=s' => \$input_format, # input format, possible values: txt, presegmented
    'p|phrase-file=s'  => \$phrase_reliability_file, # the name of the file with a list of citation phrases and their reliability
    'r|reliability=i'  => \$min_phrase_reliability, # minimal required phrase reliability
    'of|output-format=s' => \$output_format, # output format, possible values: txt, html, conllu
    'sc|store-conllu'    => \$store_conllu, # should the result of soudec detection be logged as a conllu file?
    'v|version'    => \$version, # print the version of the program and exit
    'h|help'    => \$help, # print a short help and exit
);


my $script_path = $0;  # Získá název spuštěného skriptu s cestou
my $script_dir = dirname($script_path);  # Získá pouze adresář ze získané cesty


if ($version) {
  print "SouDeC version $VER.\n";
  exit 0;
}

if ($help) {
  print "SouDeC version $VER.\n";
  my $text = <<'END_TEXT';
Usage: soudec.pl [options]
options:  -i|--input-file [input text file name]
          -a|--ann-file [manual annotation file name]
         -si|--stdin (input text provided via stdin)
         -if|--input-format [input format: txt (default) or presegmented]
          -p|--phrase-file [phrases reliability file name]
          -r|--reliability [minimal required phrase reliability]
         -of|--output-format [output format: txt (default), html, conllu]
         -sc|--store-conllu (log the output of UDPipe parser, NameTag and SouDeC to a CONLL-U file)
          -v|--version (prints the version of the program and ends)
          -h|--help (prints a short help and ends)
END_TEXT
  print $text;
  exit 0;
}

###################################################################################
# Summarize the program arguments to the log (except for --version and --help)
###################################################################################

print STDERR "\n####################################################################\n";

print STDERR "Arguments:\n";

if ($stdin) {
  print STDERR " - input: STDIN\n";
}
elsif ($input_file) {
  print STDERR " - input: file $input_file\n";
}

if (!defined $input_format) {
  print STDERR " - input format: not specified, set to default $INPUT_FORMAT_DEFAULT\n";
  $input_format = $INPUT_FORMAT_DEFAULT;
}
elsif ($input_format !~ /^(txt|presegmented)$/) {
  print STDERR " - input format: unknown ($input_format), set to default $INPUT_FORMAT_DEFAULT\n";
  $input_format = $INPUT_FORMAT_DEFAULT;
}
else {
  print STDERR " - input format: $input_format\n";
}

if ($ann_file) {
  print STDERR " - file with manual annotation: $ann_file\n";  
}

if (!defined $phrase_reliability_file) {
  print STDERR " - phrase reliability file: not specified, set to default $PHRASE_RELIABILITY_FILE_DEFAULT\n";
  $phrase_reliability_file = "$script_dir/$PHRASE_RELIABILITY_FILE_DEFAULT";
}
else {
  print STDERR " - phrase reliability file: $phrase_reliability_file\n";
}

if (!defined $min_phrase_reliability) {
  print STDERR " - min. phrase reliability: not specified, set to default $MIN_RELIABILITY_DEFAULT\n";
  $min_phrase_reliability = $MIN_RELIABILITY_DEFAULT;
}
else {
  print STDERR " - min. phrase reliability: $min_phrase_reliability\n";
}

$output_format = lc($output_format) if $output_format;
if (!defined $output_format) {
  print STDERR " - output format: not specified, set to default $OUTPUT_FORMAT_DEFAULT\n";
  $output_format = $OUTPUT_FORMAT_DEFAULT;
}
elsif ($output_format !~ /^(txt|html|conllu)$/) {
  print STDERR " - output format: unknown ($output_format), set to default $OUTPUT_FORMAT_DEFAULT\n";
  $output_format = $OUTPUT_FORMAT_DEFAULT;
}
else {
  print STDERR " - output format: $output_format\n";
}

if ($store_conllu) {
  print STDERR " - log output in a conllu file; includes output of udpipe and nametag)\n";
}


print STDERR "\n";

###################################################################################
# Let us first read the file with reliability of citation phrases
###################################################################################

my %phrase_lemma_constraint2reliability; # reliability of the phrase lemmas together with a constraint in percents (in how many percents it was used in training data as a citation phrase); the phrase lemma is separated by '_' from the constraint
my %phrase_lemma2constraints; # which constraints does the phrase require (if any); the individual constraints are separated by '_'; an empty constraint is represented by 'NoConstraint'

print STDERR "Reading phrase lemmas and their reliability from $phrase_reliability_file\n";

open (PHRASES, '<:encoding(utf8)', $phrase_reliability_file)
  or die "Could not open file '$phrase_reliability_file' for reading: $!";

my $phrases_count = 0;
while (<PHRASES>) {
  chomp(); 
  my $line = $_;
  if ($line =~ /^(\d+)\t(\d+)\t(\S+)\t(\S*)$/) {
    my $all_occurrences = $1;
    my $used_as_citation_phrase = $2;
    my $lemma = $3;
    my $constraint = $4 || 'NoConstraint';
    my $reliability = $used_as_citation_phrase / $all_occurrences;
    my $reliability_percent = 100 * sprintf("%.2f", $reliability);
    $phrase_lemma_constraint2reliability{$lemma . '_' . $constraint} = $reliability_percent;
    print STDERR "Phrase $lemma (with constraint $constraint) and reliability $reliability_percent\n";
    $phrases_count++;
    if ($phrase_lemma2constraints{$lemma}) { # if there already was a constraint for this lemma
      print STDERR "Note: multiple constraints for lemma $lemma.\n";
      $phrase_lemma2constraints{$lemma} .= "_";
    }
    $phrase_lemma2constraints{$lemma} .= $constraint;
  }
  else {
    print STDERR "Unknown format of a line in file $phrase_reliability_file:\n$line\n";
  }
}
print STDERR "$phrases_count phrase lemmas (plus a constraint) have been read from file $phrase_reliability_file:\n";


###################################################################################
# If an .ann file with manual annotation is provided for measuring the success rate,
# read the file now
# e.g.
# T16	anonymous-partial 1360 1365	vědců
# T23	PHRASE 1354 1359	podle
#
# Discontinuous indexes are possible, e.g.:
# "Vědci si donedávna mysleli" -> "si mysleli":
# T2	PHRASE 7 9;20 27	si mysleli
###################################################################################

# hashes to keep info about manual annotation
my %h_ann_phrase_range2text; # '1354:1359' => 'podle' or '7:9;20:27' => 'si mysleli'
my %h_ann_source_range2text; # '1360:1365' => 'vědců'
my %h_ann_source_range2type; # '1360:1365' => 'anonymous-partial'

=item possible values for source type

        anonymous
        anonymous-partial
        unofficial
        official-political
        official-non-political
        
=cut

# similar hashes to later collect info about automatic recognition, to be compared with manual
my %h_phrase_range2text;
my %h_source_range2text;
my %h_source_range2type;


if ($ann_file) {
  print STDERR "Reading manual annotation from $ann_file\n";

  open my $ann_handle, '<:encoding(utf8)', $ann_file
    or die "Cannot open file '$ann_file' for reading: $!";

  while(my $line = <$ann_handle>) {
    if ($line =~ /^\S+\t(\S+)\ ([\d; ]+)\t(.+)$/) {
      my ($event, $range, $text) = ($1, $2, $3);
      $range =~ s/\ /:/g;
      if ($event =~ /PHRASE/) {
        $h_ann_phrase_range2text{$range} = $text;
      }
      else {
        $h_ann_source_range2text{$range} = $text;
        $h_ann_source_range2type{$range} = $event;        
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

my $input_content;

if ($stdin) { # the input text should be read from STDIN
  $input_content = '';
  while (<>) {
    $input_content .= $_;
  }
  my $current_datetime = strftime("%Y%m%d_%H%M%S", localtime);
  $input_file = "stdin_$current_datetime.txt"; # a fake file name for naming the output files

} elsif ($input_file) { # the input text should be read from a file
  open my $file_handle, '<:encoding(utf8)', $input_file
    or die "Cannot open file '$input_file' for reading: $!";

  $input_content = do { local $/; <$file_handle> }; # reading the file into a variable
  close $file_handle;

} else {
  print STDERR "No input to process! Exiting!\n";
  exit -1;
}

#print STDERR $input_content;


###################################################################################
# Let us parse the file using UDPipe REST API
###################################################################################

my $conll_data = call_udpipe($input_content);

# Store the result to a file (just to have it, not needed for further processing)
#  open(OUT, '>:encoding(utf8)', "$input_file.conll") or die "Cannot open file '$input_file.conll' for writing: $!";
#  print OUT $conll_data;
#  close(OUT);

###################################################################################
# Now let us add info about named entities using NameTag REST API
###################################################################################

my $conll_data_ne = call_nametag($conll_data);

# Store the result to a file (just to have it, not needed for further processing)
#  open(OUT, '>:encoding(utf8)', "$input_file.conllne") or die "Cannot open file '$input_file.conllne' for writing: $!";
#  print OUT $conll_data_ne;
#  close(OUT);



###################################################################################
# Let us parse the CONLL format into Tree::Simple tree structures (one tree per sentence)
###################################################################################

my @lines = split("\n", $conll_data_ne);

my @trees = (); # array of trees in the document

my $root; # a single root

my $min_start = 10000; # from indexes of the tokens, we will get indexes of the sentence
my $max_end = 0;

my $multiword = ''; # store a multiword line to keep with the following token

# the following cycle for reading UD CONLL is modified from Jan Štěpánek's UD TrEd extension
foreach my $line (@lines) {
    chomp($line);
    #print STDERR "Line: $line\n";
    if ($line =~ /^#/ && !$root) {
        $root = Tree::Simple->new({}, Tree::Simple->ROOT);
        #print STDERR "Beginning of a new sentence!\n";
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



###################################################################################
# Now we have dependency trees of the sentences; let us search for citation phrases
###################################################################################

print_log_header();

foreach $root (@trees) {
  print STDERR "\n====================================================================\n";
  print STDERR "Sentence id=" . attr($root, 'id') . ": " . attr($root, 'text') . "\n";
  print_children($root, "\t");
  
  my @nodes = descendants($root);
  foreach my $node (@nodes) {
    my $lemma = attr($node, 'lemma');
    my $constraints = $phrase_lemma2constraints{$lemma};
    if (!$constraints) {
      print STDERR "No constraints for lemma '$lemma', skipping.\n";
      next; # the lemma is not among citation phrases
    }
    foreach my $constraint (split(/_/, $constraints)) { # split the constraints by separator '_' and work with one constraint at a time
      my $reliability = $phrase_lemma_constraint2reliability{$lemma . '_' . $constraint} // 0;
      print STDERR "Testing phrase lemma (constraint) '$lemma ($constraint)' with reliability $reliability\n";

      my ($claim_parent, @phrase_nodes) = check_constraint($node, $lemma, $constraint); # check if the constraint is met (e.g., se/si is present) and return the expected parent of the claim and all nodes belonging to the phrase; empty constraint is represented by 'NoConstraint'
      if (!$claim_parent) {
        print STDERR "- the constraint '$constraint' for lemma '$lemma' is not met.\n";
        next;
      }
      if ($reliability >= $min_phrase_reliability) {
        print STDERR " - reliability of lemma '$lemma' with constraint '$constraint' is greater than threshold $min_phrase_reliability\n";
        # Checking if there is something like a claim, i.e. a finite-verb core object 
        if (has_finite_verb_object($claim_parent)) {
          evaluate_single_event('phrase', $lemma, $constraint, $root, @phrase_nodes);
          if ($constraint eq 'PREP') { # special treatment of 'podle' and 'dle'
            my $parent = $node->getParent;
            my $source = attr($parent, 'form');
            my @whole_source_nodes = get_whole_source_nodes($parent);
            my $whole_source = get_text(@whole_source_nodes);
            print STDERR " - SOURCE parent: $source\n - WHOLE SOURCE: $whole_source\n";
            my $source_type = guess_source_type($root, $node, @whole_source_nodes);
            print STDERR "   - SOURCE TYPE: $source_type\n";
            evaluate_single_event($source_type, $lemma, 'N/A', $root, @whole_source_nodes);
          }
          else {
            my @nsubj = grep {attr($_, 'deprel') eq 'nsubj'} $node->getAllChildren; # looking for a subject (i.e, the source)
            if (@nsubj) {
              my $subject = attr($nsubj[0], 'form');
              my @whole_source_nodes = get_whole_source_nodes($nsubj[0]);
              my $whole_source = get_text(@whole_source_nodes);
              print STDERR " - SOURCE nsubj: $subject\n - WHOLE SOURCE: $whole_source\n";
              my $source_type = guess_source_type($root, $node, @whole_source_nodes);
              print STDERR "   - SOURCE TYPE: $source_type\n";
              evaluate_single_event($source_type, $lemma, 'N/A', $root, @whole_source_nodes);
            }
          }
        }
        else {
          print STDERR "   - no finite-verb core object found!\n";
        }
      }
    }
  }
  
  evaluate_false_negatives($root);
  
}

print_log_tail();

# print the input text with marked sources in the selected output format to STDOUT
my $output = get_output($output_format); 
print $output;

if ($store_conllu) { # log the input text with marked sources in the conllu format in a file
  $output = get_output('conllu') if $output_format ne 'conllu';
  my $file_name = basename($input_file); # the file name without the path
  open(OUT, '>:encoding(utf8)', "$script_dir/log/$file_name.conllu") or die "Cannot open file '$script_dir/log/$file_name.conllu' for writing: $!";
  print OUT $output;
  close(OUT);
}

################################################################
########################## FINISHED ############################
################################################################


=item check_constraint

Check if the constraint is met at the node.

The constraint can have one of the following formats:
- a single word form - it must be a child of the given node (e.g., 'si' in 'myslí si')
- a set of word forms (or pairs of word forms, see just below) separated by '|' - all these word forms must be children of the given node (e.g., 'se|slyšet' in 'nechal se slyšet')
- a pair of word forms separated by '-' - the first word form must be a child and the second one its child (e.g. 'za-to' in 'má za to')
- PREP - the node must be a preposition ('podle', 'dle')
- POSTPOS - the attribution phrase is in post position, e.g. "To tak není, pousmál se Honza". It means that "pousmál" with deprel "conj" is a son of "není"; can be combined with other required word forms (separated by '|'), e.g. 'se|POSTPOS' in "pousmál se"
- ANTEPOS - the attribution phrase is in ante position, e.g. "Co jsem slyšel, tak lístků je dost". It means that "slyšel" with deprel "csubj" (or "csubj:pass") is a son of "prodalo"; can be combined with other required word forms (separated by '|'), e.g. 'co|jsem|ANTEPOS' in "co jsem slyšel"

Any (presumably only one) word form in the formats above may be followed by '!' - it is the expected parent of the claim in the tree (e.g. 'hovořit' in 'začal hovořit'); it should not happen for PREP or if POSTPOS/ANTEPOS is a part of the constraint 

Also checks if the given phrase node is morphologically acceptable - i.e.:
 - not an infinitive (unless PREP)
 - not negative

Returns undef if the constraints are not met.
Otherwise returns the expected parent of the claim and all nodes belonging to the phrase.

=cut


sub check_constraint {
  my ($node, $lemma, $constraint) = @_;

  print STDERR "check_constraint: checking constraint '$constraint'\n";

  my $claim_parent;
  my @phrase_nodes = ($node);

  my $deprel = attr($node, 'deprel') // '';
  
  my $xpostag = attr($node, 'xpostag') // '';
  if ($constraint and $constraint eq 'PREP' and $xpostag =~ /^R/) {
    print STDERR " - PREP, constraint OK\n";
    return ($node, @phrase_nodes);
  }
 
  # check morphological properties of the node:
  my $feats = attr($node, 'feats') // '';
  print STDERR "check_constraint: checking morphology: feats='$feats'\n";
  if ($feats =~ /\bVerbForm=Inf\b/) { # We do not want infinitive
    print STDERR " - we do not want infinitive, returning undef\n";
    return undef;
  }
  print STDERR " - morphology OK\n";
  #return undef if $feats =~ /\bPolarity=Neg\b/; # We do not want negation

  if ($constraint eq 'NoConstraint') { # no constraint, i.e. trivially matched
    print STDERR " - no constraint, i.e. trivially matched\n";
    return ($node, @phrase_nodes);
  }

  # now check the constraints:
  my @children = $node->getAllChildren;
  my @required_children_forms_lc = split('\|', $constraint); # get the individul required children (possibly with '!')
  foreach my $required_child_form_lc (@required_children_forms_lc) {
    print STDERR " - checking if '$required_child_form_lc' is present/fulfilled\n";
    if ($required_child_form_lc eq 'POSTPOS') { # the attribution is in post position, i.e. the claim is the parent (i.e. a child of the grandparent)
      if ($deprel ne 'conj') {
        print STDERR " - constraint POSTPOS but deprel is not 'conj'; returning undef\n";
        return undef;
      }
      # check the order
      my $phrase_ord = attr($node, 'ord');
      my $parent_ord = attr($node->getParent, 'ord');
      if ($phrase_ord < $parent_ord) {
        print STDERR " - constraint POSTPOS but parent is to the right; returning undef\n";
        return undef;
      }
      print STDERR " - constraint POSTPOS, setting the grandparent as the parent of claim\n";
      $claim_parent = $node->getParent->getParent;
    }
    elsif ($required_child_form_lc eq 'ANTEPOS') { # the attribution is in ante position, i.e. the claim is the parent (i.e. a child of the grandparent)
      if ($deprel ne 'csubj' and $deprel ne 'csubj:pass') {
        print STDERR " - constraint ANTEPOS but deprel is not 'csubj' or 'csubj:pass'; returning undef\n";
        return undef;
      }
      # check the order
      my $phrase_ord = attr($node, 'ord');
      my $parent_ord = attr($node->getParent, 'ord');
      if ($phrase_ord > $parent_ord) {
        print STDERR " - constraint ANTEPOS but parent is to the left; returning undef\n";
        return undef;
      }
      print STDERR " - constraint ANTEPOS, setting the grandparent as the parent of claim\n";
      $claim_parent = $node->getParent->getParent;
    }
    elsif ($required_child_form_lc =~ /^(\S+)-(\S+)$/) { # a hierarchy required (e.g. 'za-to' in 'má za to')
      my ($child_form_lc, $grandchild_form_lc) = ($1, $2);
      my $required_child_is_claim_parent = $child_form_lc =~ /!/;
      $child_form_lc =~ s/!//;      
      my @good_children = grep {$child_form_lc eq lc(attr($_, 'form'))} @children;
      if (!@good_children) {
        print STDERR " - constraint not matched (no good children), returning undef\n";
        return undef;
      }
      my $good_child = $good_children[0]; # I doubt there might be more
      push(@phrase_nodes, $good_child);
      if ($required_child_is_claim_parent) { # it is also the expected parent of the claim
        $claim_parent = $good_child if !$claim_parent;
      }      
      my $required_grandchild_is_claim_parent = $grandchild_form_lc =~ /!/;
      $grandchild_form_lc =~ s/!//;      
      my @good_grandchildren = grep {$grandchild_form_lc eq lc(attr($_, 'form'))} $good_child->getAllChildren;
      if (!@good_grandchildren) {
        print STDERR " - constraint not matched (no good grandchildren), returning undef\n";
        return undef;
      }
      my $good_grandchild = $good_grandchildren[0]; # I doubt there might be more
      push(@phrase_nodes, $good_grandchild);
      if ($required_grandchild_is_claim_parent) { # it is also the expected parent of the claim
        $claim_parent = $good_grandchild if !$claim_parent;
      }      
    }
    else { # only words from among the children are required
      my $required_child_is_claim_parent = $required_child_form_lc =~ /!/;
      $required_child_form_lc =~ s/!//;
      my @good_children = grep {$required_child_form_lc eq lc(attr($_, 'form'))} @children;
      if (!@good_children) {
        print STDERR " - constraint not matched (no good children), returning undef\n";
        return undef;
      }
      my $good_child = $good_children[0]; # I doubt there might be more
      push(@phrase_nodes, $good_child);
      if ($required_child_is_claim_parent) { # it is also the expected parent of the claim
        $claim_parent = $good_child if !$claim_parent;
      }
    }
  }
  print STDERR " - OK, constraint matched.\n";
  if (!$claim_parent) { # no special claim parent was set
    $claim_parent = $node;
  }
  return ($claim_parent, @phrase_nodes);
}


=item is_finite

Checks if the given node represents a finite verb

=cut

sub is_finite {
  my $node = shift;
  my $VerbForm = get_feat_value($node, 'VerbForm') // '';
  # print STDERR "is_finite: VerbForm = '$VerbForm'\n";
  if ($VerbForm and $VerbForm ne 'Inf') {
    return 1;
  }
  # It may also be a copula ("je konzervativní")
  my @cop_children = grep {attr($_, 'deprel') eq 'cop'} $node->getAllChildren;
  if (@cop_children) {
    if (is_finite($cop_children[0])) {
      return 1;
    }
  }
  # It may be a complex verb ("bude potřebovat")
  my @finverb_children = grep {get_feat_value($_, 'VerbForm') and get_feat_value($_, 'VerbForm') ne 'Inf'} $node->getAllChildren;
  if ($VerbForm and @finverb_children) {
    if (is_finite($finverb_children[0])) {
      return 1;
    }
  }  
  # It may be a reference to a verbal phrase, such as "potvrzuje to i ..." or "jeho slova potvrzuje i ..."
  my $form = attr($node, 'form');
  if ($form =~ /^(slova|to|tom)$/) {
    return 1;
  }
  return 0;
}



=item has_finite_verb_object

Checks if the given node has something like a core finite-verb argument

=cut

sub has_finite_verb_object {
  my $node = shift;
  my $form_lc = lc(attr($node, 'form') // '');
  my $lemma = attr($node, 'lemma') // '';
  my $parent = $node->getParent;

  # First, let us solve 'podle'
  # 'podle' needs to have a grandparent (finite-verb of the claim)
  # The parent of 'podle' (the source) should not be the last child of the grandparent (to avoid constructions such ad "udělal jsem to podle příručky");
  # (Condition "the parent needs to be left from the grandparent" would be too strong, see: "Tak jste podle nich jedni z mála.")
  if ($form_lc =~ /^(podle|dle)$/) {
    my $grandparent = $parent->getParent;
    return 0 if !$grandparent;
#    return 0 if !is_finite($grandparent);
    my $parent_ord = attr($parent, 'ord');
    my @parent_right_brothers = grep {attr($_, 'ord') > $parent_ord} $grandparent->getAllChildren;
    if (@parent_right_brothers) {
      print STDERR " - has_finite_verb_object: case 'podle' OK (a claim found)\n";
      return 1;
    }
    print STDERR " - has_finite_verb_object: case 'podle' - no claim found\n";
    return 0;
  }
  # Second, let us search for a claim among the children
  my @finite_verb_object_children = grep {attr($_, 'deprel') =~ /^(obj|iobj|ccomp|xcomp|obl:arg|acl|root|csubj:pass)$/}
                                    grep {is_finite($_)}
                                    $node->getAllChildren;
  if (@finite_verb_object_children) {
    print STDERR " - has_finite_verb_object: OK (a claim found among children: " . attr($finite_verb_object_children[0], 'form') . ")\n";
    return 1;
  }
  # Third, the claim might also be in a parataxis position ("Jak už vědci uvedli při prvním kole vykopávek, jde pro ně o záhadu.")
  if (attr($node, 'deprel') and attr($node, 'deprel') eq 'parataxis') {
    if (is_finite($parent)) {
      print STDERR " - has_finite_verb_object: OK (a claim found in a parataxis position): " . attr($parent, 'form') . ")\n";
      return 1;
    }
  }
  # Fourth, "informovat o (cokoli)" or "přinesl zprávu o (cokoli), e.g. "O rozsudku informoval ..." or "Zprávu o zmizení XY přinesl ..."
  if ($lemma eq 'informovat' or $lemma eq 'zpráva') {
    my @children_with_o = grep {has_child_with_lemma($_, 'o')}
                          $node->getAllChildren;
    if (@children_with_o) {
      print STDERR " - has_finite_verb_object: case 'o' OK (a claim found)\n";
      return 1;
    }    
  }
  # Fifth, "Čest jeho památce!, uvedl městys na facebooku k úmrtí"
  my @children_with_excl = grep {has_child_with_lemma($_, '!')}
                           $node->getAllChildren;
  if (@children_with_excl) {
    print STDERR " - has_finite_verb_object: case '!' OK (a claim found)\n";
    return 1;
  }    
  
  # Je potřeba vyřešit "Vyplývá to z údajů na internetových stránkách České národní banky.", kde claim je subject ("to") a source je obl:arg (z údajů), soubor doc-8359658.xml.txt.conll
  
  print STDERR " - has_finite_verb_object: no claim found\n";
  return 0;
}


=item has_child_with_lemma

Checks if a lemma is among children

=cut

sub has_child_with_lemma {
  my ($node, $lemma) = @_;
  if (grep {attr($_, 'lemma') eq $lemma} $node->getAllChildren) {
    return 1;
  }
  return 0;
}


=item guess_source_type

Guesses and returns the type of the source, i.e. one of these values:

        anonymous
        anonymous-partial
        unofficial
        official-political
        official-non-political

Uses global hash %surname2class to keep track of surnames that have already been classified (possibly as a part of a longer source, e.g. "mluvčí cestovní kanceláře Jiří Nekvapil"), so that they are not misclassified later when mentioned just by themselves (e.g., just "Nekvapil")

NameTag offers these values:

NE containers

P - complex person names
T - complex time expressions
A - complex address expressions
C - complex bibliographic expressions

Types of NE

a - Numbers in addresses
ah - street numbers
at - phone/fax numbers
az - zip codes

g - Geographical names
gc - states
gh - hydronyms
gl - nature areas / objects
gq - urban parts
gr - territorial names
gs - streets, squares
gt - continents
gu - cities/towns
g_ - underspecified

i - Institutions
ia - conferences/contests
ic - cult./educ./scient. inst.
if - companies, concerns...
io - government/political inst.
i_ - underspecified

m - Media names
me - email address
mi - internet links
mn - periodical
ms - radio and TV stations

n - Number expressions
na - age
nb - vol./page/chap./sec./fig. numbers
nc - cardinal numbers
ni - itemizer
no - ordinal numbers
ns - sport score
n_ - underspecified

o - Artifact names
oa - cultural artifacts (books, movies)
oe - measure units
om - currency units
op - products
or - directives, norms
o_ - underspecified

p - Personal names
pc - inhabitant names
pd - (academic) titles
pf - first names
pm - second names
pp - relig./myth persons
ps - surnames
p_ - underspecified

t - Time expressions
td - days
tf - feasts
th - hours
tm - months
ty - years

=cut

sub guess_source_type {
  my ($root, $phrase_node, @whole_source_nodes) = @_;

  my $surname = undef; # We will set this if there is a surname found among the source nodes
  my @source_named_entity_classes = ();
  foreach my $source_node (@whole_source_nodes) {
    my $named_entity_class = get_misc_value($source_node, 'NE');
    if (!$named_entity_class) {
      $named_entity_class = get_extra_NE($source_node);
    }
    next if !$named_entity_class;
    $named_entity_class =~ s/[^a-z]*([a-z][a-z_])_.*/$1/;
    # print STDERR "guess_source_type: " . attr($source_node, 'lemma') . ": '$named_entity_class'\n";
    if ($named_entity_class eq 'ps') { # a surname - check if we already know the class
      my $lemma = attr($source_node, 'lemma') // '';
      my $class = $surname2class{lc($lemma)};
      if ($class) {
        print STDERR "Class for surname $lemma already determined before: $class\n";
        return $class;
      }
      else { # first mention of the surname - let us keep it and later store it in %surname2class
        $surname = $lemma;
      }
    }
    push(@source_named_entity_classes, $named_entity_class);
  }
  
  my $joined = '~' . join('~', @source_named_entity_classes);
  
  my $type = 'anonymous-partial'; # default

  # print STDERR "guess_source_type: $joined\n";
  
  if ($joined =~ /~sp/) { # sp - source anonymous-partial (fake NE class)
    $type = 'anonymous-partial';
  }
  elsif ($joined =~ /~io/) { # io - government/political inst.
    $type = 'official-political';
  }
  elsif ($joined =~ /~i/) { # i - Institutions
    $type = 'official-non-political';
  }
  elsif ($joined =~ /~p/) { # p - Personal names
    $type = 'unofficial';
  }
  elsif ($joined =~ /~m[ns]/) { # mn - periodical, ms - radio and TV stations
    $type = 'unofficial';
  }
  elsif ($joined =~ /~sa/) { # sa - source anonymous (fake NE class)
    $type = 'anonymous';
  }

  if ($surname) {
    $surname2class{lc($surname)} = $type;
  }
  # print STDERR "guess_source_type: $type\n";
  #return "$joined:$type";
  return "$type";
}


=item get_extra_NE

Returns a fake NE value for some obvious words, such as 'mluvčí', 'premiér' etc.
Also gives fake NE value for significantly anonymous words (zdroj, pozorovatel, informace).

=cut

sub get_extra_NE {
  my $node = shift;
  my $lemma = attr($node, 'lemma');
  my @children = $node->getAllChildren;
  my @children_lemmas = map {attr($_, 'lemma')} @children;
  if ($lemma eq 'mluvčí') {
    # print STDERR "get_extra_NE: found 'mluvčí'\n";
    return 'im'; # "institution - mluvčí"
  }
  if ($keywords_anonymous{$lemma}) {
    return 'sa' # "source - anonymous"
  }
  if ($keywords_anonymous_partial{$lemma}) {
    return 'sp' # "source - anonymous-partial"
  }
  if ($lemma eq 'premiér') {
    return 'io'; # "institution - goverment, political"
  }
  if ($lemma eq 'poslanec') {
    return 'io'; # "institution - goverment, political"
  }
  if ($lemma eq 'senátor') {
    return 'io'; # "institution - goverment, political"
  }
  if ($lemma eq 'magistrát') {
    return 'io'; # "institution - goverment, political"
  }
  if ($lemma eq 'předseda') {
    if (grep {'ministerský'} @children_lemmas or grep {'vláda'} @children_lemmas) {
      return 'io'; # "institution - goverment, political"
    }
  }
  
}



=item get_misc_value

Returns a value of the given property from the misc attribute. Or undef.

=cut

sub get_misc_value {
  my ($node, $property) = @_;
  my $misc = attr($node, 'misc') // '';
  # print STDERR "get_misc_value: misc=$misc\n";
  if ($misc =~ /$property=([^|]+)/) {
    my $value = $1;
    # print STDERR "get_misc_value: $property=$value\n";
    return $value;
  }
  return undef;
}  



=item get_feat_value

Returns a value of the given property from the feats attribute. Or undef.

=cut

sub get_feat_value {
  my ($node, $property) = @_;
  my $feats = attr($node, 'feats') // '';
  # print STDERR "get_feat_value: feats=$feats\n";
  if ($feats =~ /$property=([^|]+)/) {
    my $value = $1;
    # print STDERR "get_feat_value: $property=$value\n";
    return $value;
  }
  return undef;
}  


=item get_output

Returns the input text with marked sources in the given format (one of: txt, html, conllu).

=cut

sub get_output {
  my $format = shift;
  my $output = '';

  # FILE HEADER
  
  if ($format eq 'html') {
    $output .= "<html>\n";
    $output .= "<body>\n";
  }
  
  my $first_par = 1; # for paragraph separation in txt and html formats (first par in the file should not be separated)

  my $first_sent = 1; # for sentence separation in txt and html formats (first sentence in the file should not be separated)

  # for conllu:
  my $SD_phrase_count = 0; # counting citation phrases
  my $SD_source_count = 0; # counting citation sources
  my $SD_count; # for keeping the number of the current event
  my $inside_SD = 0; # for dealing with multi-token events
  my $end_of_SD = 0; # dtto
  my $SD_type = ''; # type of the event - P for phrases, S for sources
  my $SD_subtype = ''; # source type
  
  foreach $root (@trees) {
  
    # PARAGRAPH SEPARATION (txt, html)
    if (attr($root, 'newpar') and $format =~ /^(txt|html)$/) {
      $first_sent = 1;
      if ($first_par) {
        $first_par = 0;
      }
      else {
        $output .= $format eq 'html' ? "\n</p>\n" : "\n\n";
      }
      $output .= "<p>\n" if $format eq 'html';
    }
    
    # SENTENCE HEADER (conllu)
    if ($format eq 'conllu') {
      $output .= attr($root, 'other_comment') // '';
      my $newdoc = attr($root, 'newdoc') // '';
      $output .= "$newdoc\n" if $newdoc;
      my $newpar = attr($root, 'newpar') // '';
      $output .= "$newpar\n" if $newpar;
      my $sent_id = attr($root, 'id') // '';
      $output .= "# sent_id = $sent_id\n" if $sent_id;
      my $text = attr($root, 'text') // '';
      $output .= "# text = $text\n" if $text;
    }

    # sentence separation in txt and html formats
    if ($format =~ /^(txt|html)$/) {
      if ($first_sent) {
        $first_sent = 0;
      }
      else {
        if ($input_format eq 'presegmented') { # each sentence should go to its own line
          $output .= "\n";
          if ($format eq 'html') {
            $output .= '<br>';
          }
        }
        else {
          $output .= ' ';
        }
      }
    }

    # PRINT THE SENTENCE TOKEN BY TOKEN
    my @nodes = sort {attr($a, 'ord') <=> attr($b, 'ord')} descendants($root);
    my $space_before = '';

    foreach my $node (@nodes) {
    
      # COLLECT INFO ABOUT THE TOKEN
      my $form = attr($node, 'form');
      my $start = attr($node, 'start');
      my $end = attr($node, 'end');
      
      my $span_start = '';
      my $span_end = '';
      my $type_span = '';

      my $source_range = partial_match("$start:$end", \%h_source_range2text) // ''; # is this token a part of a source?
      if ($source_range) {
        if ($source_range =~ /^$start:/) { # first token in this source
          $SD_source_count++;
          $SD_count = $SD_source_count;
        }
        if ($source_range =~ /\b$start:/) { # first token in one of contiguous parts of the source
          $span_start = $format eq 'html' ? '<span style="font-weight: bold; text-decoration: underline; color: darkgreen">' : '>>';
          $inside_SD = 1;
          $SD_type = 'S';        
          my $source_type = $h_source_range2type{$source_range};
          if ($source_type) {
            $SD_subtype = 'a' if $source_type =~ /anonymous/;
            $SD_subtype = 'ap' if $source_type =~ /anonymous-partial/;
            $SD_subtype = 'u' if $source_type =~ /unofficial/;
            $SD_subtype = 'op' if $source_type =~ /official-political/;
            $SD_subtype = 'onp' if $source_type =~ /official-non-political/;
          }
        }
        if ($source_range =~ /:$end\b/) { # last token in one of contiguous parts of the source
          $span_end = $format eq 'html' ? '</span>' : '<<';
          $end_of_SD = 1;
        }
        if ($source_range =~ /:$end$/) { # last token of the source
          my $source_type = $h_source_range2type{$source_range};
          if ($source_type) {
            $type_span = $format eq 'html' ? "<span style=\"vertical-align: sub; color: darkblue\">[$source_type]</span>" : "[$source_type]";
          }
        }
      }
      
      else { # it is not a part of a source, maybe it is a part of a phrase?
        my $phrase_range = partial_match("$start:$end", \%h_phrase_range2text) // ''; # is this token a part of a citation phrase?
        if ($phrase_range =~ /^$start:/) { # first token in this phrase
          $SD_phrase_count++;
          $SD_count = $SD_phrase_count;
        }
        if ($phrase_range =~ /\b$start:/) { # first token in one of contiguous parts of the phrase
          $span_start = $format eq 'html' ? '<span style="font-weight: bold; color: darkred">' : '@';
          $inside_SD = 1;
          $SD_type = 'P';        
        }
        if ($phrase_range =~ /:$end\b/) { # last token in one of contiguous parts of the phrase
          $span_end = $format eq 'html' ? '</span>' : '@';
          $end_of_SD = 1;
        }
      }
      
      # PRINT THE TOKEN
      if ($format =~ /^(txt|html)$/) {
        my $SpaceAfter = get_misc_value($node, 'SpaceAfter') // '';
        $output .= "$space_before$span_start$form$span_end$type_span";
        $space_before = $SpaceAfter eq 'No' ? '' : ' '; # this way there will not be space after the last token of the sentence
      }
      elsif ($format eq 'conllu') {
        my $ord = attr($node, 'ord') // '_';
        my $lemma = attr($node, 'lemma') // '_';
        my $deprel = attr($node, 'deprel') // '_';
        my $upostag = attr($node, 'upostag') // '_';
        my $xpostag = attr($node, 'xpostag') // '_';
        my $feats = attr($node, 'feats') // '_';
        my $deps = attr($node, 'deps') // '_';
        my $misc = attr($node, 'misc') // '_';
        
        if ($inside_SD) { # add info to $misc about detected events
          my $event = 'SD=' . $SD_type . '_' . $SD_count;
          $event .= '_' . $SD_subtype if ($SD_subtype);
          
          if ($misc eq '_') {
            $misc = $event;
          }
          else {
            my @miscs = split('\|', $misc);
            push(@miscs, $event);
            my @miscs_sorted = sort {$a cmp $b} @miscs;
            $misc = join('|', @miscs_sorted);
          }
          
          if ($end_of_SD) {
            $inside_SD = 0;
            $end_of_SD = 0;
            $SD_type = '';
            $SD_subtype = '';
          }
        }
        
        my $head = attr($node, 'head') // '_';
        
        my $multiword = attr($node, 'multiword') // '';
        if ($multiword) {
          $output .= "$multiword\n";
        }
        
        $output .= "$ord\t$form\t$lemma\t$upostag\t$xpostag\t$feats\t$head\t$deprel\t$deps\t$misc\n";
      }
    }

    # sentence separation in the conllu format needs to be here (also the last sentence should be ended with \n)
    if ($format eq 'conllu') {
      $output .= "\n"; # an empty line ends a sentence in the conllu format    
    }
    
  }

  if ($format eq 'html') {
    $output .= "\n</p>\n";
    $output .= "</body>\n";
    $output .= "</html>\n";
  }

  return $output;
  
} # get_output


=item print_log_header

Prints header info for the document (name of the file, start of the html table)

=cut

sub print_log_header {
  print STDERR "<!-- HTML-EVALUATION-EXACT --><h3>$input_file</h3>\n";
  print STDERR "<!-- HTML-EVALUATION-PARTIAL --><h3>$input_file</h3>\n";
  if ($ann_file) {
    print STDERR "<!-- HTML-EVALUATION-EXACT --><table><tr><th>type</th><th>automatic</th><th>class</th><th>manual</th><th>class</th><th>sentence</th></tr>\n";
    print STDERR "<!-- HTML-EVALUATION-PARTIAL --><table><tr><th>type</th><th>automatic</th><th>class</th><th>manual</th><th>class</th><th>sentence</th></tr>\n";
  }
  else {
    print STDERR "<!-- HTML-EVALUATION-EXACT --><p>No manual annotation provided.</p>\n";
    print STDERR "<!-- HTML-EVALUATION-PARTIAL --><p>No manual annotation provided.</p>\n";
  }
}


=item print_log_tail

Prints tail info for the document (end of the html table)

=cut

sub print_log_tail {
  if ($ann_file) {
    print STDERR "<!-- HTML-EVALUATION-EXACT --></table>\n";
    print STDERR "<!-- HTML-EVALUATION-PARTIAL --></table>\n";
  }
}


=item print_eval

Prints a single evaluation out to STDERR in TSV and HTML formats.

=cut

sub print_eval {
  my ($type, $auto_range, $auto_text, $auto_event, $ann_range, $ann_text, $ann_event) = @_;
  my $range = ($auto_range =~/^\d+:\d+$/) ? $auto_range : $ann_range;
  my $sentence = get_sentence_html($auto_range, $ann_range);
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

  # now compare the source events (types of sources)
  my $event_color = $color;
  if ($type =~ /SOURCE-HIT$/) {
    my $exactness = $type =~ /PARTIAL/ ? 'PARTIAL' : 'EXACT';
    my $pure_auto_event = $auto_event;
    $pure_auto_event =~ s/^.*://; # get rid of info about NEs
    my $hit = 'HIT'; # let us be optimistic ;-)
    if ($pure_auto_event ne $ann_event) { # disagreement on the source type
      $event_color = '#ef6109';
      $hit = 'MISS';
    }
    print STDERR "TSV-SOURCETYPE-$exactness-$hit\t$auto_range\t$auto_text\t$auto_event\t$ann_range\t$ann_text\t$ann_event\t$sentence\n";
  }
  
  print STDERR "<tr style=\"color: $color; background-color: $background\"><td>HTML-$type</td><td><b>$auto_text</b></td><td style=\"color: $event_color\">$auto_event</td><td><u>$ann_text</u></td><td style=\"color: $event_color\">$ann_event</td><td>$sentence</td></tr>\n";
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


=item get_sentence_html

Given two ranges of text indexes (e.g. "124:129"), it returns the sentence to which they belong.
The function uses the first range that is in the correct format and suppose that the other one is either to be omitted or from the same sentence.
Both ranges are marked in the sentence; the first one with bold, the other one with underline.

=cut

sub get_sentence_html {
  my ($range_auto, $range_manual) = @_;

  print STDERR "get_sentence_html: $range_auto, $range_manual\n";
  
  # check if there is auto range given
  my ($start_auto, $end_auto) = (10000, -1);
  if ($range_auto and $range_auto =~ /^(\d+):(\d+)/) {
    ($start_auto, $end_auto) = ($1, $2);
  }

  # check if there is manual range given
  my ($start_manual, $end_manual) = (10000, -1);
  if ($range_manual and $range_manual =~ /^(\d+):(\d+)/) {
    ($start_manual, $end_manual) = ($1, $2);
  }
  
  print STDERR "get_sentence_html:   $start_auto, $end_auto, $start_manual, $end_manual\n";

  if ($end_auto > 0 or $end_manual > 0) { # at least one of the given ranges was properly defined

    my ($start, $end) = $end_auto > 0 ? ($start_auto, $end_auto) : ($start_manual, $end_manual); # for searching for the sentence
    print STDERR "get_sentence_html:     start = $start, end = $end\n";

    foreach $root (@trees) { # go through all sentences
      my ($start_sent, $end_sent) = (attr($root, 'start'), attr($root, 'end'));
      if ($start_sent <= $start and $end_sent >= $end) { # we found the tree
        my $sentence_text = attr($root, 'text');
        my $sentence_html = '';
        for (my $i = 0; $i < length($sentence_text); $i++) {
          if ($start_sent + $i == $start_auto) {
              $sentence_html .= "<b>";
          }
          if ($start_sent + $i == $start_manual) {
              $sentence_html .= "<u>";
          }

          if ($start_sent + $i == $end_manual) {
              $sentence_html .= "</u>";
          }
          if ($start_sent + $i == $end_auto) {
              $sentence_html .= "</b>";
          }
          
          $sentence_html .= substr($sentence_text, $i, 1);
          
        }
        return $sentence_html;
      }
    }
  }
  else {
    return 'N/A';
  }
}




=item partial_match

Returns range (in the form "start:end", or a sequence of these separated by ';') from keys of given hash that at least partially overlaps with the given range.
Otherwise returns undef.

=cut

sub partial_match {
  my ($range, $rh_range2text) = @_;
  # print STDERR "partial_match: input range: $range\n";
  my @range_parts = split(';', $range);
  foreach my $range_part (@range_parts) { # for each consequent range
    if ($range_part =~ /^(\d+):(\d+)$/) {
      my ($start, $end) = ($1, $2);
      my @ranges = keys(%$rh_range2text);
      foreach my $r (@ranges) {
        my @r_parts = split(';', $r);
        foreach my $r_part (@r_parts) { # for each consequent range from the key
          if ($r_part =~ /^(\d+):(\d+)$/) {
            my ($s, $e) = ($1, $2);
            next if ($e<$start or $end<$s);
            # print STDERR "partial_match:  - SUCCESS, matches with $r!\n";
            return $r;
          }
        }
      }
    }
  }
  return undef;
}

=item evaluate_single_event

Checks the event ('phrase' or source type) with the given nodes representing a text for presence in the manual annotation.
Prints info about matching/missing

$event may be:

for a phrase: 'phrase'
for source, one of:
        'anonymous'
        'anonymous-partial'
        'unofficial'
        'official-political'
        'official-non-political'

Also collects info about automatic annotation in these hashes:
my %h_phrase_range2text;
my %h_source_range2text;
my %h_source_range2type;

The log going to STDERR is used to counting the reliability of phrases (that's why $lemma and $constraint are among arguments).

=cut

sub evaluate_single_event {
  my ($event, $lemma, $constraint, $root, @nodes) = @_;
  
  my $range = get_range(@nodes);
  my $text = get_text(@nodes);
  
  if ($event eq 'phrase') {
    $h_phrase_range2text{$range} = get_text(@nodes);
    if ($ann_file) { # evaluate the event against manual annotation
      if ($h_ann_phrase_range2text{$range}) {
        print_eval('EVALUATION-EXACT-PHRASE-HIT', $range, $text, '-', $range, $text, '-');
        print_eval('EVALUATION-PARTIAL-PHRASE-HIT', $range, $text, '-', $range, $text, '-');
        print STDERR "RELIABILITY_COUNT\t$lemma\t$constraint\tHIT\n";
      }
      else {
        print_eval('EVALUATION-EXACT-PHRASE-FALSE-POSITIVE', $range, $text, '-', 'N/A', 'N/A', '-');
        my $partial_phrase_range = partial_match($range, \%h_ann_phrase_range2text);
        if ($partial_phrase_range) {
          my $partial_text = $h_ann_phrase_range2text{$partial_phrase_range};
          print_eval('EVALUATION-PARTIAL-PHRASE-HIT', $range, $text, '-', $partial_phrase_range, $partial_text, '-');
          print STDERR "RELIABILITY_COUNT\t$lemma\t$constraint\tHIT_PARTIAL\n";
        }
        else {
          print_eval('EVALUATION-PARTIAL-PHRASE-FALSE-POSITIVE', $range, $text, '-', 'N/A', 'N/A', '-');
          print STDERR "RELIABILITY_COUNT\t$lemma\t$constraint\tFALSE_POSITIVE\n";
        }
      }
    }
  }
  else { # source
    $h_source_range2text{$range} = get_text(@nodes);
    $h_source_range2type{$range} = $event;
    if ($ann_file) { # evaluate the event against manual annotation
      if ($h_ann_source_range2text{$range}) {
        my $event_manual = $h_ann_source_range2type{$range} // 'N/A';
        print_eval('EVALUATION-EXACT-SOURCE-HIT', $range, $text, $event, $range, $text, $event_manual);
        print_eval('EVALUATION-PARTIAL-SOURCE-HIT', $range, $text, $event, $range, $text, $event_manual);
      }
      else {
        print_eval('EVALUATION-EXACT-SOURCE-FALSE-POSITIVE', $range, $text, $event, 'N/A', 'N/A', 'N/A');
        my $partial_source_range = partial_match($range, \%h_ann_source_range2text);
        if ($partial_source_range) {
          my $partial_text = $h_ann_source_range2text{$partial_source_range};
          my $event_manual = $h_ann_source_range2type{$partial_source_range} // 'N/A';
          print_eval('EVALUATION-PARTIAL-SOURCE-HIT', $range, $text, $event, $partial_source_range, $partial_text, $event_manual);
        }
        else {
          print_eval('EVALUATION-PARTIAL-SOURCE-FALSE-POSITIVE', $range, $text, $event, 'N/A', 'N/A', 'N/A');
        }
      }
    }
  }
}


=item evaluate_false_negatives

Finds and prints false negatives for the given sentence.
# hashes to keep info about manual annotation:
# my %h_ann_phrase_range2text; # '1354:1359' => 'podle'
# my %h_ann_source_range2text; # '1360:1365' => 'vědců'
# my %h_ann_source_range2type; # '1360:1365' => 'anonymous-partial'
# hashes with automatic annotation:
my %h_phrase_range2text;
my %h_source_range2text;
my %h_source_range2type;

=cut

sub evaluate_false_negatives {
  my $root = shift;
  return if !$ann_file; # do nothing if no manuall annotation was provided

  my $sent_start = attr($root, 'start');
  my $sent_end = attr($root, 'end');
  print STDERR "evaluate_false_negatives: sentence $sent_start:$sent_end\n";

  # phrases
  foreach my $ann_phrase_range (keys(%h_ann_phrase_range2text)) {
    if ($ann_phrase_range =~ /^(\d+):(\d+)$/) {
      my ($s, $e) = ($1, $2);
      print STDERR "evaluate_false_negatives:   ann phrase range $s:$e\n";
      next if ($e<$sent_start or $sent_end<$s); # choose only ranges from the given sentence
      print STDERR "evaluate_false_negatives:     -within the sentence!\n";
      next if ($h_phrase_range2text{$ann_phrase_range}); # exact HIT, already reported elsewhere
      # now we know it is exact miss
      my $text = $h_ann_phrase_range2text{$ann_phrase_range};
      my $sentence = get_sentence($ann_phrase_range);
      print_eval('EVALUATION-EXACT-PHRASE-FALSE-NEGATIVE', 'N/A', 'N/A', '-', $ann_phrase_range, $text, '-');
      my $partial_phrase_range = partial_match($ann_phrase_range, \%h_phrase_range2text);
      if (!$partial_phrase_range) {
        print_eval('EVALUATION-PARTIAL-PHRASE-FALSE-NEGATIVE', 'N/A', 'N/A', '-', $ann_phrase_range, $text, '-');
      }
      # partial HIT already reported elsewhere
    }
  }

  # sources
  foreach my $ann_source_range (keys(%h_ann_source_range2text)) {
    if ($ann_source_range =~ /^(\d+):(\d+)$/) {
      my ($s, $e) = ($1, $2);
      print STDERR "evaluate_false_negatives:   ann source range $s:$e\n";
      next if ($e<$sent_start or $sent_end<$s); # choose only ranges from the given sentence
      print STDERR "evaluate_false_negatives:     -within the sentence!\n";
      next if ($h_source_range2text{$ann_source_range}); # exact HIT, already reported elsewhere
      # now we know it is exact miss
      my $text = $h_ann_source_range2text{$ann_source_range};
      my $event_manual = $h_ann_source_range2type{$ann_source_range};
      print_eval('EVALUATION-EXACT-SOURCE-FALSE-NEGATIVE', 'N/A', 'N/A', 'N/A', $ann_source_range, $text, $event_manual);
      my $partial_source_range = partial_match($ann_source_range, \%h_source_range2text);
      if (!$partial_source_range) {
        print_eval('EVALUATION-PARTIAL-SOURCE-FALSE-NEGATIVE', 'N/A', 'N/A', 'N/A', $ann_source_range, $text, $event_manual);
      }
      # partial HIT already reported elsewhere
    }
  }
}


=item get_range

Returns a text index range for an array of nodes
For non-contiguous ranges, the individual contiguous parts are separated by ';'

=cut

sub get_range {
  my @nodes = sort {attr($a, 'start') <=> attr($b, 'start')} @_;
  return '' if !@nodes;
  # print STDERR "get_range: nodes: " . join(' ', map {attr($_, 'form')} @nodes) . "\n";
  my $range = '';
  my $start = shift(@nodes);
  my $end = $start;
  my $prev = $start;
  foreach my $node (@nodes) { # go through the remaining nodes
    if (attr($prev, 'end') + 1 >= attr($node, 'start')) { # the nodes are consequent
      $end = $node;
      $prev = $node;
    }
    else { # there is a gap between $prev and $node
      my $sep = $range ? ';' : '';
      $range .= $sep . attr($start, 'start') . ':' . attr($end, 'end');
      $start = $node;
      $end = $node;
      $prev = $node;
    }
  }
  # now process the last contiguous part
  my $sep = $range ? ';' : '';
  $range .= $sep . attr($start, 'start') . ':' . attr($end, 'end');
  # print STDERR "get_range: result: $range\n";
  return $range;
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

It recursively adds sons whith deprel nmod, amod, flat (and flat:foreign), case (with exception of 'podle') and acl:relcl (acl:relcl with the whole subtree right away)

=cut

sub get_source_nodes {
  my $node = shift;
  
  if (attr($node, 'deprel') eq 'acl:relcl') { # rel. clause, e.g. "lidé, které Radiožurnál oslovil"
    return descendants($node);
  }
  
  my @source_sons = grep {attr($_, 'lemma') !~ /^(po)?dle$/}
                    grep {attr($_, 'deprel') =~ /^(nmod|amod|flat|flat:foreign|case|acl:relcl)$/}
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

=item

    # Původní volání metodou GET - neprošly delší texty

    # Nastavení URL pro volání REST::API s parametry
    my $tokenizer = 'tokenizer=ranges';
    if ($input_format eq 'presegmented') {
      $tokenizer .= ';presegmented';
    }
    my $url = 'http://lindat.mff.cuni.cz/services/udpipe/api/process?' . $tokenizer . '&tagger&parser&data=' . uri_escape_utf8($text);

    print STDERR "url = $url\n";
    # Vytvoření instance LWP::UserAgent
    my $ua = LWP::UserAgent->new;

    # Vytvoření požadavku
    my $req = HTTP::Request->new('GET', $url);
    $req->header('Content-Type' => 'application/json');

=cut

=item

    # Nefunkční pokus o volání metodou POST

    # Nastavení URL pro volání REST::API
    my $url = 'http://lindat.mff.cuni.cz/services/udpipe/api/process';

    # Připravení dat pro POST požadavek
    my %post_data = (
        tokenizer => 'ranges',
        tagger => 1,
        parser => 1,
        data => uri_escape_utf8($text)
    );

    if ($input_format eq 'presegmented') {
        $post_data{tokenizer} .= ';presegmented';
    }

    # Vytvoření instance LWP::UserAgent
    my $ua = LWP::UserAgent->new;

    # Vytvoření POST požadavku s daty jako JSON
    my $req = HTTP::Request->new('POST', $url);
    $req->header('Content-Type' => 'application/json');
    $req->content(encode_json(\%post_data));

=cut


    # Funkční volání metodou POST, i když podivně kombinuje URL-encoded s POST

    # Nastavení URL pro volání REST::API s parametry
    my $tokenizer = 'tokenizer=ranges';
    if ($input_format eq 'presegmented') {
      $tokenizer .= ';presegmented';
    }
    my $url = 'http://lindat.mff.cuni.cz/services/udpipe/api/process?' . $tokenizer . '&tagger&parser';

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

=item
    
    # Stará verze metodou GET
    
    # Nastavení URL pro volání REST::API s parametry
    my $url = 'http://lindat.mff.cuni.cz/services/nametag/api/recognize?input=conllu&output=conllu-ne&data=' . uri_escape_utf8($conll);

    # Vytvoření instance LWP::UserAgent
    my $ua = LWP::UserAgent->new;

    # Vytvoření požadavku
    my $req = HTTP::Request->new('GET', $url);
    $req->header('Content-Type' => 'application/json');

=cut

    # Funkční volání metodou POST, i když podivně kombinuje URL-encoded s POST

    # Nastavení URL pro volání REST::API s parametry
    my $url = 'http://lindat.mff.cuni.cz/services/nametag/api/recognize?input=conllu&output=conllu-ne';

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
        # print STDERR "NameTag result:\n$result\n";
        return $result;
    } else {
        print STDERR "NameTag error: " . $res->status_line . "\n";
        return $conll; 
    }
}
