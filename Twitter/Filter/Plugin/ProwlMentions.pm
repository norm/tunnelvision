package Twitter::Filter::Plugin::ProwlMentions;
use base qw( Twitter::Filter::Plugin );

use Modern::Perl;



sub _order { 50; }

sub classify {
    my $class  = shift;
    my $filter = shift;
    my $tweet  = shift;
    my $tokens = shift;
    my @tags;
    
    if ( defined $tokens->{'attr:mention'} ) {
        my @users = $filter->get_config_users();
        foreach my $user ( @users ) {
            push @tags, 'prowl'
                if defined $tokens->{"mention:$user"};
        }
    }
    
    return ( 0, @tags );
}

1;
