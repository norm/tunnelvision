package Twitter::Filter::Classifier::Mention;
use base qw( Twitter::Filter::Classifier );

use Modern::Perl;



sub classify {
    my $class  = shift;
    my $filter = shift;
    my $tweet  = shift;
    my $tokens = shift;
    my @tags;
    
    if ( defined $tokens->{'attr:mention'} ) {
        my @users = $filter->get_config_users();
        foreach my $user ( @users ) {
            push @tags, 'mention'
                if defined $tokens->{"mention:$user"};
        }
    }
    
    return ( 0, @tags );
}

1;
