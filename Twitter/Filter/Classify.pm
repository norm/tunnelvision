package Twitter::Filter::Classify;

use Modern::Perl;
use Moose::Role;
use MooseX::Method::Signatures;

use constant BAYES_STATE_FILE => 'state/bayes.db';
use constant WORD_IS_HASHTAG  => qr{^ [#] ( .+ ) $}x;
use constant WORD_IS_MENTION  => qr{
        ^
        [^a-zA-Z0-9_]*          # start with things other than account chars
        [@] ( [a-zA-Z0-9_]+ )   # followed by a normal @user construct
        [^a-zA-Z0-9_]*          # optional other noise
        $
    }ix;

has bayes_state_timestamp => (
        isa => 'Int',
        is  => 'rw'
    );
has bayes_state => (
        isa => 'Algorithm::NaiveBayes::Model::Frequency',
        is  => 'rw',
    );



method classify_tweet ( HashRef $tweet ) {
    my %tokens      = $self->tweet_token_list( $tweet );
    my $final_score = 0;
    my %final_tags;
    my @buckets;
    
    # run tweet through each classifier plugin, collecting tags and score
    foreach my $classifier ( @{ $self->get_classifiers() } ) {
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
    my $user = $self->get_screen_name( $tweet->{'sender_id'} );
    my $text = $tweet->{'text'};
    
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
        if ( $stat->mtime > $self->get_bayes_state_timestamp() ) {
            $self->set_bayes_state( 
                    Algorithm::NaiveBayes->restore_state( BAYES_STATE_FILE )
                );
            $self->set_bayes_state_timestamp( $stat->mtime );
        }
    }
}

1;
