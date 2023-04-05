#!/usr/bin/env plackup

use strict;
use warnings;

use DBD::Pg;
use JSON;

my $coder = JSON->new->pretty->canonical->utf8;

my $dsn = $ENV{'HORTENFV_KORTLESER_DSN'} // 'dbi:Pg:dbname=kortleser;host=fvdbprod.postgres.database.azure.com';
my $user = $ENV{'HORTENFV_KORTLESER_USER'} // 'kortleser@fvdbprod';
my $password = $ENV{'HORTENFV_KORTLESER_PASSWORD'};
die("Please specify HORTENFV_KORTLESER_PASSWORD\n")
    unless defined $password;
die("Please ensure HORTENFV_KORTLESER_PASSWORD is set to a value\n")
    if length($password) == 0;
my $dbh = DBI->connect($dsn, $user, $password)
    or die("Unable to connect to database $dsn with user $user and specified password\n");

my $app = sub {
    my ($env) = @_;
    my $ds = sql('SELECT max(swiped_at) FROM swipes');
    return [
        '200',
        [ 'Content-Type' => 'text/plain' ],
        [ $coder->encode($ds) ],
    ];
};

sub sql {
    my ($query, @bind_params) = @_;
    my $sth = $dbh->prepare($query);
    $sth->execute(@bind_params);
    return $sth->selectall_arrayref({});
}

$app;