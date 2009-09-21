package Twitter::Filter::Classifier::Mention;

use Modern::Perl;



sub classify {
    my $self       = shift;
    my $classifier = shift;
    my $tweet      = shift;
    my $tokens     = shift;
    
    my @tags;
    
    if ( defined $tokens->{'attr:mention'} ) {
        foreach my $user ( $classifier->get_config_users() ) {
            if ( defined $tokens->{"mention:$user"} ) {
                push @tags, 'mention';
            }
        }
    }
    
    return ( 0, @tags );
}

1;
