package Twitter::Filter::Plugin::ProwlSearches;
use base qw( Twitter::Filter::Plugin );

use Modern::Perl;



sub _order { 50; }

sub classify {
    my $class  = shift;
    my $filter = shift;
    my $tweet  = shift;
    my $tokens = shift;
    my @tags;
    
    my $origin = $tweet->{'origin'} // '';
    
    push @tags, 'prowl'
        if 'search' eq $origin;
    
    return ( 0, @tags );
}

1;
