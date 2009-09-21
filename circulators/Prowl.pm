package Twitter::Filter::Circulator::Prowl;

use Modern::Perl;

use WebService::Prowl;

use constant HIGH_PRIORITY => 8;

my $prowl;



sub initialise {
    my $self = shift;
    my $you  = shift;
    
    my $config = $you->get_plugin_config();
    
    $prowl = WebService::Prowl->new( apikey => $config->{''}{'api_key'} );
    $prowl->verify() 
        or die $prowl->error();
}

sub circulate {
    my $self       = shift;
    my $circulator = shift;
    my $item       = shift;
    
    my $tweet             = $item->{'tweet'};
    my $prowl_application = '';
    
    # send DMs
    if ( defined $tweet->{'direct_message'} ) {
        $prowl_application = 'Twitter DM';
    }
    
    # send @mentions
    foreach my $tag ( @{ $item->{'tags'} } ) {
        if ( 'mention' eq $tag ) {
            $prowl_application = 'Twitter Mention';
        }
    }
    
    # send high priority tweets
    if ( $item->{'score'} > HIGH_PRIORITY ) {
        $prowl_application = "Twitter Prio $item->{'score'}";
    }
    
    if ( $prowl_application ) {
        $prowl->add(
                application => $prowl_application,
                event       => $tweet->{'user_account'} // 'x',
                description => $tweet->{'text'},
            );
    }
    
    return;
}

1;
