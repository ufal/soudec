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
use File::Basename; # to get a filename from the whole path
use Time::HiRes qw(gettimeofday tv_interval); # to measure how long the program ran
use Data::Dumper;

use FindBin qw($Bin);  # $Bin je adresář, kde je skript
use lib "$Bin/lib";    # Absolutní cesta k lib

use UD v1.4.1;
use mylog v1.0.0;
$mylog::name = 'SouDeC';


# STDIN and STDOUT in UTF-8
binmode STDIN, ':encoding(UTF-8)';
binmode STDOUT, ':encoding(UTF-8)';

my $start_time = [gettimeofday];

my $VER_en = '1.17 (20250827)'; # version of the program
my $VER_cs = $VER_en; # version of the program

my @features_cs = ('detekce citačních zdrojů',
                   'klasifikace citačních zdrojů',
                   'detekce obsahu citací (beta)'
                  );
my @features_en = ('detection of citation sources',
                   'classification of citation sources',
                   'detection of citation content (beta)'
                  );

my $experimental_zero_perspron = 1; # use experimental introduction of zero persprons
my $experimental_zero_gen = 1; # use experimental introduction of #Gen node in passive 'se' construction (like in 'tvrdí se')

my $FEATS_cs = join(' • ', @features_cs); 
my $FEATS_en = join(' • ', @features_en);

$mylog::logging_level = 2; # default log level, can be changed using the -ll parameter (0=full, 1=limited, 2=minimal)

my %logging_level_label = (0 => 'full', 1 => 'limited', 2 => 'minimal');

#######################################

# default minimal required phrase reliability
my $MIN_RELIABILITY_DEFAULT = 10;
# default output format
my $OUTPUT_FORMAT_DEFAULT = 'txt';
# default input format
my $INPUT_FORMAT_DEFAULT = 'txt';
# default phrase reliability file
my $PHRASE_RELIABILITY_FILE_DEFAULT = 'resources/phrases_reliability.csv';
# default UI language
my $UI_LANGUAGE_DEFAULT = 'en';

# variables for arguments
my $input_file;
my $ann_file;
my $stdin;
my $input_format;
my $phrase_reliability_file;
my $min_phrase_reliability;
my $output_format;
my $output_statistics;
my $ui_language;
my $add_NE;
my $add_antecedent;
my $store_format;
my $store_statistics;
my $logging_level_override;
my $version;
my $info;
my $help;

# getting the arguements
GetOptions(
    'i|input-file=s'         => \$input_file, # the name of the input file
    'a|ann-file=s'           => \$ann_file, # the name of the file with manual annotation
    'si|stdin'               => \$stdin, # should the input be read from STDIN?
    'if|input-format=s'      => \$input_format, # input format, possible values: txt, presegmented
    'p|phrase-file=s'        => \$phrase_reliability_file, # the name of the file with a list of citation phrases and their reliability
    'r|reliability=i'        => \$min_phrase_reliability, # minimal required phrase reliability
    'of|output-format=s'     => \$output_format, # output format, possible values: txt, html, conllu
    'os|output-statistics=s' => \$output_statistics, # add statistics to the output in the given format (html, tsv, or a comma-separated list thereof); if present, output is JSON with items: data (in output-format) and stats_html and/or stats_tsv
    'uil|ui-language=s'      => \$ui_language, # localize the response whenever possible to the given language: en (default), cs
    'ne|named-entities'      => \$add_NE, # add named entities as marked by NameTag to the classes in the output
    'aa|add-antecedent'      => \$add_antecedent, # add the antecedent if coreference is used to determine the class
    'sf|store-format=s'      => \$store_format, # log the result in the given format: txt, html, conllu
    'ss|store-statistics=s'  => \$store_statistics, # log statistics in the given format (html, tsv, or a comma-separated list thereof)
    'll|logging-level=s'     => \$logging_level_override, # override the default (minimal) logging level (0=full, 1=limited, 2=minimal)
    'v|version'              => \$version, # print the version of the program and exit
    'n|info'                 => \$info, # print the info (program version and supported features) as JSON and exit
    'h|help'                 => \$help, # print a short help and exit
);

if (defined($logging_level_override)) {
  $mylog::logging_level = $logging_level_override;
}

my $script_path = $0;  # Získá název spuštěného skriptu s cestou
my $script_dir = dirname($script_path);  # Získá pouze adresář ze získané cesty


if ($version) {
  if ($ui_language eq 'cs') {
    print "SouDeC verze $VER_cs.\n";
  }
  else {
    print "SouDeC version $VER_en.\n";
  }
  exit 0;
}


if ($info) {
  my $json_data;
  if ($ui_language eq 'cs') {
    $json_data = {
       version  => $VER_cs,
       features => $FEATS_cs,
    };
  }
  else {
    $json_data = {
       version  => $VER_en,
       features => $FEATS_en,
    };
  }
  # Encode the Perl data structure into a JSON string
  my $json_string = encode_json($json_data);
  # Print the JSON string to STDOUT
  print $json_string;
  exit 0;
}


if ($help) {
  print "SouDeC version $VER_en.\n";
  my $text = <<'END_TEXT';
Usage: soudec.pl [options]
options:  -i|--input-file [input text file name]
          -a|--ann-file [manual annotation file name]
         -si|--stdin (input text provided via stdin)
         -if|--input-format [input format: txt (default) or presegmented]
          -p|--phrase-file [phrases reliability file name]
          -r|--reliability [minimal required phrase reliability]
         -of|--output-format [output format: txt (default), html, conllu]
         -os|--output-statistics (format: add statistics to the output in the given format (html, tsv, or a comma-separated list thereof); if present, output is JSON with items: data (in output-format) and stats_html and/or stats_tsv)
        -uil|--ui-language [language: localize the response whenever possible to the given language: en (default), cs]
	 -ne|--named-entities (add NameTag marks to classes in the output)
         -aa|--add-antecedent (add the antecedent if coreference is used to determine the class)
         -sf|--store-format [format: log the output in the given format: txt, html, conllu]
         -ss|--store-statistics (format: log statistics in the given format ('html', 'tsv', or a comma-separated list thereof))
         -ll|--logging-level (override the default (minimal) logging level (0=full, 1=limited, 2=minimal))
          -v|--version (prints the version of the program and ends)
          -h|--help (prints a short help and ends)
END_TEXT
  print $text;
  exit 0;
}

###################################################################################
# Summarize the program arguments to the log (except for --version and --help)
###################################################################################

mylog(2, "####################################################################\n");
mylog(2, "SouDec $VER_en (logging level: $mylog::logging_level - $logging_level_label{$mylog::logging_level})\n");
mylog(2, "####################################################################\n");

mylog(0, "Arguments:\n");

if ($stdin) {
  mylog(0, " - input: STDIN\n");
}
elsif ($input_file) {
  mylog(0, " - input: file $input_file\n");
}

if (!defined $input_format) {
  mylog(0, " - input format: not specified, set to default $INPUT_FORMAT_DEFAULT\n");
  $input_format = $INPUT_FORMAT_DEFAULT;
}
elsif ($input_format !~ /^(txt|presegmented)$/) {
  mylog(0, " - input format: unknown ($input_format), set to default $INPUT_FORMAT_DEFAULT\n");
  $input_format = $INPUT_FORMAT_DEFAULT;
}
else {
  mylog(0, " - input format: $input_format\n");
}

if ($ann_file) {
  mylog(0, " - file with manual annotation: $ann_file\n");  
}

if (!defined $phrase_reliability_file) {
  mylog(0, " - phrase reliability file: not specified, set to default $PHRASE_RELIABILITY_FILE_DEFAULT\n");
  $phrase_reliability_file = "$script_dir/$PHRASE_RELIABILITY_FILE_DEFAULT";
}
else {
  mylog(0, " - phrase reliability file: $phrase_reliability_file\n");
}

if (!defined $min_phrase_reliability) {
  mylog(0, " - min. phrase reliability: not specified, set to default $MIN_RELIABILITY_DEFAULT\n");
  $min_phrase_reliability = $MIN_RELIABILITY_DEFAULT;
}
else {
  mylog(0, " - min. phrase reliability: $min_phrase_reliability\n");
}

$output_format = lc($output_format) if $output_format;
if (!defined $output_format) {
  mylog(0, " - output format: not specified, set to default $OUTPUT_FORMAT_DEFAULT\n");
  $output_format = $OUTPUT_FORMAT_DEFAULT;
}
elsif ($output_format !~ /^(txt|html|conllu)$/) {
  mylog(0, " - output format: unknown ($output_format), set to default $OUTPUT_FORMAT_DEFAULT\n");
  $output_format = $OUTPUT_FORMAT_DEFAULT;
}
else {
  mylog(0, " - output format: $output_format\n");
}

$output_statistics = $output_statistics // '';
$output_statistics = lc($output_statistics) if $output_statistics;
if ($output_statistics) {
  if ($output_statistics =~ /^(html|tsv)(,(html|tsv))*$/) {
    mylog(0, " - add SouDeC statistics to the output in format(s) '$output_statistics'; the output will be JSON with items: data (in $output_format) and stats_html and/or stats_tsv\n");
  }
  else {
    mylog(0, " - unknown format for statistics ($output_statistics); the statistics will not be part of output\n");
    $output_statistics = undef;
  }
}

if ($add_NE) {
  mylog(0, " - add named entities as marked by NameTag to classes in the output\n");
}

if ($add_antecedent) {
  mylog(0, " - add the antecedent to the classes in the output if coreference is used to determine the class\n");
}

$store_format = lc($store_format) if $store_format;
if ($store_format) {
  if ($store_format =~ /^(txt|html|conllu)$/) {
    mylog(0, " - log the output to a file in $store_format\n");
  }
  else {
    mylog(0, " - unknown format for logging the output ($store_format); the output will not be logged\n");
    $store_format = undef;
  }
}

if ($store_statistics) {
  mylog(0, " - log SouDeC statistics in an HTML file\n");
}
$store_statistics = $store_statistics // '';
$store_statistics = lc($store_statistics) if $store_statistics;
if ($store_statistics) {
  if ($store_statistics =~ /^(html|tsv)(,(html|tsv))*$/) {
    mylog(0, " - log SouDeC statistics in format(s) '$store_statistics'\n");
  }
  else {
    mylog(0, " - unknown format for statistics ($store_statistics); the statistics will not be logged\n");
    $store_statistics = undef;
  }
}


if (defined($logging_level_override)) {
  mylog(2, " - logging level override: $logging_level_override - $logging_level_label{$logging_level_override}\n");
}

mylog(0, "\n");


###################################################################################

