package Twitter::Filter::Collector;

use Modern::Perl;
use MooseX::FollowPBP;
use Moose;
use MooseX::Method::Signatures;

use Config::Std;
use IO::All  -utf8;
use IPC::DirQueue;
use Net::Twitter::Lite;
use Storable  qw( freeze thaw );

use constant TWEETS_PER_API_CALL     => 100;
use constant SLEEP_BETWEEN_API_CALLS => 3;
use constant MAX_API_ATTEMPTS        => 5;

has application => ( isa => 'Str',     is => 'ro', required => 1 );
has user        => ( isa => 'Str',     is => 'ro' );
has _state      => ( isa => 'HashRef', is => 'rw' );
has _config     => ( isa => 'HashRef', is => 'rw' );

has twitter     => ( isa     => 'Net::Twitter::Lite', is => 'rw' );
has queue       => ( 
        isa     => 'IPC::DirQueue', 
        is      => 'ro',
        builder => 'build_queue',
    );

method build_queue {
    return IPC::DirQueue->new( { dir => 'collected' } );
}
sub BUILD {
    my $self = shift;
    
    # get global configuration object
    read_config 'twitter.conf' => my %config;
    $self->{'_config'} = \%config;
    
    
    # get state object
    my $application = $self->get_application();
    my $user        = $self->get_user() // 'generic';
    my $state_file = sprintf 
                         'state/%s.%s',
                             $application, 
                             $user;
    
    if ( ! -f $state_file ) {
        my $default_state = '# autocreated at ' . scalar( gmtime ) . "\n";
        $default_state > io( $state_file );
    }
    
    read_config $state_file => my %state;
    $self->{'_state'} = \%state;
    
    # create twitter object
    my %options;
    if ( 'generic' ne $user ) {
        $options{'username'} = $user;
        $options{'password'} = $self->get_config( "user $user", 'password' );
    }
    
    my $twitter = Net::Twitter::Lite->new( %options );
    $self->set_twitter( $twitter );
}
sub DEMOLISH {
    my $self = shift;
    
    # save the configuration object
    write_config %{ $self->{'_state'} };
}


method get_searches {
    return $self->get_config_as_array( 'search', 'term' );
}
method get_stalked_users {
    return $self->get_config_as_array( 'stalk', 'screen_name' );
}


