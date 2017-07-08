use DBI;
use strict;
use warnings;

our %config = (
	dbserver => 'localhost',
	dbuser   => 'root',	
	dbname   => 'XDCCSPIDER',
	dbpasswd => '',
	debug    => 0,
	maintain_connections_interval => 120,
	maintain_database_interval => 180
);

# print debug messages
sub debug_out {
	my ( $text, $errorlevel ) = @_;
	return unless defined $config{'debug'};
	$text =~ s/\n//;
	$errorlevel = 0 unless defined($errorlevel);
	print STDERR $text . "\n" if $errorlevel >= $config{'debug'};
}
# return open database handle
sub get_database {		
	my $db_handle = DBI->connect_cached(
		"DBI:mysql:database=$config{dbname};host=$config{dbserver}",
		$config{'dbuser'}, $config{'dbpasswd'} )
	  or debug_out("failed to connect to database");
	return $db_handle;
}
# generate a random string
sub get_random_name
{
	my ($len) = @_;
	$len = 8 unless $len;
	my $name;
	$name .= chr(rand(26) + 97) for(1..$len);
	return $name;
}

1;