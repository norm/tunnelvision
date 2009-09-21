package Twitter::Filter::Circulator;

use Modern::Perl;
use MooseX::FollowPBP;
use Moose;
use MooseX::Method::Signatures;

with 'Twitter::Filter::State';
with 'Twitter::Filter::Config';
with 'Twitter::Filter::Plugins';

use constant PLUGIN_CLASS        => 'Twitter::Filter::Classifier';
use constant QUEUE_TIMEOUT       => 0;      # 0 means "wait indefinitely"
use constant QUEUE_POLL_INTERVAL => 15;

use IPC::DirQueue;
use Module::Pluggable   require     => 1,
                        search_path => [ PLUGIN_CLASS ];
use Storable            qw( freeze thaw );

has queue       => (
        isa     => 'IPC::DirQueue', 
        is      => 'ro',
        builder => 'build_queue',
    );
has circulators => (
        isa     => 'ArrayRef',
        is      => 'ro',
        builder => 'build_circulators',
    );
has current_job => (
        isa => 'IPC::DirQueue::Job',
        is  => 'rw',
    );

method build_queue {
    return IPC::DirQueue->new( { dir => 'queues/classified' } );
}
method build_circulators {
    my $plugins = $self->build_plugins( 
            dir    => 'circulators',
            method => 'circulate',
            class  => 'Twitter::Filter::Circulator',
        );
    
    return $plugins;
}



method get_next_tweet {
    my $queue    = $self->get_queue();
    
    my $job      = $queue->wait_for_queued_job( 
                           QUEUE_TIMEOUT, QUEUE_POLL_INTERVAL 
                       );
    my $contents = $job->get_data();
    
    $self->set_current_job( $job );
    
    return thaw( $contents );
}
method circulate_tweet ( HashRef $tweet! ) {
    my $any_blocked = 0;
    
    say $tweet->{'tweet'}{'text'};
    
    CIRCULATOR:
    foreach my $circulator ( @{ $self->get_circulators() } ) {
        next CIRCULATOR if defined $tweet->{'circulated'}{ $circulator };
        
        my $blocked = $circulator->circulate( $self, $tweet );
        
        if ( $blocked ) {
            $any_blocked = 1;
        }
        else {
            $tweet->{'circulated'}{ $circulator } = 1;
        }
    }
    
    return $any_blocked;
}
method finished_processing {
    my $job = $self->get_current_job();
    
    $job->finish();
}
method requeue_tweet ( HashRef $tweet! ){
    my $string = freeze $tweet;
    my $queue  = $self->get_queue();
    my $job    = $self->get_current_job();
    
    # Rather than "return to queue", remove the queue item and
    # requeue to allow other tweets to flush through the queue if 
    # the problem was specific to this tweet. It also means we store
    # the details of what has and hasn't been processed already.
    $job->finish();
    $queue->enqueue_string( $string );
}

1;
