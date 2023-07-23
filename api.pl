#!/usr/bin/env perl

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