method queue_home_timeline {
    my $most_recent = $self->get_state( 'most_recent' ) // 1;
    
    my ( $count, $new_most_recent )
        = $self->queue_from_api_call( 
                'home_timeline', 
                {
                    since_id => $most_recent,
                },
            );
    
    if ( $count ) {
        $self->set_state( 'most_recent', $new_most_recent );
    }
    
    return $count;
}
method queue_user_timeline ( Str $user! ) {
    my $most_recent = $self->get_state( $user ) // 1;
    
    my ( $count, $new_most_recent )
        = $self->queue_from_api_call( 
            'user_timeline', 
            {
                screen_name => $user,
                since_id    => $most_recent,
            }
        );
    
    if ( $count ) {
        $self->set_state( $user, $new_most_recent );
    }
    
    return $count;
}
method queue_search ( Str $term! ) {
    my $most_recent = $self->get_state( $term ) // 1;
    
    my ( $count, $new_most_recent ) 
        = $self->queue_from_search( 
                {
                    q        => $term,
                    since_id => $most_recent,
                }
            );
    
    if ( $count ) {
        $self->set_state( $term, $new_most_recent );
    }
    
    return $count;
}
method queue_from_api_call ( Str $method!, HashRef $options! ) {
    my $twitter         = $self->get_twitter();
    my $latest_tweet    = $options->{'since_id'};
    my $page            = 1;
    my $tweet_count     = 0;
    my $failed_attempts = 0;
    
    FETCH:
    while ( 1 ) {
        $failed_attempts++;
        last FETCH if $failed_attempts > MAX_API_ATTEMPTS;
        
        my $statuses;
        $options->{'page'}  = $page;
        $options->{'count'} = TWEETS_PER_API_CALL;
        
        eval {
            $statuses = $twitter->$method( $options );
            sleep SLEEP_BETWEEN_API_CALLS;
        };
        if ( $@ ) {
            my $error = $@;     # is actually Net::Twitter::Lite::Error
            
            # API sometimes returns near-empty HTML pages
            # instead of data ... most curious
            next FETCH if ( 200 == $error->code );
            
            say 'ERROR ' . $error->code;
            say $error->message;
            say $error->twitter_error;
            use Data::Dumper;
            say Dumper $error->http_response;
            die q();
        }
        
        use Data::Dumper;
        print Dumper $statuses;
        
        last FETCH if -1 == $#$statuses;
        
        $failed_attempts = 0;
        $page++;
        
        foreach my $status ( @{ $statuses } ) {
            $tweet_count++;
            
            if ( $latest_tweet < $status->{'id'} ) {
                $latest_tweet = $status->{'id'};
            }
            
            say '-> ' 
              . $status->{'user'}{'screen_name'}
              . ' [' . $status->{'id'} . '] '
              . $status->{'text'};
            
            $self->queue_tweet( $status );
        } 
    }

    return( $tweet_count, $latest_tweet );
}
method queue_from_search ( HashRef $options! ) {
    my $twitter         = $self->get_twitter();
    my $latest_tweet    = $options->{'since_id'};
    my $page            = 1;
    my $tweet_count     = 0;
    my $failed_attempts = 0;
    
    FETCH:
    while ( 1 ) {
        $failed_attempts++;
        last FETCH if $failed_attempts > MAX_API_ATTEMPTS;
        
        my $results;
        $options->{'page'}  = $page;
        $options->{'count'} = TWEETS_PER_API_CALL;
        
        eval {
            $results = $twitter->search( $options );
            sleep SLEEP_BETWEEN_API_CALLS;
        };
        if ( $@ ) {
            my $error = $@;     # is actually Net::Twitter::Lite::Error
            
            say 'ERROR ' . $error->code;

            # API sometimes returns near-empty HTML pages
            # instead of data ... most curious
            next FETCH if ( 200 == $error->code );
            
            say $error->message;
            say $error->twitter_error;
            use Data::Dumper;
            say Dumper $error->http_response;
            die q();
        }
        
        # search API returns useful metadata
        my $statuses         = $results->{'results'};
        my $results_per_page = $results->{'results_per_page'};
           $latest_tweet     = $results->{'max_id'};
        
        # no search results
        last FETCH if -1 == $#$statuses;
        
        $failed_attempts = 0;
        $page++;
        
        foreach my $status ( @{ $statuses } ) {
            $tweet_count++;
            
            say '-> ' 
              . $status->{'from_user'}
              . ' [' . $status->{'id'} . '] '
              . $status->{'text'};
            
            $self->queue_tweet( $status );
        }
        
        # no more statuses to find
        last FETCH if ( $#$statuses + 1 ) < $results_per_page;
    }

    return( $tweet_count, $latest_tweet );
}
method queue_tweet ( HashRef $tweet ) {
    my $string = freeze $tweet;
    my $queue  = $self->get_queue();
    
    $queue->enqueue_string( $string );
}


method get_config ( Str $section!, Str $key! ) {
    my $config = $self->{'_config'};
    return $config->{ $section }{ $key };
}
method get_config_as_array ( Str $section!, Str $key! ) {
    my $config = $self->{'_config'};
    my $result = $config->{ $section }{ $key };
    my @results;
    
    if ( 'ARRAY' eq ref( $result ) ) {
        push @results, @{ $result };
    }
    else {
        push @results, $result;
    }
    
    return @results;
}
method set_config ( Str $section!, Str $key!, $value! ) {
    my $config = $self->{'_config'};
    $config->{ $section }{ $key } = $value;
}
method get_state  ( Str $key! ) {
    return $self->{'_state'}{''}{ $key };
}
method set_state  ( Str $key!, $value! ) {
    $self->{'_state'}{''}{ $key } = $value;
}


1;
