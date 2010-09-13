package Twitter::Filter::Classifier::SearchResult;
use base qw( Twitter::Filter::Classifier );

use Modern::Perl;



sub classify {
    my $class  = shift;
    my $filter = shift;
    my $tweet  = shift;
    my $tokens = shift;
    my @tags;
    
    my $origin = $tweet->{'origin'} // '';
    
    push @tags, 'search'
        if 'search' eq $origin;
    
    return ( 0, @tags );
}

1;
