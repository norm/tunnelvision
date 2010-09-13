package Twitter::Filter::Classifier::Lists;
use base qw( Twitter::Filter::Classifier );

use Modern::Perl;



sub classify {
    my $class  = shift;
    my $filter = shift;
    my $tweet  = shift;
    my $tokens = shift;
    my @tags;
    
    my %lists = $filter->get_twitter_lists();
    foreach my $list ( keys %lists ) {
        foreach my $id ( @{ $lists{ $list } } ) {
            push @tags, $list
                if ( $id == $tweet->{'sender_id'} );
        }
    }
    
    return ( 0, @tags );
}

1;
