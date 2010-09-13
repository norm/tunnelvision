package Twitter::Filter::Plugin::Prowl;
use base qw( Twitter::Filter::Plugin );

use Modern::Perl;
use WebService::Prowl;

my $prowl;



sub initialise {
    my $class  = shift;
    my $filter = shift;
    
    my $config = $filter->get_plugin_config();
    
    if ( defined $config->{''}{'api_key'} ) {
        $prowl = WebService::Prowl->new( 
                apikey => $config->{''}{'api_key'},
            );
        my $ok = $prowl->verify();
        
        if ( !$ok ) {
            warn "** Cannot start Prowl:"
               . $prowl->error();
            return 0;
        }
    }
    else {
        warn '** No API key defined for Prowl: disabling sending.';
        return 0;
    }
    
    return 1;
}

sub circulate {
    my $class  = shift;
    my $filter = shift;
    my $tweet  = shift;
    
    foreach my $tag ( @{ $tweet->{'tags'} } ) {
        if ( 'prowl' eq $tag ) {
            my $user = $filter->get_screen_name( $tweet->{'sender_id'} );
            $prowl->add(
                    application => 'Twitter',
                    event       => $user,
                    description => $tweet->{'text'},
                );
        }
    }
    
    return;
}

1;
