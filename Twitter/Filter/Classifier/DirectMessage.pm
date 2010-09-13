package Twitter::Filter::Classifier::DirectMessage;
use base qw( Twitter::Filter::Classifier );

use Modern::Perl;



sub classify {
    my $class  = shift;
    my $filter = shift;
    my $tweet  = shift;
    my $tokens = shift;
    my @tags;
    
    push @tags, 'direct_message'
        if defined $tweet->{'direct_message'};
    
    return ( 0, @tags );
}

1;
