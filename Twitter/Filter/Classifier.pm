package Twitter::Filter::Classifier;

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
use constant BAYES_STATE_FILE    => 'state/bayes.db';
use constant WORD_IS_HASHTAG     => qr{^ [#] ( .+ ) $}x;
use constant WORD_IS_MENTION     => qr{
        ^
        [^a-zA-Z0-9_]*          # start with things other than account chars
        [@] ( [a-zA-Z0-9_]+ )   # followed by a normal @user construct
        $
    }ix;

use Algorithm::NaiveBayes;
use Algorithm::NaiveBayes::Model::Frequency;
use File::stat;
use IPC::DirQueue;
use Module::Pluggable   require     => 1,
                        search_path => [ PLUGIN_CLASS ];
use Storable            qw( freeze thaw );

has state_timestamp => ( isa => 'Int', is => 'rw' );
has _config         => ( isa => 'HashRef', is => 'rw' );
has classifiers     => (
        isa     => 'ArrayRef',
        is      => 'ro',
        builder => 'build_classifiers',
    );
has in_queue        => (
        isa     => 'IPC::DirQueue', 
        is      => 'ro',
        builder => 'build_in_queue',
    );
has out_queue       => (
        isa     => 'IPC::DirQueue', 
        is      => 'ro',
        builder => 'build_out_queue',
    );
has current_job     => (
        isa => 'IPC::DirQueue::Job',
        is  => 'rw',
    );
has bayes_state     => (
        isa => 'Algorithm::NaiveBayes::Model::Frequency',
        is  => 'rw',
    );

method build_in_queue {
    return IPC::DirQueue->new( { dir => 'queues/collected' } );
}
method build_out_queue {
    return IPC::DirQueue->new( { dir => 'queues/classified' } );
}
method build_classifiers {
    my $plugins = $self->build_plugins( 
            dir    => 'classifiers',
            method => 'classify',
            class  => 'Twitter::Filter::Classifier',
        );
    
    return $plugins;
}
method BUILD {
    $self->{'_config'} = $self->read_global_config();
}


method classify_tweet ( HashRef $tweet ) {
    my %tokens      = $self->tweet_token_list( $tweet );
    my $final_score = 0;
    my %final_tags;
    my @buckets;
    
    # run tweet through each classifier plugin, collecting tags and score
    foreach my $classifier ( @{ $self->get_classifiers } ) {
        my ( $score, @tags ) 
            = $classifier->classify( $self, $tweet, \%tokens );
        
        $final_score += $score
                     // 0;
        
        foreach my $tag ( @tags ) {
            $final_tags{ $tag } = 1;
        }
    }

    my @tags = keys %final_tags;
    
    # run tweet through bayesian classification, putting it into buckets
    # where the likelihood of belonging is greater than 3/4s
    my $buckets = $self->get_tweet_buckets( $tweet, \%tokens );
    foreach my $bucket ( keys %{ $buckets } ) {
        if ( 0.75 < $buckets->{ $bucket } ) {
            push @buckets, $bucket;
        }
    }
    
    return $final_score, \@tags, \@buckets;
}
method tweet_token_list ( HashRef $tweet ) {
    my $text = $tweet->{'text'};
    my $user = $tweet->{'user'}{'screen_name'};
    
    # who the tweet is from could be an important factor
    my %tokens = (
            'attr:user' => $user,
        );
    
    foreach my $word ( split( /\s+/, $text ) ) {
        $tokens{ $word }++;
        
        # weight the words with the person who said them
        my $user_word = "${user}%${word}";
        $tokens{ $user_word }++;
        
        # add metadata about special words
        if ( $word =~ WORD_IS_MENTION ) {
            $tokens{'attr:mention'}++;
            $tokens{"mention:$1"}++;
        }
        if ( $word =~ WORD_IS_HASHTAG ) {
            $tokens{'attr:hashtag'}++;
            $tokens{"hashtag:$1"}++;
        }
    }
    
    return %tokens;
}
method get_tweet_buckets ( HashRef $tweet, HashRef $tokens ) {
    $self->reload_bayes_state();
    my $bayes = $self->get_bayes_state();
    
    # beware: bayes object will not exist when nothing has been trained
    if ( defined $bayes ) {
        return $bayes->predict( attributes => $tokens );
    }
    
    return;
}
method reload_bayes_state {
    my $stat = stat( BAYES_STATE_FILE );
    if ( $stat ) {
        if ( $stat->mtime > $self->get_state_timestamp() ) {
            $self->set_bayes_state( 
                    Algorithm::NaiveBayes->restore_state( BAYES_STATE_FILE )
                );
            $self->set_state_timestamp( $stat->mtime );
        }
    }
}


method get_next_tweet {
    my $queue    = $self->get_in_queue();
    
    my $job      = $queue->wait_for_queued_job( 
                           QUEUE_TIMEOUT, QUEUE_POLL_INTERVAL 
                       );
    my $contents = $job->get_data();
    
    $self->set_current_job( $job );
    
    return thaw( $contents );
}
method cancel_processing {
    my $job = $self->get_current_job();
    
    $job->return_to_queue();
}
method finished_processing {
    my $job = $self->get_current_job();
    
    $job->finish();
}
method queue_tweet ( HashRef $tweet ) {
    my $string = freeze $tweet;
    my $queue  = $self->get_out_queue();
    
    $queue->enqueue_string( $string );
}


1;
