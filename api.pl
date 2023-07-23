#!/usr/bin/env perl

=item
# skript se na serveru spustí pomocí
morbo api.pl

# Pak naslouchá na defaultním portu 3000 a lokálně funguje např.:
curl http://localhost:3000/api/test

# Perlovský balíček Mojolicious obsahující i příkaz morbo se instaloval pomocí 
sudo apt-get install libmojolicious-perl

# Pro přesměrování požadavků z Apache2 bylo mj. potřeba nastavit v /etc/apache2/sites-available/000-default.conf v sekci <VirtualHost *:80>:
        ServerName localhost
	# Proxy pro /api/detect a /api/test
        ProxyPass "/api/detect" "http://localhost:3000/api/detect"
        ProxyPassReverse "/api/detect" "http://localhost:3000/api/detect"
        ProxyPass "/api/test" "http://localhost:3000/api/test"
        ProxyPassReverse "/api/test" "http://localhost:3000/api/test"
# A v /etc/apache2/apache2.conf bylo potřeba přidat:
	LoadModule proxy_module modules/mod_proxy.so
	LoadModule proxy_http_module modules/mod_proxy_http.so
# Pak funguje např.
curl http://localhost/api/test

=cut


use Mojolicious::Lite;

# Endpoint pro test
get '/api/test' => sub {
    my $c = shift;
    $c->render(json => { message => 'This is the test function.' });
};

# Endpoint pro detect
get '/api/detect' => sub {
    my $c = shift;
    $c->render(json => { message => 'This is the detect function.' });
};

app->start;

