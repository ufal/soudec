#!/usr/bin/env perl

# skript se na serveru spustí pomocí
# morbo api.pl

# Pak naslouchá na defaultním portu 3000 a lokálně funguje např.:
# curl http://localhost:3000/api/test

# Perlovský balíček Mojolicious obsahující i příkaz morbo se instaloval pomocí 
# sudo apt-get install libmojolicious-perl

# Pro přesměrování požadavků z Apache2 bylo mj. potřeba nastavit v /etc/apache2/sites-available/000-default.conf v sekci <VirtualHost *:80>:
#        ServerName localhost
#        # Proxy pro /api/detect a /api/test
#        ProxyPass "/api/detect" "http://localhost:3000/api/detect"
#        ProxyPassReverse "/api/detect" "http://localhost:3000/api/detect"
#        ProxyPass "/api/test" "http://localhost:3000/api/test"
#        ProxyPassReverse "/api/test" "http://localhost:3000/api/test"
# A v /etc/apache2/apache2.conf bylo potřeba přidat:
#        LoadModule proxy_module modules/mod_proxy.so
#        LoadModule proxy_http_module modules/mod_proxy_http.so
# Pak funguje např.
# curl http://localhost/api/test


use Mojolicious::Lite;

# Endpoint pro test
any '/api/test' => sub {
    my $c = shift;
    if ($c->req->method eq 'POST') {
        # Zde můžete zpracovat data odeslaná v těle požadavku POST
        my $data = $c->req->json;
        # Pro ilustraci jen odeslat data zpět jako odpověď
        return $c->render(json => { message => 'This is the test function called via POST.',
                                    result => 'A dummy result' });
    }
    else {
        # Zpracování GET požadavku stejně jako dříve
        return $c->render(json => { message => 'This is the test function called via GET.',
                                    result => 'A dummy result' });
    }
};

# Endpoint pro detect
any '/api/detect' => sub {
    my $c = shift;
    if ($c->req->method eq 'POST') {

        # Zde můžete zpracovat data odeslaná v těle požadavku POST
	# my $data = $c->req->json;
        my $text = $c->param('text'); # input text
        my $input_format = $c->param('input'); # input format
        my $output_format = $c->param('output'); # output format

        # Pro ilustraci jen odeslat data zpět jako odpověď
        return $c->render(json => { message => 'This is the detect function called via POST.',
                                    result => "input format: '$input_format', output format: '$output_format', text: '$text'" });
    }
    else { # GET

        # Přečtěte parametry z GET requestu
        my $text = $c->param('text'); # input text
        my $input_format = $c->param('input'); # input format
        my $output_format = $c->param('output'); # output format

        # Zpracování GET požadavku
        return $c->render(json => { message => 'This is the detect function called via GET.',
                                    result => "input format: '$input_format', output format: '$output_format', text: '$text'" });
    }
};

app->start;