# lists of keywords to classify a source
my %keywords_anonymous = ('zdroj' => 1,
                          'pozorovatel' => 1
                         );

my %keywords_single_anonymous = ('všechen' => 1,
                                 'každý' => 1,
			         'mnohý' => 1,
				 'nikdo' => 1
                                );

my %keywords_anonymous_partial = ('část' => 1,
                                  'některý' => 1,
                                  'většina' => 1,
                                  'řada' => 1,
				  'informace' => 1
                         );

my %keywords_unofficial = ('slovník' => 1,
                           'encyklopedie' => 1,
                         );

# List of one-word states
my %states = ('Čína' => 1,
              'Indie' => 1,
              'USA' => 1,
              'Indonésie' => 1,
              'Pákistán' => 1,
              'Nigérie' => 1,
              'Brazílie' => 1,
              'Bangladéš' => 1,
              'Rusko' => 1,
              'Mexiko' => 1,
              'Japonsko' => 1,
              'Etiopie' => 1,
              'Filipíny' => 1,
              'Egypt' => 1,
              'Vietnam' => 1,
              'Írán' => 1,
              'Turecko' => 1,
              'Německo' => 1,
              'Thajsko' => 1,
              'Francie' => 1,
              'Itálie' => 1,
              'Tanzanie' => 1,
              'Keňa' => 1,
              'Myanmar' => 1,
              'Kolumbie' => 1,
              'Španělsko' => 1,
              'Argentina' => 1,
              'Alžírsko' => 1,
              'Ukrajina' => 1,
              'Súdán' => 1,
              'Irák' => 1,
              'Uganda' => 1,
              'Kanada' => 1,
              'Polsko' => 1,
              'Maroko' => 1,
              'Arábie' => 1,
              'Uzbekistán' => 1,
              'Malajsie' => 1,
              'Peru' => 1,
              'Venezuela' => 1,
              'Afghánistán' => 1,
              'Mosambik' => 1,
              'Jemen' => 1,
              'Ghana' => 1,
              'Angola' => 1,
              'Nepál' => 1,
              'Madagaskar' => 1,
              'Pobřeží' => 1,
              'Austrálie' => 1,
              'Kamerun' => 1,
              'Niger' => 1,
              'Tchaj-wan' => 1,
              'Burkina' => 1,
              'Lanka' => 1,
              'Mali' => 1,
              'Rumunsko' => 1,
              'Chile' => 1,
              'Kazachstán' => 1,
              'Malawi' => 1,
              'Sýrie' => 1,
              'Guatemala' => 1,
              'Ekvádor' => 1,
              'Nizozemsko' => 1,
              'Zambie' => 1,
              'Senegal' => 1,
              'Čad' => 1,
              'Somálsko' => 1,
              'Kambodža' => 1,
              'Zimbabwe' => 1,
              'Rwanda' => 1,
              'Guinea' => 1,
              'Benin' => 1,
              'Tunisko' => 1,
              'Belgie' => 1,
              'Kuba' => 1,
              'Bolívie' => 1,
              'Haiti' => 1,
              'Burundi' => 1,
              'Česko' => 1,
              'Švédsko' => 1,
              'Řecko' => 1,
              'Portugalsko' => 1,
              'Ázerbájdžán' => 1,
              'Jordánsko' => 1,
              'Maďarsko' => 1,
              'Bělorusko' => 1,
              'Honduras' => 1,
              'Tádžikistán' => 1,
              'Papua' => 1,
              'Rakousko' => 1,
              'Švýcarsko' => 1,
              'Izrael' => 1,
              'Sierra' => 1,
              'Togo' => 1,
              'Hongkong' => 1,
              'Bulharsko' => 1,
              'Srbsko' => 1,
              'Laos' => 1,
              'Paraguay' => 1,
              'Libanon' => 1,
              'Libye' => 1,
              'Kyrgyzstán' => 1,
              'Salvador' => 1,
              'Nikaragua' => 1,
              'Turkmenistán' => 1,
              'Dánsko' => 1,
              'Singapur' => 1,
              'Finsko' => 1,
              'Slovensko' => 1,
              'Norsko' => 1,
              'Kostarika' => 1,
              'Irsko' => 1,
              'Omán' => 1,
              'Libérie' => 1,
              'Palestina' => 1,
              'Kuvajt' => 1,
              'Panama' => 1,
              'Chorvatsko' => 1,
              'Mauritánie' => 1,
              'Gruzie' => 1,
              'Uruguay' => 1,
              'Eritrea' => 1,
              'Bosna' => 1,
              'Mongolsko' => 1,
              'Portoriko' => 1,
              'Arménie' => 1,
              'Albánie' => 1,
              'Litva' => 1,
              'Jamajka' => 1,
              'Katar' => 1,
              'Moldavsko' => 1,
              'Namibie' => 1,
              'Gambie' => 1,
              'Gabon' => 1,
              'Lesotho' => 1,
              'Slovinsko' => 1,
              'Botswana' => 1,
              'Lotyšsko' => 1,
              'Kosovo' => 1,
              'Bahrajn' => 1,
              'Trinidad' => 1,
              'Estonsko' => 1,
              'Mauricius' => 1,
              'Svazijsko' => 1,
              'Džibutsko' => 1,
              'Kypr' => 1,
              'Fidži' => 1,
              'Réunion' => 1,
              'Guyana' => 1,
              'Bhútán' => 1,
              'Macao' => 1,
              'Lucembursko' => 1,
              'Surinam' => 1,
              'Kapverdy' => 1,
              'Malta' => 1,
              'Brunej' => 1,
              'Guadeloupe' => 1,
              'Bahamy' => 1,
              'Belize' => 1,
              'Martinik' => 1,
              'Maledivy' => 1,
              'Island' => 1,
              'Barbados' => 1,
              'Vanuatu' => 1,
              'Mayotte' => 1,
              'Abcházie' => 1,
              'Samoa' => 1,
              'Guam' => 1,
              'Curaçao' => 1,
              'Kiribati' => 1,
              'Aruba' => 1,
              'Grenada' => 1,
              'Jersey' => 1,
              'Mikronésie' => 1,
              'Tonga' => 1,
              'Seychely' => 1,
              'Antigua' => 1,
              'Andorra' => 1,
              'Dominika' => 1,
              'Bermudy' => 1,
              'Guernsey' => 1,
              'Grónsko' => 1,
              'Turks' => 1,
              'Lichtenštejnsko' => 1,
              'Monako' => 1,
              'Gibraltar' => 1,
              'Alandy' => 1,
              'Palau' => 1,
              'Anguilla' => 1,
              'Wallis' => 1,
              'Nauru' => 1,
              'Tuvalu' => 1,
              'Montserrat' => 1,
              'Falklandy' => 1,
              'Špicberky' => 1,
              'Norfolk' => 1,
              'Niue' => 1,
              'Tokelau' => 1,
              'Vatikán' => 1,
);

#######################################
# HASHES FOR SOMETHING LIKE COREFERENCE

# hashes to keep classes and full expressions of already seen surnames
my %surname2class;
my %surname2full; # the original (full) mention of the surname

# hashes to keep already seen nouns (not surnames)
# e.g.: for "britský list" -> "britský bulvární list The Daily Mirror", the hashes would contain:
#       'list Daily Mirror' => 'unofficial'
#       'list Daily Mirror' => 'britský bulvární list The Daily Mirror'
my %noun_lemmas2class;
my %noun_lemmas2full; # the original (full) mention of the source

# hashes for keeping classes and full expressions for a given gender and number of sources containing Animacy=Anim
# to be used if a personal pronoun is found as a source
my %last_gender_number2class;
my %last_gender_number2full; # the original (full) mention of the source


#############################
# Colours for html

my $color_a = 'red';
my $color_ap = 'magenta';
my $color_u = 'orange';
my $color_onp = 'darkcyan';
my $color_op = 'blue';

my $color_phrase = 'brown'; # used to be darkred
my $color_source = 'darkgreen';
my $color_source_antecedent = 'darkblue';
my $color_source_brackets = 'darkblue';


###################################################################################
# Let us first read the file with reliability of citation phrases
###################################################################################

my %phrase_lemma_constraint2reliability; # reliability of the phrase lemmas together with a constraint in percents (in how many percents it was used in training data as a citation phrase); the phrase lemma is separated by '_' from the constraint
my %phrase_lemma2constraints; # which constraints does the phrase require (if any); the individual constraints are separated by '_'; an empty constraint is represented by 'NoConstraint'

mylog(1, "Reading phrase lemmas and their reliability from $phrase_reliability_file\n");

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
    # mylog(0, "Phrase $lemma (with constraint $constraint) and reliability $reliability_percent\n");
    $phrases_count++;
    if ($phrase_lemma2constraints{$lemma}) { # if there already was a constraint for this lemma
      # mylog(0, "Note: multiple constraints for lemma $lemma.\n");
      $phrase_lemma2constraints{$lemma} .= "_";
    }
    $phrase_lemma2constraints{$lemma} .= $constraint;
  }
  else {
    mylog(0, "Unknown format of a line in file $phrase_reliability_file:\n$line\n");
  }
}
mylog(1, "$phrases_count phrase lemmas (plus a constraint) have been read from file $phrase_reliability_file:\n");


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

# possible values for source type (used to determine order of the TSV stats results)
my @source_type_classes = ('anonymous',
                           'anonymous-partial',
                           'unofficial',
                           'official-political',
                           'official-non-political'
                          );

# similar hashes to later collect info about automatic recognition, to be compared with manual
my %h_phrase_range2text;
my %h_source_range2text;
my %h_source_range2type;


