#!/usr/bin/env plackup

use strict;
use warnings;
use utf8;

use DBD::Pg;
use JSON;
use Encode ();

my $coder = JSON->new->pretty->canonical->utf8;

my $dsn = $ENV{'HORTENFV_KORTLESER_DSN'} // 'dbi:Pg:dbname=kortleser;host=fvdbprod.postgres.database.azure.com;sslmode=require';
my $user = $ENV{'HORTENFV_KORTLESER_USER'} // 'kortleser@fvdbprod';
my $password = $ENV{'HORTENFV_KORTLESER_PASSWORD'};
die("Please specify HORTENFV_KORTLESER_PASSWORD\n")
    unless defined $password;
die("Please ensure HORTENFV_KORTLESER_PASSWORD is set to a value\n")
    if length($password) == 0;
my $dbh = DBI->connect($dsn, $user, $password)
    or die("Unable to connect to database $dsn with user $user and specified password\n");

my $db_query = <<EOM;
WITH last_swipe AS (
  SELECT max(swiped_at) AS var
  FROM swipes
  LIMIT 1
),
unique_swipes_interval AS (
  SELECT interval '3 hours' AS var
),
unique_swipes_since AS (
  SELECT CURRENT_TIMESTAMP - (SELECT var from unique_swipes_interval) AS var
),
unique_swipes AS (
  SELECT DISTINCT badge_id
  FROM swipes
  WHERE swiped_at > (SELECT var from unique_swipes_since)
),
unique_swipes_count AS (
  SELECT count(*) AS var
  FROM unique_swipes
  LIMIT 1
)
SELECT
 (SELECT var FROM last_swipe) AS last_swipe,
 (SELECT var FROM unique_swipes_interval) AS unique_swipes_interval,
 (SELECT var FROM unique_swipes_since) AS unique_swipes_since,
 (SELECT var FROM unique_swipes_count) AS unique_swipes_count
EOM

my $app = sub {
    my ($env) = @_;
    my $path_info = $env->{'PATH_INFO'} // '/';
    my $path = substr $path_info, 1;
    my (@path) = split '/', $path;    
    my $route = shift (@path) // 'html';
    my $ds = shift @{ sql($db_query) // [] };
    if ( $route eq 'json' ) {
        my $payload = $coder->encode($ds);
        return [
            '200',
            [ 'Content-Type'   => 'application/json', ],
            [ $payload ],
        ];
    }
    if ( $route eq 'html' ) {
        my $payload = Encode::encode('UTF-8', <<"EOM");
<!DOCTYPE html>
<html>
<head>
<title>Status kortleser</title>
</head>
<body>
<ul>
<li>Siste besøk: $ds->{'last_swipe'}</li>
<li>Antall besøkende siden $ds->{'unique_swipes_since'}: $ds->{'unique_swipes_count'}
</ul>
</body>
</html>
EOM
        return [
            '200',
            [ 'Content-Type'   => 'text/html; charset=UTF-8', ],
            [ $payload ],
        ];
    }
    return [
        '200',
        [ 'Content-Type' => 'text/plain; charset=UTF-8' ],
        [ 'Please specify path /html or /json.' ],
    ];
};

sub sql {
    my ($query, @bind_params) = @_;
    my $sth = $dbh->prepare($query);
    $sth->execute(@bind_params);
    return $sth->fetchall_arrayref({});
}

$app;
