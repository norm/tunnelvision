package Twitter::Filter::Collector;

use Modern::Perl;
use MooseX::FollowPBP;
use Moose;
use MooseX::Method::Signatures;

with 'Twitter::Filter::State';
with 'Twitter::Filter::Config';

use IO::All  -utf8;
use IPC::DirQueue;
use Net::Twitter::Lite;
use Storable  qw( freeze );

use constant TWEETS_PER_API_CALL     => 100;
use constant SLEEP_BETWEEN_API_CALLS => 1;
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
    return IPC::DirQueue->new( { dir => 'queues/collected' } );
}
method BUILD {
    $self->{'_config'} = $self->read_global_config();
    
    # get state object
    my $application = $self->get_application();
    my $user        = $self->get_user() // 'generic';
    my $state_file  = sprintf 
                         '%s.%s',
                             $application, 
                             $user;
    
    $self->{'_state'} = $self->read_state( $state_file );
    
    # create twitter object
    my %options;
    if ( 'generic' ne $user ) {
        $options{'username'} = $user;
        $options{'password'} = $self->get_config( "user $user", 'password' );
    }
    
    my $twitter = Net::Twitter::Lite->new( %options );
    $self->set_twitter( $twitter );
}
method DEMOLISH {
    $self->save_state();
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
method queue_tweet ( HashRef $tweet ) {
    my $string = freeze $tweet;
    my $queue  = $self->get_queue();
    
    $queue->enqueue_string( $string );
}


method get_state  ( Str $key! ) {
    return $self->{'_state'}{''}{ $key };
}
method set_state  ( Str $key!, $value! ) {
    $self->{'_state'}{''}{ $key } = $value;
}

1;