if ($ann_file) {
  mylog(1, "Reading manual annotation from $ann_file\n");

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
  mylog(0, " - PHRASES:\n");
  foreach my $range (keys(%h_ann_phrase_range2text)) {
    mylog(0, "   - $range - $h_ann_phrase_range2text{$range}\n");
  }
  mylog(0, " - SOURCES:\n");
  foreach my $range (keys(%h_ann_source_range2text)) {
    mylog(0, "   - $range - $h_ann_source_range2text{$range} - $h_ann_source_range2type{$range}\n");
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
  mylog(2, "No input to process! Exiting!\n");
  exit -1;
}

#mylog(0, $input_content);


my $input_length = length($input_content);
mylog(2, "input length: $input_length characters\n");

my $max_input_length = 75000;
my $max_input_length_text = '75 thousand';
if ($ui_language and $ui_language eq 'cs') {
  $max_input_length_text = '75 tisíc';
}

if ($input_length > $max_input_length) { # avoid long texts
  # 'data' (in output-format)
  # 'stats_html' (in html, if requested)
  # 'stats_tsv' (in TSV, if requested)

  my $json_data = {
    data  => "<font color=\"red\">The text is too long ($input_length characters, the maximum is $max_input_length_text)!</font>",
  };
  if ($output_statistics =~ /\bhtml\b/) {
    $json_data->{stats_html} = "<font color=\"red\">The text is too long ($input_length characters, the maximum is $max_input_length_text)!</font>";
  }
  if ($output_statistics =~ /\btsv\b/) {
    $json_data->{stats_tsv} = "The text is too long ($input_length characters, the maximum is $max_input_length_text)!";
  }

  if ($ui_language and $ui_language eq 'cs') {
    $json_data = {
       data  => "<font color=\"red\">Příliš dlouhý text ($input_length znaků, povolené maximum je $max_input_length_text)!</font>",
     };
    if ($output_statistics =~ /\bhtml\b/) {
      $json_data->{stats_html} = "<font color=\"red\">Příliš dlouhý text ($input_length znaků, povolené maximum je $max_input_length_text)!</font>";
    }
    if ($output_statistics =~ /\btsv\b/) {
      $json_data->{stats_tsv} = "Příliš dlouhý text ($input_length znaků, povolené maximum je $max_input_length_text)!";
    }
  }

  # Encode the Perl data structure into a JSON string
  my $json_string = encode_json($json_data);
  # Print the JSON string to STDOUT
  print $json_string;
  mylog(2, "Input text too long (max allowed: $max_input_length)! Exiting!\n");

  exit;
}


my $processing_time;
my $processing_time_udpipe;
my $processing_time_nametag;


###################################################################################
# Let us parse the file using UDPipe REST API
###################################################################################

my $start_time_udpipe = [gettimeofday];

my $conll_data = call_udpipe($input_content, 'cs', $input_format, 'all');

# Store the result to a file (just to have it, not needed for further processing)
#  open(OUT, '>:encoding(utf8)', "$input_file.conll") or die "Cannot open file '$input_file.conll' for writing: $!";
#  print OUT $conll_data;
#  close(OUT);

# Measure time spent by UDPipe 
my $end_time_udpipe = [gettimeofday];
$processing_time_udpipe = tv_interval($start_time_udpipe, $end_time_udpipe);

my $sentence_count = 0;
my $word_count = 0;

# Rozdělíme text na řádky
my @lines = split /\n/, $conll_data;

foreach my $line (@lines) {
    # Přeskočíme prázdné řádky a komentáře
    next if $line =~ /^\s*$/ || $line =~ /^#/;

    # Pokud řádek začíná číslem a tabulátorem, je to slovo
    if ($line =~ /^\d+\t/) {
        $word_count++;
    }
}

# Počet vět zjistíme podle prázdných řádků nebo komentářů # text
foreach my $line (@lines) {
    if ($line =~ /^# text =/) {
        $sentence_count++;
    }
}

mylog(2, "input length: $word_count tokens, $sentence_count sentences\n");


###################################################################################
# Now let us add info about named entities using NameTag REST API
###################################################################################

my $start_time_nametag = [gettimeofday];

my $conll_data_ne = call_nametag($conll_data);

# Store the result to a file (just to have it, not needed for further processing)
#  open(OUT, '>:encoding(utf8)', "$input_file.conllne") or die "Cannot open file '$input_file.conllne' for writing: $!";
#  print OUT $conll_data_ne;
#  close(OUT);

# Measure time spent by NameTag 
my $end_time_nametag = [gettimeofday];
$processing_time_nametag = tv_interval($start_time_nametag, $end_time_nametag);


###################################################################################
# Let us parse the CONLL format into Tree::Simple tree structures (one tree per sentence)
###################################################################################

my @trees = parse_conllu($conll_data_ne); # array of trees in the document


################################################
# Now we have dependency trees of the sentences
################################################


######################################################
######################################################
#
# MAIN LOOP: let us search for citation phrases
#
######################################################
######################################################


print_log_header();

# variables and hashes for statistics
my $sentences_count = scalar(@trees);
my $tokens_count = 0;
my %source2count = ();
my %source2class = ();
my %class2count = ();
my %source2claims = (); # a value is a reference to an array


foreach my $root (@trees) {
  mylog(0, "\n");
  mylog(0, "====================================================================\n");
  mylog(0, "Sentence id=" . attr($root, 'id') . ": " . attr($root, 'text') . "\n");
  #print_tree($root, "\t");
  
  my @nodes = descendants($root, {sort_children => 1});
  $tokens_count += scalar(@nodes) - 1; # without the root
  
  foreach my $node (@nodes) {
    my $lemma = attr($node, 'lemma');
    my $constraints = $phrase_lemma2constraints{$lemma};

    if (!$constraints) { # the lemma is not among citation phrases
      mylog(0, "No constraints for lemma '$lemma', skipping.\n");
      # Let us check if it is a root node of a source (potentially without citation, e.g. "Požádali jsme o názor ředitele firmy.")
      mylog(0, "Checking if it is a root node of a source (potentially without citation).\n");
      if (attr($node, 'upostag') eq 'NOUN' and attr($node, 'deprel') =~ /^(nsubj|obj|obl)/) { # it might be a root of a source
        mylog(0, " - it is a noun (nsubj, obj, obl).\n");
        my @potential_all_source_nodes = get_whole_source_nodes($node);
	my $potential_all_source_nodes_count = scalar(@potential_all_source_nodes);
        my @NE_nodes = grep {get_misc_value($_, 'NE')} @potential_all_source_nodes;
        my @extraNE_nodes = grep {get_extra_NE_for_node($node, $potential_all_source_nodes_count)} @potential_all_source_nodes;
        if (scalar(@NE_nodes) or scalar(@extraNE_nodes)) { # any Named Entity or extra Named Entity assigned to any of the nodes?
          mylog(0, "Found a potential independent source:\n");
          my $whole_potential_source = text(\@potential_all_source_nodes);
          mylog(0, " - WHOLE POTENTIAL SOURCE: $whole_potential_source\n");
          my $source_type = guess_source_type($root, 0, undef, @potential_all_source_nodes);
          mylog(0, " - POTENTIAL SOURCE TYPE: $source_type\n");
        }
      }
      next; 
    }
    foreach my $constraint (split(/_/, $constraints)) { # split the constraints by separator '_' and work with one constraint at a time
      my $reliability = $phrase_lemma_constraint2reliability{$lemma . '_' . $constraint} // 0;
      mylog(0, "Testing phrase lemma (constraint) '$lemma ($constraint)' with reliability $reliability\n");

      my ($claim_parent, @phrase_nodes) = check_constraint($node, $lemma, $constraint); # check if the constraint is met (e.g., se/si is present) and return the expected parent of the claim and all nodes belonging to the phrase; empty constraint is represented by 'NoConstraint'
      if (!$claim_parent) {
        mylog(0, "- the constraint '$constraint' for lemma '$lemma' is not met.\n");
        next;
      }
      if ($reliability >= $min_phrase_reliability) {
        mylog(0, " - reliability of lemma '$lemma' with constraint '$constraint' is greater than threshold $min_phrase_reliability\n");
        # Checking if there is something like a claim, i.e. a finite-verb core object 
        if (has_finite_verb_object($claim_parent)) {
          evaluate_single_event('phrase', $lemma, $constraint, $root, @phrase_nodes);

          if ($constraint eq 'PREP') { # special treatment of 'podle' and 'dle'
            my $parent = $node->getParent;
            my $source = attr($parent, 'form');
            my @whole_source_nodes = get_whole_source_nodes($parent);
            my $whole_source = text(\@whole_source_nodes);
            mylog(0, " - SOURCE parent: $source\n - WHOLE SOURCE: $whole_source\n");
            my $source_type = guess_source_type($root, 1, $claim_parent, @whole_source_nodes);
            mylog(0, "   - SOURCE TYPE: $source_type\n");
            evaluate_single_event($source_type, $lemma, 'N/A', $root, @whole_source_nodes);
          }

          else { # all cases other than 'podle' and 'dle'
            # Check if the clause is conditional ('Je důležité, aby ministr řekl, že ...')
            my @conditions = grep {attr($_, 'lemma') =~ /^(by|aby|kdyby)$/} $node->getAllChildren;
	    if (@conditions) {
              mylog(0, "- a conditional clause, giving up.\n");
              next;
            }     
            my @nsubj = grep {attr($_, 'deprel') eq 'nsubj'} $node->getAllChildren; # looking for a subject (i.e, the source)

	    if (!@nsubj and attr($node, 'deprel') eq 'conj') { # no subject? Maybe we have a common subject in a conjunction of clauses - let us search for the subject at the parent node (not doing it recursively for now)
              mylog(0, "'conj' verb with no source. Looking for a source at the parent.\n");
	      my $gender = get_feat_value($node, 'Gender');
	      my $number = get_feat_value($node, 'Number');
	      my $parent = $node->getParent;
	      my $parent_gender = get_feat_value($parent, 'Gender');
	      my $parent_number = get_feat_value($parent, 'Number');
	      if ($gender eq $parent_gender and $number eq $parent_number) { # I take common subject only if both verbs have same gender and number
                @nsubj = grep {attr($_, 'deprel') eq 'nsubj'} $parent->getAllChildren;
              }     
            }

	    my @passive_se = grep {attr($_, 'deprel') eq 'expl:pass' and attr($_, 'lemma') eq 'se' and lc(attr($_,'form')) eq 'se'} $node->getAllChildren; # e.g. in "tvrdí se"
	    if (!@nsubj and $experimental_zero_gen and @passive_se) { # no nsubj but passive 'se', as in 'tvrdí se'; let us ad a #Gen node
              my $perspron = Tree::Simple->new({}); # we could use new({}, $node) to make it a child of the governing verb in the tree structure
              set_attr($perspron, 'ord', attr($node, 'ord') - 0.5); # let us put it just before the governing verb
              set_attr($perspron, 'gord', attr($node, 'gord') - 0.5);
              set_attr($perspron, 'form', '#Gen');
              set_attr($perspron, 'lemma', '#Gen');
              set_attr($perspron, 'deprel', 'nsubj');
              set_attr($perspron, 'upostag', 'PRON');
              set_property($perspron, 'feats', 'PronType', 'Prs');
	      set_property($perspron, 'feats', 'Gender', 'Neut');
	      set_property($perspron, 'feats', 'Number', 'Sing');
              #set_attr($perspron, 'xpostag', $xpos);
              set_attr($perspron, 'head', attr($node, 'id'));
              mylog(0, " - No nsubj found but passive 'se' present: adding a #Gen node.\n");
              @nsubj = ($perspron);
            }

            elsif (!@nsubj and $experimental_zero_perspron) { # no nsubj, i.e. no source; let us ad a #PersPron node
              my $perspron = Tree::Simple->new({}); # we could use new({}, $node) to make it a child of the governing verb in the tree structure
              set_attr($perspron, 'ord', attr($node, 'ord') - 0.5); # let us put it just before the governing verb
              set_attr($perspron, 'gord', attr($node, 'gord') - 0.5);
              set_attr($perspron, 'form', '#PersPron');
              set_attr($perspron, 'lemma', '#PersPron');
              set_attr($perspron, 'deprel', 'nsubj');
              set_attr($perspron, 'upostag', 'PRON');
              set_property($perspron, 'feats', 'PronType', 'Prs');
              set_property($perspron, 'feats', 'Gender', get_feat_value($node, 'Gender'));
              set_property($perspron, 'feats', 'Number', get_feat_value($node, 'Number'));
              #set_attr($perspron, 'xpostag', $xpos);
              set_attr($perspron, 'head', attr($node, 'id'));
              mylog(0, " - No nsubj found: adding a #PersPron node.\n");
              @nsubj = ($perspron);
            }
            if (@nsubj) {
              my $subject = attr($nsubj[0], 'form');
              my @whole_source_nodes = get_whole_source_nodes($nsubj[0]);
              my $whole_source = text(\@whole_source_nodes);
              mylog(0, " - SOURCE nsubj: $subject\n - WHOLE SOURCE: $whole_source\n");
              my $source_type = guess_source_type($root, 1, $claim_parent, @whole_source_nodes);
              mylog(0, "   - SOURCE TYPE: $source_type\n");
              evaluate_single_event($source_type, $lemma, 'N/A', $root, @whole_source_nodes);
            }
          }
        }
        else {
          mylog(0, "   - no finite-verb core object found!\n");
        }
      }
    }
  }
  
  evaluate_false_negatives($root);
  
}

print_log_tail();

# Measure time spent so far
my $end_time = [gettimeofday];
$processing_time = tv_interval($start_time, $end_time);


# calculate and format statistics if needed
my $stats_html;
my $stats_tsv;
if ($store_statistics or $output_statistics) { # we need to calculate statistics
  if ($store_statistics =~ /\bhtml\b/ or $output_statistics =~ /\bhtml\b/) {
    $stats_html = get_stats_html();
  }
  if ($store_statistics =~ /\btsv\b/ or $output_statistics =~ /\btsv\b/) {
    $stats_tsv = get_stats_tsv();
  }
}


# print the input text with marked sources in the selected output format to STDOUT
my $output = get_output($output_format);

if (!$output_statistics) { # statistics should not be a part of output
  print $output;
}
else { # statistics should be a part of output, i.e. output will be JSON with items: data (in output-format) and stats_html and/or stats_tsv
  my $json_data = {
       data  => $output,
     };
  if ($output_statistics =~ /\bhtml\b/) {
    $json_data->{stats_html} = $stats_html;
  }
  if ($output_statistics =~ /\btsv\b/) {
    $json_data->{stats_tsv} = $stats_tsv;
  }

  # Encode the Perl data structure into a JSON string
  # print STDERR "JSON data with statistics: " . Dumper($json_data);
  my $json_string = encode_json($json_data);
  # Print the JSON string to STDOUT
  print $json_string;  
}

if ($store_format) { # # log the input text with marked sources in the given format in a file
  $output = get_output($store_format) if $store_format ne $output_format;
  my $output_file = basename($input_file); # the file name without the path
  open(OUT, '>:encoding(utf8)', "$script_dir/log/$output_file.$store_format") or die "Cannot open file '$script_dir/log/$output_file.$store_format' for writing: $!";
  print OUT $output;
  close(OUT);
}

if ($store_statistics) { # log statistics about the detection to a html and/or tsv file
  my $file_name = basename($input_file); # the file name without the path
  foreach my $format (split(',', $store_statistics)) {
    open(OUT, '>:encoding(utf8)', "$script_dir/log/$file_name.stats.$format") or die "Cannot open file '$script_dir/log/$file_name.stats.$format' for writing: $!";
    print OUT $format eq 'html' ? $stats_html : $stats_tsv;
    close(OUT);
  }
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
Otherwise returns:
 - the expected parent of the claim (special case: it returns the preposition node in case of PREP ('podle', 'dle'))
 - and all nodes belonging to the citation phrase.

=cut


sub check_constraint {
  my ($node, $lemma, $constraint) = @_;

  mylog(0, "check_constraint: checking constraint '$constraint'\n");

  my $claim_parent;
  my @phrase_nodes = ($node);

  my $deprel = attr($node, 'deprel') // '';
  
  my $xpostag = attr($node, 'xpostag') // '';
  if ($constraint and $constraint eq 'PREP' and $xpostag =~ /^R/) {
    mylog(0, " - PREP, constraint OK\n");
    return ($node, @phrase_nodes);
  }
 
  # check morphological properties of the node:
  my $feats = attr($node, 'feats') // '';
  mylog(0, "check_constraint: checking morphology: feats='$feats'\n");
  if ($feats =~ /\bVerbForm=Inf\b/) { # We do not want infinitive
    mylog(0, " - we do not want infinitive, returning undef\n");
    return undef;
  }
  mylog(0, " - morphology OK\n");
  #return undef if $feats =~ /\bPolarity=Neg\b/; # We do not want negation

  if ($constraint eq 'NoConstraint') { # no constraint, i.e. trivially matched
    mylog(0, " - no constraint, i.e. trivially matched\n");
    return ($node, @phrase_nodes);
  }

  # now check the constraints:
  my @children = $node->getAllChildren;
  my @required_children_forms_lc = split('\|', $constraint); # get the individul required children (possibly with '!')
  foreach my $required_child_form_lc (@required_children_forms_lc) {
    mylog(0, " - checking if '$required_child_form_lc' is present/fulfilled\n");
    if ($required_child_form_lc eq 'POSTPOS') { # the attribution is in post position, i.e. the claim is the parent (i.e. a child of the grandparent)
      if ($deprel ne 'conj') {
        mylog(0, " - constraint POSTPOS but deprel is not 'conj'; returning undef\n");
        return undef;
      }
      my @cc_children = grep {attr($_, 'deprel') eq 'cc'} @children;
      if (@cc_children) {
        mylog(0, " - constraint POSTPOS but 'cc' children; returning undef\n");
        return undef;
	# Still, there remain homonymous expressions such as: (Politici jsou k místním kritičtí.) Soudci se jich bojí, odsuzují místní obyvatele. There is no way telling if it is a coordintation with a common subject or if it is a post-position with 'Politici' being subject of the second clause.
      }
      # check the order
      my $phrase_ord = attr($node, 'ord');
      my $parent_ord = attr($node->getParent, 'ord');
      if ($phrase_ord < $parent_ord) {
        mylog(0, " - constraint POSTPOS but parent is to the right; returning undef\n");
        return undef;
      }
      mylog(0, " - constraint POSTPOS, setting the grandparent as the parent of claim\n");
      $claim_parent = $node->getParent->getParent;
    }
    elsif ($required_child_form_lc eq 'ANTEPOS') { # the attribution is in ante position, i.e. the claim is the parent (i.e. a child of the grandparent)
      if ($deprel ne 'csubj' and $deprel ne 'csubj:pass') {
        mylog(0, " - constraint ANTEPOS but deprel is not 'csubj' or 'csubj:pass'; returning undef\n");
        return undef;
      }
      # check the order
      my $phrase_ord = attr($node, 'ord');
      my $parent_ord = attr($node->getParent, 'ord');
      if ($phrase_ord > $parent_ord) {
        mylog(0, " - constraint ANTEPOS but parent is to the left; returning undef\n");
        return undef;
      }
      mylog(0, " - constraint ANTEPOS, setting the grandparent as the parent of claim\n");
      $claim_parent = $node->getParent->getParent;
    }
    elsif ($required_child_form_lc =~ /^(\S+)-(\S+)$/) { # a hierarchy required (e.g. 'za-to' in 'má za to')
      my ($child_form_lc, $grandchild_form_lc) = ($1, $2);
      my $required_child_is_claim_parent = $child_form_lc =~ /!/;
      $child_form_lc =~ s/!//;      
      my @good_children = grep {$child_form_lc eq lc(attr($_, 'form'))} @children;
      if (!@good_children) {
        mylog(0, " - constraint not matched (no good children), returning undef\n");
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
        mylog(0, " - constraint not matched (no good grandchildren), returning undef\n");
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
        mylog(0, " - constraint not matched (no good children), returning undef\n");
        return undef;
      }
      my $good_child = $good_children[0]; # I doubt there might be more
      push(@phrase_nodes, $good_child);
      if ($required_child_is_claim_parent) { # it is also the expected parent of the claim
        $claim_parent = $good_child if !$claim_parent;
      }
    }
  }
  mylog(0, " - OK, constraint matched.\n");
  if (!$claim_parent) { # no special claim parent was set
    $claim_parent = $node;
  }
  return ($claim_parent, @phrase_nodes);
}


=item is_finite

Checks if the given node represents a finite verb or something similer, e.g. "ano", "ne".

=cut

sub is_finite {
  my $node = shift;
  my $VerbForm = get_feat_value($node, 'VerbForm') // '';
  my $upostag = attr($node, 'upostag') // '';
  my $form = attr($node, 'form') // '';
  mylog(0, "is_finite: form = '$form', upostag = '$upostag', VerbForm = '$VerbForm'\n");
  if ($upostag eq 'VERB' and $VerbForm ne 'Inf') {
    mylog(0, "is_finite: a finite verb\n");
    return 1;
  }
  # It may also be a copula ("je konzervativní")
  my @cop_children = grep {attr($_, 'deprel') eq 'cop'} $node->getAllChildren;
  if (@cop_children) {
    if (is_finite($cop_children[0])) {
      mylog(0, "is_finite: a copula\n");
      return 1;
    }
  }
  # It may be a complex verb ("bude potřebovat")
  my @finverb_children = grep {get_feat_value($_, 'VerbForm') and get_feat_value($_, 'VerbForm') ne 'Inf'} $node->getAllChildren;
  if ($upostag eq 'VERB' and @finverb_children) {
    if (is_finite($finverb_children[0])) {
      mylog(0, "is_finite: a complex verb form\n");
      return 1;
    }
  }  
  # It may be a reference to a verbal phrase, such as "potvrzuje to i ..." or "jeho slova potvrzuje i ..."
  my $form = attr($node, 'form');
  my $deprel = attr($node, 'deprel');
  if ($form =~ /^(slova|to)$/ and $deprel eq 'obj') { # tady bylo i 'tom', ale proč?
    mylog(0, "is_finite: a reference object such as 'to'\n");
    return 1; # musí to být 'obj', aby se vyloučilo např. "na to odpověděl..."
  }
  # It may be a yes/no response, e.g. "ano" or "on ne" (deprel = dep)
  if ($form =~ /^(ano|ne)$/) {
    mylog(0, "is_finite: ano/ne'\n");
    return 1;
  }
  my $deprel = attr($node, 'deprel') // '';
  if ($deprel eq 'dep') {
    my @ano_ne_children = grep {attr($_, 'lemma') and attr($_, 'lemma') =~ /(ano|ne)/} $node->getAllChildren;
    if (@ano_ne_children) {
      mylog(0, "is_finite: ano/ne grandchild'\n");
      return 1;
    }
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
      mylog(0, " - has_finite_verb_object: case 'podle' OK (a claim found)\n");
      return 1;
    }
    mylog(0, " - has_finite_verb_object: case 'podle' - no claim found\n");
    return 0;
  }
  # Second, let us search for a claim among the children
  my @finite_verb_object_children = grep {attr($_, 'deprel') =~ /^(obj|iobj|ccomp|xcomp|obl:arg|acl|root|csubj:pass|dep)$/}
                                    grep {is_finite($_)}
                                    $node->getAllChildren;
  if (@finite_verb_object_children) {
    mylog(0, " - has_finite_verb_object: OK (a finite claim found among children: " . attr($finite_verb_object_children[0], 'form') . ")\n");
    return 1;
  }
  my @clausal_object_children = grep {attr($_, 'deprel') =~ /^(ccomp)$/}
                                    $node->getAllChildren;
  if (@clausal_object_children) {
    mylog(0, " - has_finite_verb_object: OK (a clausal claim found among children: " . attr($clausal_object_children[0], 'form') . ")\n");
    return 1;
  }

  # Third, the claim might also be in a parataxis position ("Jak už vědci uvedli při prvním kole vykopávek, jde pro ně o záhadu.")
  if (attr($node, 'deprel') and attr($node, 'deprel') eq 'parataxis') {
    if (is_finite($parent)) {
      mylog(0, " - has_finite_verb_object: OK (a claim found in a parataxis position): " . attr($parent, 'form') . ")\n");
      return 1;
    }
  }
  # Fourth, "informovat o (cokoli)" or "přinesl zprávu o (cokoli), e.g. "O rozsudku informoval ..." or "Zprávu o zmizení XY přinesl ..."
  if ($lemma eq 'informovat' or $lemma eq 'zpráva') {
    my @children_with_o = grep {has_child_with_lemma($_, 'o')}
                          $node->getAllChildren;
    if (@children_with_o) {
      mylog(0, " - has_finite_verb_object: case 'o' OK (a claim found)\n");
      return 1;
    }    
  }
  # Fifth, "Čest jeho památce!, uvedl městys na facebooku k úmrtí"
  my @children_with_excl = grep {has_child_with_lemma($_, '!')}
                           $node->getAllChildren;
  if (@children_with_excl) {
    mylog(0, " - has_finite_verb_object: case '!' OK (a claim found)\n");
    return 1;
  }    
  
  # Je potřeba vyřešit "Vyplývá to z údajů na internetových stránkách České národní banky.", kde claim je subject ("to") a source je obl:arg (z údajů), soubor doc-8359658.xml.txt.conll
  
  mylog(0, " - has_finite_verb_object: no claim found\n");
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

Uses global hashes %surname2class and %surname2full to keep track of surnames that have already been classified (possibly as a part of a longer (full) source, e.g. "mluvčí cestovní kanceláře Jiří Nekvapil"), so that they are not misclassified later when mentioned just by themselves (e.g., just "Nekvapil").

Fills global hashes to keep info for statistics:
 - %source2count;
 - %source2class;
 - %class2count;
 - %source2claims;


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
  my ($root, $should_be_counted, $claim_parent, @whole_source_nodes) = @_;

  my $surname = undef; # We will set this if there is a surname found among the source nodes
  
  mylog(0, "guess_source_type: Entered the function; should_be_counted=$should_be_counted, claim_parent=" . (attr($claim_parent, 'form') // '') . ", source nodes: '" . join(' ', map {attr($_, 'form')} @whole_source_nodes) . "'\n");

  my @whole_source_nodes_dfo = sort_nodes_dfo(@whole_source_nodes);
  my $whole_source_nodes_count = scalar(@whole_source_nodes_dfo);
  my $source_root = $whole_source_nodes_dfo[0];
  my $source_root_NE_marks = ''; # will be set in the following cycle
  my $source_root_lemma = attr($source_root, 'lemma') // '';

  my $claim_parent_form = lc(attr($claim_parent, 'form'));
  if ($claim_parent_form eq 'podle' or $claim_parent_form eq 'dle') { # special handling of 'podle' and 'dle'
    $claim_parent = $claim_parent->getParent->getParent;
  }
  my @claim_nodes = descendants($claim_parent, {include_root => 1});
  my $claim_text = text(\@claim_nodes);
  
  # Collect NameTag marks for all source nodes
  my @source_named_entity_marks = ();
  foreach my $source_node (@whole_source_nodes_dfo) {
    my $named_entity_marks = get_NameTag_and_extra_NE_marks($source_node, $whole_source_nodes_count);
    mylog(0, "guess_source_type: node=" . attr($source_node, 'lemma') . ", named_entity_marks=$named_entity_marks\n");
    next if !$named_entity_marks;
    # mylog(0, "guess_source_type: " . attr($source_node, 'lemma') . ": '$named_entity_marks'\n");
    if ($source_node eq $source_root) {
      $source_root_NE_marks = $named_entity_marks;
    }
    if ($named_entity_marks =~ /\bps\b/) { # a surname - check if we already know the class
      my $lemma = attr($source_node, 'lemma') // '';
      my $class = $surname2class{lc($lemma)};

      if ($class) {
        mylog(0, "Class for surname $lemma already determined before: $class\n");
        my $antecedent = $surname2full{lc($lemma)};
        if ($should_be_counted) {
          $class2count{$class}++;
          $source2count{$antecedent}++;
          push @{ $source2claims{$antecedent} ||= [] }, $claim_text;
        }

        # storing the antecedent for pronouns
        my ($gender, $number) = get_gender_number_of_animate_source($source_node);
        if ($gender and $number) {
          mylog(0, "Storing the class '$class' and the full source '$antecedent' for resolving pronouns (gender $gender, number $number)\n");
          $last_gender_number2class{$gender . '_' . $number} = $class;
          $last_gender_number2full{$gender . '_' . $number} = $antecedent;
        }
        
        if ($add_antecedent) {
          if ($output_format eq 'html') {
            $class .= '_<span class="source-antecedent">' . $antecedent . '</span>';
          }
          else {
            $class .= '_' . $antecedent;
          }
        }
        return $class;
      }
      else { # first mention of the surname - let us keep it and later store it in %surname2class
        $surname = $lemma;
      }
      
    }
    push(@source_named_entity_marks, $named_entity_marks);
  }
  
  my $joined = '~' . join('~', @source_named_entity_marks);

  # maybe we will keep info about this source (if it contains nouns and has been recognized also by NameTag)  
  my @a_source_noun_nodes = grep {attr($_, 'upostag') eq 'NOUN'} @whole_source_nodes_dfo;
  my @a_source_noun_lemmas = map {attr($_, 'lemma')} @a_source_noun_nodes;
  my $source_noun_lemmas = join(' ', @a_source_noun_lemmas);

  if ($joined eq '~') { # no NameTag class assigned to the source
    mylog(0, "A source without a NameTag mark\n");
    # let us have a look if we can find a better specified (longer) antecedent for the source
    # (1) if it is a pronoun (e.g., "Podle něj")
    # hashes for keeping classes and full expressions for a given gender and number of sources containing Animacy=Anim
    # to be used if a personal pronoun is found as a source
    # my %last_gender_number2class;
    # my %last_gender_number2full; # the original (full) mention of the source
    if (scalar(@whole_source_nodes_dfo) eq 1) { # a single-word source
      mylog(0, "A single-word source\n");
      my $source_node = $whole_source_nodes_dfo[0];
      my $lemma = attr($source_node, 'lemma');
      my $upostag = attr($source_node, 'upostag');
      my $prontype = get_feat_value($source_node, 'PronType') // '';
      if (($upostag eq 'PRON' and $prontype eq 'Prs') or $lemma eq 'ten') { # a personal pronoun or lemma 'ten'
        mylog(0, "A personal pronoun or lemma 'ten'\n");
        # les us try to find an antecedent with the same Gender and Number among last antecedents with Animacy=Anim
        my $gender = get_feat_value($source_node, 'Gender') // '';
        my $number = get_feat_value($source_node, 'Number') // '';
        mylog(0, "Gender $gender and Number $number\n");
        if ($gender and $number) {
          foreach my $one_gender (split(',', $gender)) { # Gender of pronouns may be, e.g., 'Masc,Neut'
            if ($last_gender_number2class{$one_gender . '_' . $number}) {
              my $class = $last_gender_number2class{$one_gender . '_' . $number};
              my $antecedent = $last_gender_number2full{$one_gender . '_' . $number};
              mylog(0, "Class for a $one_gender $number pronoun already determined before for '$antecedent': $class\n");
              if ($should_be_counted) {
                $class2count{$class}++;
                $source2count{$antecedent}++;
                push @{ $source2claims{$antecedent} ||= [] }, $claim_text;
              }
              if ($add_antecedent) {
                $class .= '_' . $antecedent;
              }
              return $class;        
            }
          }
        }
      }
    }
    
    # (2) if it contains a noun that was already used in some longer source which had a NameTag class assigned (e.g., "britský list" -> "britský bulvární list The Daily Mirror"
    # hashes to keep already seen nouns (not surnames)
    # e.g.: for "britský list" -> "britský bulvární list The Daily Mirror", the hashes would contain:
    #       'list Daily Mirror' => 'unofficial'
    #       'list Daily Mirror' => 'britský bulvární list The Daily Mirror'
    # my %noun_lemmas2class;
    # my %noun_lemmas2full; # the original (full) mention of the source

    if (@a_source_noun_lemmas) { # at least one noun in the source
      my $previous_noun_lemmas = get_noun_lemmas(@a_source_noun_lemmas);
      if ($previous_noun_lemmas) { # found!
        my $class = $noun_lemmas2class{$previous_noun_lemmas};
        my $antecedent = $noun_lemmas2full{$previous_noun_lemmas};
        mylog(0, "Class for a source with the same nouns ($source_noun_lemmas) already determined before for '$antecedent': $class\n");
        if ($should_be_counted) {
          $class2count{$class}++;
          $source2count{$antecedent}++;
          push @{ $source2claims{$antecedent} ||= [] }, $claim_text;
        }
        if ($add_antecedent) {
          $class .= '_' . $antecedent;
        }
        return $class;        
      }
    }
  }
  
  my $class = 'anonymous-partial'; # default

  # mylog(0, "guess_source_type: whole source joined marks='$joined', source root marks='$source_root_NE_marks'\n");
  if ($source_root_NE_marks =~ /\bgc\b/) { # gc - state
    $class = 'official-political';
  }
  elsif ($source_root_lemma eq 'firma') {
    $class = 'official-non-political';
  }
  elsif ($joined =~ /~sp/) { # sp - source anonymous-partial (fake NE class)
    $class = 'anonymous-partial';
  }
  elsif ($joined =~ /~io/) { # io - government/political inst.
    $class = 'official-political';
  }
  elsif ($joined =~ /~i/) { # i - Institutions
    $class = 'official-non-political';
  }
  elsif ($joined =~ /~p/) { # p - Personal names
    $class = 'unofficial';
  }
  elsif ($joined =~ /~m[ns]/) { # mn - periodical, ms - radio and TV stations
    $class = 'unofficial';
  }
  elsif ($joined =~ /~sa/) { # sa - source anonymous (fake NE class)
    $class = 'anonymous';
  }
  elsif ($joined =~ /~su/) { # su - source unofficial (fake NE class)
    $class = 'unofficial';
  }

  my $full = get_source_base_form(@whole_source_nodes);

  if ($surname) { # first mention of the surname (possibly in a longer (full) source)
    mylog(0, "guess_source_type: There was a yet unseen surname ($surname) among the source nodes, let us remember it and its class ($class)\n");
    $surname2class{lc($surname)} = $class;
    $surname2full{lc($surname)} = $full;
    $source2class{$full} = $class;
    if ($should_be_counted) {
      $source2count{$full}++; # =1 would do the same
      $class2count{$class}++;
      push @{ $source2claims{$full} ||= [] }, $claim_text;
    }
    
    # storing the antecedent for pronouns
    my ($gender, $number) = get_gender_number_of_animate_source(@whole_source_nodes);
    if ($gender and $number) {
      mylog(0, "guess_source_type: Storing the class '$class' and the full source '$full' for resolving pronouns (gender $gender, number $number)\n");
      $last_gender_number2class{$gender . '_' . $number} = $class;
      $last_gender_number2full{$gender . '_' . $number} = $full;
    }
    
  }
  
  # there was a NameTag mark for some of the source nodes
  elsif ($joined ne '~' and $source_noun_lemmas and not $noun_lemmas2class{$source_noun_lemmas}) { # if the source contains nouns (but not surnames) and has been recognized also by NameTag and we have not yet set this
    mylog(0, "guess_source_type: There was a NameTag mark for some of the source nodes and the source contains a noun\n");
    $noun_lemmas2class{$source_noun_lemmas} = $class;
    $noun_lemmas2full{$source_noun_lemmas} = $full;
    $source2class{$full} = $class; # it may have been set before but never mind
    if ($should_be_counted) {
      $source2count{$full}++;
      $class2count{$class}++;
      push @{ $source2claims{$full} ||= [] }, $claim_text;
    }
    # storing the antecedent for pronouns
    my ($gender, $number) = get_gender_number_of_animate_source(@whole_source_nodes);
    if ($gender and $number) {
      mylog(0, "guess_source_type: Storing the class '$class' and the full source '$full' for resolving pronouns (gender $gender, number $number)\n");
      $last_gender_number2class{$gender . '_' . $number} = $class;
      $last_gender_number2full{$gender . '_' . $number} = $full;
    }

  }
  else {
    $source2class{$full} = $class;
    if ($should_be_counted) {
      $source2count{$full}++;
      $class2count{$class}++;
      push @{ $source2claims{$full} ||= [] }, $claim_text;
    }
  }

  # mylog(0, "guess_source_type: $class\n");
  if ($add_NE) {
    $class = "$joined:$class";
  }
  return "$class";
}


sub get_NameTag_marks {
  my $node = shift;
  my $ne = get_misc_value($node, 'NE') // '';
  if ($ne) {
    my @values = $ne =~ /([A-Za-z][a-z_]?)_[0-9]+/g; # get an array of the marks
    my $marks = join '~', @values;
    # mylog(0, "get_NameTag_marks: $ne -> $marks\n");
    return $marks;
  }
  return '';
}


sub get_NameTag_and_extra_NE_marks {
  my ($node, $count_of_nodes) = @_;
  my $named_entity_marks = get_NameTag_marks($node);
  my $named_entity_extra_marks = get_extra_NE_for_node($node, $count_of_nodes);
  if ($named_entity_marks and $named_entity_extra_marks) {
    return $named_entity_marks . '~' . $named_entity_extra_marks;
  }

  if ($named_entity_marks) {
    return $named_entity_marks;
  }

  if ($named_entity_extra_marks) {
    return $named_entity_extra_marks;
  }
  
  return '';
}


sub get_extra_NE_for_node {
  my ($node, $number_of_nodes) = @_;
  my $lemma = attr($node, 'lemma');
  my $form = attr($node, 'form');
  if ($lemma eq '#Gen') {
    # mylog(0, "get_extra_NE_for_node: #Gen\n";
    return 'sa'; # "source - anonymous"
  }
  if ($lemma =~ /^(mluvčí|velitel(ka)?|ředitel(ka)?|vedoucí|šéf(ka)?|soudce|soudkyně|soud|obžaloba|obhajoba|obhájce|obhájkyně|prokurátor(ka)?|obžalovaný|obžalovaná)$/) {
    # mylog(0, "get_extra_NE_for_node: found 'mluvčí etc.'\n");
    return 'im'; # "institution - mluvčí"
  }
  if ($number_of_nodes == 1 and $keywords_single_anonymous{$lemma}) {
    return 'sa' # "source - anonymous"
  }
  if ($keywords_anonymous{$lemma}) {
    return 'sa' # "source - anonymous"
  }
  if ($keywords_anonymous_partial{$lemma}) {
    return 'sp' # "source - anonymous-partial"
  }
  if ($keywords_unofficial{$lemma}) {
    return 'su' # "source - unofficial"
  }

  if (is_state($node)) { # e.g., Čína
    return 'gc'; # "states"
  }

  if ($lemma =~ /^premiér(ka)?$/) {
    return 'io'; # "institution - goverment, political"
  }
  if ($lemma =~ /^vláda$/) {
    return 'io'; # "institution - goverment, political"
  }
  if ($lemma =~ /^poslan(ec|kyně)$/) {
    return 'io'; # "institution - goverment, political"
  }
  if ($lemma =~ /^senátor(ka)?$/) {
    return 'io'; # "institution - goverment, political"
  }
  if ($lemma =~ /^ministr(yně)?$/) {
    return 'io'; # "institution - goverment, political"
  }
  if ($lemma eq 'magistrát') {
    return 'io'; # "institution - goverment, political"
  }
  if ($lemma eq 'radní') {
    return 'io'; # "institution - goverment, political"
  }
  if ($lemma =~ /^(místo)?starost(k)?a/) {
    return 'io'; # "institution - goverment, political"
  }
  if ($lemma =~ /^armáda$/) {
    return 'io'; # "institution - goverment, political"
  }
  if ($lemma =~ /^ministerstvo$/) { # with small 'm'
    return 'io'; # "institution - goverment, political"
  }
  
  my @children = $node->getAllChildren;
  my @children_lemmas = map {attr($_, 'lemma')} @children;
  
  if ($lemma =~ /^(místo)?předsed(a|kyně)$/) {
    if (grep {/ministersk[ýá]/} @children_lemmas or grep {/^(vláda|parlament|sněmovna|senát)$/} @children_lemmas) {
      return 'io'; # "institution - goverment, political"
    }
    else {
      return 'im'; # "institution - mluvčí"
    }
  }
  
  if ($lemma =~ /^prezident(ka)?$/) {
    if (grep {/^(republika|stát|země)$/} @children_lemmas) {
      return 'io'; # "institution - goverment, political"
    }
    if (grep {is_state($_)} @children) {
      return 'io'; # "institution - goverment, political"
    }
    return 'im'; # "institution - mluvčí"
  }

  my @children_forms = map {attr($_, 'form')} @children;
  if ($lemma =~ /^dům$/) {
    if (grep {/^Bíl[ýé]/} @children_forms) {
      return 'io'; # "institution - goverment, political"
    }
  }
}

sub is_state {
  my $node = shift;
  my $lemma = attr($node, 'lemma');
  if ($states{$lemma}) {
    return 1;
  }
  if (lc($lemma) eq 'republika') {
    return 1;
  }
  # two- and more-word countries should˚ be solved here...
  return 0;
}

=item get_gender_number_of_animate_source

Given all source nodes, it finds its root and checks if it has a number, a gender and (Animacy="Anim" or gender="Fem"). If so, returns the gender and number.´

=cut

sub get_gender_number_of_animate_source {
  my @source_nodes = @_;
  my @source_nodes_sorted_dfo = sort_nodes_dfo(@source_nodes);

  my $source_root = $source_nodes_sorted_dfo[0];
  my $animacy = get_feat_value($source_root, 'Animacy') // '';
  my $gender = get_feat_value($source_root, 'Gender') // '';
  my $number = get_feat_value($source_root, 'Number') // '';
  if ($animacy eq 'Anim' and $gender and $number) {
    return ($gender, $number);
  }
  elsif ($gender and $number and $gender eq "Fem") {
    return ($gender, $number);
  }
  
=item
  
  foreach my $node (@source_nodes) {
    my $animacy = get_feat_value($node, 'Animacy') // '';
    my $gender = get_feat_value($node, 'Gender') // '';
    my $number = get_feat_value($node, 'Number') // '';
    if ($animacy eq 'Anim' and $gender and $number) {
      return ($gender, $number);
    }
    elsif ($gender and $number and $gender eq "Fem") {
      return ($gender, $number);
    }
  }
  
=cut

  return undef;
}


sub sort_nodes_dfo {
  my @nodes = @_;
  my @sorted = sort {compare_dfo($a, $b)} @nodes;
  return @sorted;
}

sub compare_dfo {
  my ($n1, $n2) = @_;
  if ($n1->getDepth != $n2->getDepth) {
    return ($n1->getDepth <=> $n2->getDepth);
  }
  return (attr($n1, 'ord') <=> attr($n2, 'ord')); 
}


=item get_noun_lemmas

Give an array of noun lemmas, it finds the first key in the hash %noun_lemmas2class that contains at least the same noun lemmas

# hashes to keep already seen nouns (not surnames)
# e.g.: for "britský list" -> "britský bulvární list The Daily Mirror", the hashes would contain:
#       'list Daily Mirror' => 'unofficial'
#       'list Daily Mirror' => 'britský bulvární list The Daily Mirror'
# my %noun_lemmas2class;
# my %noun_lemmas2full; # the original (full) mention of the source
    
=cut

sub get_noun_lemmas {
  my @noun_lemmas = @_;
  my $noun_lemmas_count = scalar(@noun_lemmas);
  foreach my $h_key (keys(%noun_lemmas2class)) { # for each key in the hash
    my @present_lemmas = grep {$h_key =~ /\b$_\b/} @noun_lemmas;
    if (scalar(@present_lemmas) eq $noun_lemmas_count) { # all lemmas present
      return $h_key;
    }
  }
}


=item get_misc_value

Returns a value of the given property from the misc attribute. Or undef.

=cut

sub get_misc_value {
  my ($node, $property) = @_;
  my $misc = attr($node, 'misc') // '';
  # mylog(0, "get_misc_value: misc=$misc\n");
  if ($misc =~ /$property=([^|]+)/) {
    my $value = $1;
    # mylog(0, "get_misc_value: $property=$value\n");
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
  # mylog(0, "get_feat_value: feats=$feats\n");
  if ($feats =~ /$property=([^|]+)/) {
    my $value = $1;
    # mylog(0, "get_feat_value: $property=$value\n");
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
    $output .= <<END_OUTPUT_HEAD;
<head>
  <style>
        /* source classes colours */
        .source-a {
            color: $color_a;
        }
        .source-ap {
            color: $color_ap;
        }
        .source-u {
            color: $color_u;
        }
        .source-onp {
            color: $color_onp;
        }
        .source-op {
            color: $color_op;
        }
        .source-text {
            color: $color_source;
            text-decoration: underline;
            font-weight: bold
        }
        .source-antecedent {
            color: $color_source_antecedent;
        }
        .source-brackets {
            color: $color_source_brackets;
            vertical-align: sub;
        }
        .phrase-text {
            color: $color_phrase;
            font-weight: bold
        }
  </style>
</head>
END_OUTPUT_HEAD
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
  
  foreach my $root (@trees) {
  
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
            $output .= '<br/>';
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
      my $start = attr($node, 'start') // -1; # range missing e.g. when "kdyby" is parsed as "když by"
      my $end = attr($node, 'end') // -1;
      
      if ($start == -1 or $end == -1) {
        mylog(0,"Problém s atributy start ($start) či end ($end) u uzlu '$form'!\n");
      }
      
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
          $span_start = $format eq 'html' ? '<span class="source-text">' : '>>';
          $inside_SD = 1;
          $SD_type = 'S';        
          my $source_type = $h_source_range2type{$source_range};
          if ($source_type) {
            $SD_subtype = get_short_class($source_type);
          }
        }
        if ($source_range =~ /:$end\b/) { # last token in one of contiguous parts of the source
          $span_end = $format eq 'html' ? '</span>' : '<<';
          $end_of_SD = 1;
        }
        if ($source_range =~ /:$end$/) { # last token of the source
          my $source_type = $h_source_range2type{$source_range};
          if ($source_type) {
            my $type_span_class = 'source-a' if ($source_type =~ /anonymous/);
            $type_span_class = 'source-ap' if ($source_type =~ /anonymous-partial/);
            $type_span_class = 'source-u' if ($source_type =~ /unofficial/);
            $type_span_class = 'source-onp' if ($source_type =~ /official-non-political/);
            $type_span_class = 'source-op' if ($source_type =~ /official-political/);
            $type_span = $format eq 'html' ? "<span class=\"source-brackets\">[<span class=\"$type_span_class\">$source_type</span>]</span>" : "[$source_type]";
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
          $span_start = $format eq 'html' ? '<span class="phrase-text">' : '@';
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


sub get_short_class {
  my $class = shift;
  return 'ap' if $class =~ /anonymous-partial/;
  return 'a' if $class =~ /anonymous/;
  return 'u' if $class =~ /unofficial/;
  return 'op' if $class =~ /official-political/;
  return 'onp' if $class =~ /official-non-political/;
}

=item get_stats_html

Produces an html document with statistics about the detection, using info from these variables and hashes:
 - $sentences_count;
 - $tokens_count;
 - $processing_time;
 - $processing_time_udpipe;
 - $processing_time_nametag;
 - %source2count;
 - %source2class;
 - %class2count;
 - %source2claims;

=cut

sub get_stats_html {
  my $stats = "<html>\n";
  $stats .= <<END_HEAD;
<head>
  <style>
        .bar {
            display: flex;
            justify-content: space-between;
            align-items: flex-end; /* Zarovnání sloupců na spodní stranu */
            width: 250px; /* Šířka grafu */
            height: 130px; /* Výška grafu */
            margin-top: 10px
        }

        .bar-segment {
            width: 40px; /* Šířka sloupce */
            background-color: blue; /* Základní barva sloupce */
        }

        /* Bar colours */
        .bar-a {
            background-color: $color_a;
        }

        .bar-ap {
            background-color: $color_ap;
        }

        .bar-u {
            background-color: $color_u;
        }

        .bar-onp {
            background-color: $color_onp;
        }

        .bar-op {
            background-color: $color_op;
        }

        .bar-label {
          width: 46px;
          margin: 0px;
          padding: 0px;
          display: inline-block; /* Nutné, aby bylo možné nastavit šířku */
          overflow: hidden; /* Skryje přebytečný text, pokud je obsah delší než šířka */
          text-align: center;
          margin-top: 10px;
        }
    h3 {
      margin-top: 5px;
    }
    table {
      border-collapse: collapse;
    }
    table, th, td {
      border: 1px solid black;
    }
    th, td {
      text-align: left;
      padding-left: 2mm;
      padding-right: 2mm;
    }
    td:last-child {
      text-align: right;
      padding-right: 20px;
    }
  </style>
</head>
END_HEAD

  my $rounded_time = sprintf("%.1f", $processing_time);
  my $rounded_time_udpipe = sprintf("%.1f", $processing_time_udpipe);
  my $rounded_time_nametag = sprintf("%.1f", $processing_time_nametag);
 
  $stats .= "<body>\n";

  if ($ui_language and $ui_language eq 'cs') {

    $stats .= "<h3>SouDeC verze $VER_cs</h3>\n";
    $stats .= "<p>Počet vět: $sentences_count\n";
    $stats .= "<br/>Počet tokenů: $tokens_count\n";
    $stats .= "<br/>Doba zpracování: $rounded_time s\n";
    $stats .= "<br/> &nbsp; - UDPipe: $rounded_time_udpipe s\n";
    $stats .= "<br/> &nbsp; - NameTag: $rounded_time_nametag s\n";
    $stats .= "</p>\n";

  }
  else {

    $stats .= "<h3>SouDeC version $VER_en</h3>\n";
    $stats .= "<p>Number of sentences: $sentences_count\n";
    $stats .= "<br/>Number of tokens: $tokens_count\n";
    $stats .= "<br/>Processing time: $rounded_time s\n";
    $stats .= "<br/> &nbsp; - UDPipe: $rounded_time_udpipe s\n";
    $stats .= "<br/> &nbsp; - NameTag: $rounded_time_nametag s\n";
    $stats .= "</p>\n";

  }

  $stats .= "<p>\n";
  $stats .= "<table border=0><tr><td>\n";

  # table with distribution of classes
  $stats .= "<table>\n";
  if ($ui_language and $ui_language eq 'cs') {
    $stats .= "<tr><th>Třída</th><th>Počet</th></tr>\n";
  }
  else {
    $stats .= "<tr><th>Class</th><th>Count</th></tr>\n";
  }
  foreach my $class (sort {$class2count{$b} <=> $class2count{$a}} keys(%class2count)) {
    $stats .= "<tr><td>$class</td><td>$class2count{$class}</td></tr>\n";
  }
  $stats .= "</table>\n";
  
  $stats .= "</td><td style=\"padding-left: 20px;\">\n";

  # chart creation
  my @categories = qw(a ap u onp op);
  my %hdata = (
      'a'  => $class2count{'anonymous'} // 0,
      'ap' => $class2count{'anonymous-partial'} // 0,
      'u'  => $class2count{'unofficial'} // 0,
      'onp'  => $class2count{'official-non-political'} // 0,
      'op' => $class2count{'official-political'} // 0
  );
  my @values = map {$hdata{$_}} @categories;
  my $max_value = max(@values);
  my @percentages = map {100 * $_ / ($max_value+0.001)} @values; # to avoid division by 0
  $stats .= "  <div class=\"bar\">\n";
  $stats .= "      <div class=\"bar-segment bar-a\" style=\"height: $percentages[0]%;\"></div>\n";
  $stats .= "      <div class=\"bar-segment bar-ap\" style=\"height: $percentages[1]%;\"></div>\n";
  $stats .= "      <div class=\"bar-segment bar-u\" style=\"height: $percentages[2]%;\"></div>\n";
  $stats .= "      <div class=\"bar-segment bar-onp\" style=\"height: $percentages[3]%;\"></div>\n";
  $stats .= "      <div class=\"bar-segment bar-op\" style=\"height: $percentages[4]%;\"></div>\n";
  $stats .= "  </div>\n";
  # nadpisy sloupců
  $stats .= "  <div>\n";
  $stats .= "  <span class=\"bar-label\">a</span>\n";
  $stats .= "  <span class=\"bar-label\">ap</span>\n";
  $stats .= "  <span class=\"bar-label\">u</span>\n";
  $stats .= "  <span class=\"bar-label\">onp</span>\n";
  $stats .= "  <span class=\"bar-label\">op</span>\n";
  $stats .= "  </div>\n";

  $stats .= "</td></tr></table>\n";
  
  $stats .= "</p>\n";

  # table with distribution of sources and claims
  $stats .= "<p>\n";
  $stats .= "<table>\n";
  if ($ui_language and $ui_language eq 'cs') {
    $stats .= "<tr><th>Zdroj</th><th>Třída/Tvrzení</th><th>Počet</th></tr>\n";
  }
  else {
    $stats .= "<tr><th>Source</th><th>Class/Claim</th><th>Count</th></tr>\n";
  }
  foreach my $source (sort {$source2count{$b} <=> $source2count{$a}} grep {$source2count{$_}} keys(%source2class)) {
    $stats .= "<tr><td>$source</td><td>$source2class{$source}</td><td>$source2count{$source}</td></tr>\n";
    foreach my $claim (@{$source2claims{$source}}) {
      $stats .= "<tr><td></td><td>$claim</td><td></td></tr>\n";
    }
  }
  $stats .= "</table>\n";
  $stats .= "</p>\n";

  $stats .= "</body>\n";
  $stats .= "</html>\n";

  return $stats;
}


=item get_stats_html

Produces an html document with statistics about the detection, using info from these variables and hashes:
 - $sentences_count;
 - $tokens_count;
 - $processing_time;
 - $processing_time_udpipe;
 - $processing_time_nametag;
 - %source2count;
 - %source2class;
 - %class2count;
 - %source2claims;

=cut

sub get_stats_tsv {
  my $stats = '';

  my $rounded_time = sprintf("%.1f", $processing_time);
  my $rounded_time_udpipe = sprintf("%.1f", $processing_time_udpipe);
  my $rounded_time_nametag = sprintf("%.1f", $processing_time_nametag);

  # SouDeC and document info
  my $info_label = "SouDeC_doc_info_label\t"
           . "VERSION\t"
           . "FILENAME\t"
           . "#SENTENCES\t"
           . "#TOKENS\t"
           . "TOTAL TIME\t"
           . "UDPipe TIME\t"
           . "NameTag TIME\t";
  $stats .= "$info_label\n";
           
  my $file_name = basename($input_file); # the file name without the path
  my $info = "SouDeC_doc_info_item\t"
           . "$VER_en\t"
           . "$file_name\t"
           . "$sentences_count\t"
           . "$tokens_count\t"
           . "$rounded_time\t"
           . "$rounded_time_udpipe\t"
           . "$rounded_time_nametag\t";
  $stats .= "$info\n";

  # distribution of classes
  my $class_distr_label = "SouDeC_class_distr_label\t"
                        . join("\t", @source_type_classes);
  $stats .= "$class_distr_label\n";
  
  my $class_distr = "SouDeC_class_distr_item\t";
  foreach my $class (@source_type_classes) {
    $class_distr .= $class2count{$class} // 0;
    $class_distr .= "\t";
  }
  $stats .= "$class_distr\n";

  # distribution of sources (and claims)
  my $source_distr_label = "SouDeC_source_distr_label\t"
                         . "SOURCE\t"
                         . "CLASS/CLAIM\t"
                         . "COUNT";
  $stats .= "$source_distr_label\n";

  foreach my $source (sort {$source2count{$b} <=> $source2count{$a}} grep {$source2count{$_}} keys(%source2class)) {
    my $source_class_count = "SouDeC_source_distr_item\t"
                           . "$source\t"
                           . $source2class{$source} . "\t"
                           . $source2count{$source};
    $stats .= "$source_class_count\n";
    foreach my $claim (@{$source2claims{$source}}) {
      my $source_claim = "SouDeC_source_claim\t"
                       . "\t"
                       . "$claim";
      $stats .= "$source_claim\n";
    }
  }

  return $stats;
}


=item print_log_header

Prints header info for the document (name of the file, start of the html table)

=cut

sub print_log_header {
  mylog(0, "<!-- HTML-EVALUATION-EXACT --><h3>$input_file</h3>\n");
  mylog(0, "<!-- HTML-EVALUATION-PARTIAL --><h3>$input_file</h3>\n");
  if ($ann_file) {
    mylog(0, "<!-- HTML-EVALUATION-EXACT --><table><tr><th>type</th><th>automatic</th><th>class</th><th>manual</th><th>class</th><th>sentence</th></tr>\n");
    mylog(0, "<!-- HTML-EVALUATION-PARTIAL --><table><tr><th>type</th><th>automatic</th><th>class</th><th>manual</th><th>class</th><th>sentence</th></tr>\n");
  }
  else {
    mylog(0, "<!-- HTML-EVALUATION-EXACT --><p>No manual annotation provided.</p>\n");
    mylog(0, "<!-- HTML-EVALUATION-PARTIAL --><p>No manual annotation provided.</p>\n");
  }
}


=item print_log_tail

Prints tail info for the document (end of the html table)

=cut

sub print_log_tail {
  if ($ann_file) {
    mylog(0, "<!-- HTML-EVALUATION-EXACT --></table>\n");
    mylog(0, "<!-- HTML-EVALUATION-PARTIAL --></table>\n");
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
  mylog(0, "TSV-$type\t$auto_range\t$auto_text\t$ann_range\t$ann_text\t$sentence\n");
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
    $pure_auto_event =~ s/_.*$//; # get rid of the antecedent    
    my $hit = 'HIT'; # let us be optimistic ;-)
    if ($pure_auto_event ne $ann_event) { # disagreement on the source type
      $event_color = '#ef6109';
      $hit = 'MISS';
    }
    mylog(0, "TSV-SOURCETYPE-$exactness-$hit\t$auto_range\t$auto_text\t$auto_event\t$ann_range\t$ann_text\t$ann_event\t$sentence\n");
  }
  
  mylog(0, "<tr style=\"color: $color; background-color: $background\"><td>HTML-$type</td><td><b>$auto_text</b></td><td style=\"color: $event_color\">$auto_event</td><td><u>$ann_text</u></td><td style=\"color: $event_color\">$ann_event</td><td>$sentence</td></tr>\n");
}



=item get_sentence

Given a range of text indexes (e.g. "124:129"), it returns the sentence to which the range belongs.

=cut

sub get_sentence {
  my $range = shift;
  if ($range =~ /^(\d+):(\d+)/) {
    my ($start, $end) = ($1, $2);
    foreach my $root (@trees) { # go through all sentences
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

  mylog(0, "get_sentence_html: $range_auto, $range_manual\n");
  
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
  
  mylog(0, "get_sentence_html:   $start_auto, $end_auto, $start_manual, $end_manual\n");

  if ($end_auto > 0 or $end_manual > 0) { # at least one of the given ranges was properly defined

    my ($start, $end) = $end_auto > 0 ? ($start_auto, $end_auto) : ($start_manual, $end_manual); # for searching for the sentence
    mylog(0, "get_sentence_html:     start = $start, end = $end\n");

    foreach my $root (@trees) { # go through all sentences
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
  # mylog(0, "partial_match: input range: $range\n");
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
            # mylog(0, "partial_match:  - SUCCESS, matches with $r!\n");
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
  my $text = text(\@nodes);
  
  if ($event eq 'phrase') {
    $h_phrase_range2text{$range} = text(\@nodes);
    if ($ann_file) { # evaluate the event against manual annotation
      if ($h_ann_phrase_range2text{$range}) {
        print_eval('EVALUATION-EXACT-PHRASE-HIT', $range, $text, '-', $range, $text, '-');
        print_eval('EVALUATION-PARTIAL-PHRASE-HIT', $range, $text, '-', $range, $text, '-');
        mylog(0, "RELIABILITY_COUNT\t$lemma\t$constraint\tHIT\n");
      }
      else {
        print_eval('EVALUATION-EXACT-PHRASE-FALSE-POSITIVE', $range, $text, '-', 'N/A', 'N/A', '-');
        my $partial_phrase_range = partial_match($range, \%h_ann_phrase_range2text);
        if ($partial_phrase_range) {
          my $partial_text = $h_ann_phrase_range2text{$partial_phrase_range};
          print_eval('EVALUATION-PARTIAL-PHRASE-HIT', $range, $text, '-', $partial_phrase_range, $partial_text, '-');
          mylog(0, "RELIABILITY_COUNT\t$lemma\t$constraint\tHIT_PARTIAL\n");
        }
        else {
          print_eval('EVALUATION-PARTIAL-PHRASE-FALSE-POSITIVE', $range, $text, '-', 'N/A', 'N/A', '-');
          mylog(0, "RELIABILITY_COUNT\t$lemma\t$constraint\tFALSE_POSITIVE\n");
        }
      }
    }
  }
  else { # source
    $h_source_range2text{$range} = text(\@nodes);
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
  mylog(0, "evaluate_false_negatives: sentence $sent_start:$sent_end\n");

  # phrases
  foreach my $ann_phrase_range (keys(%h_ann_phrase_range2text)) {
    if ($ann_phrase_range =~ /^(\d+):(\d+)$/) {
      my ($s, $e) = ($1, $2);
      mylog(0, "evaluate_false_negatives:   ann phrase range $s:$e\n");
      next if ($e<$sent_start or $sent_end<$s); # choose only ranges from the given sentence
      mylog(0, "evaluate_false_negatives:     -within the sentence!\n");
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
      mylog(0, "evaluate_false_negatives:   ann source range $s:$e\n");
      next if ($e<$sent_start or $sent_end<$s); # choose only ranges from the given sentence
      mylog(0, "evaluate_false_negatives:     -within the sentence!\n");
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
  # mylog(0, "get_range: nodes: " . join(' ', map {attr($_, 'form')} @nodes) . "\n");
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
  # mylog(0, "get_range: result: $range\n");
  return $range;
}



=item get_whole_source

For the given source node, it collects all nodes representing the whole source.
The nodes are returned in left-right order.

=cut

sub get_whole_source_nodes {
  my $node = shift;
  my @source_nodes = get_source_nodes($node);
  push(@source_nodes, $node);

  # remove punctuation from the beginning and the end
  my @source_nodes_ordered = sort {attr($a, 'ord') <=> attr($b, 'ord')} @source_nodes;
  while (scalar(@source_nodes_ordered) > 1 and attr($source_nodes_ordered[0], 'deprel') eq 'punct') {
    shift @source_nodes_ordered;
  }
  while (scalar(@source_nodes_ordered) > 1 and attr($source_nodes_ordered[-1], 'deprel') eq 'punct') {
    pop @source_nodes_ordered;
  }

  return @source_nodes_ordered;
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
                    grep {attr($_, 'deprel') =~ /^(nmod|amod|flat|flat:foreign|case|acl:relcl|appos|punct)$/}
                    $node->getAllChildren;
  my @whole_source_nodes = @source_sons;
  foreach my $son (@source_sons) {
    push(@whole_source_nodes, get_source_nodes($son));
  }
  
  return @whole_source_nodes;
}


=item get_source_base_form

Given a list of the whole source nodes, it produces the base form of the source.
TODO! So far it only gives concatenated forms of the source nodes!

=cut

sub get_source_base_form {
  my @nodes = @_;
  my $source = join(' ', map {attr($_, 'form')} sort {attr($a, 'ord') <=> attr($b, 'ord')} @nodes);
  return $source;
}

=item

