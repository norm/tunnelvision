package Twitter::Filter::Classifier::Direct;

use Modern::Perl;



sub classify {
    my $self       = shift;
    my $classifier = shift;
    my $tweet      = shift;
    my $tokens     = shift;
    
    my @tags;
    
    if ( defined $tweet->{'direct_message'} ) {
        push @tags, 'direct';
    }
    
    return ( 0, @tags );
}

1;
