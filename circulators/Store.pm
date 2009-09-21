package Twitter::Filter::Circulator::Store;

use Modern::Perl;

use Twitter::Filter::Database;

my $database = Twitter::Filter::Database->new();



sub circulate {
    my $self       = shift;
    my $circulator = shift;
    my $tweet      = shift;
    
    $database->store_tweet( $tweet );
}

1;
