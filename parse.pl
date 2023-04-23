#!/usr/bin/perl
use strict;
use warnings;
use utf8;
use LWP::UserAgent;
use URI::Escape;
use JSON;

my $file_name = shift @ARGV;

open my $file_handle, '<:encoding(utf8)', $file_name
  or die "Nepodařilo se otevřít soubor '$file_name' pro čtení: $!";

# Načtení obsahu souboru do proměnné
my $file_content = do { local $/; <$file_handle> };

close $file_handle;

print $file_content;
call_udpipe($file_content);

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
        print "Výsledek: $json_response->{result}\n";
    } else {
        print "Chyba: " . $res->status_line . "\n";
    }
}

