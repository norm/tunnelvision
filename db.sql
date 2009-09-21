CREATE TABLE user (
    id                              integer     PRIMARY KEY,
    name                            text,
    screen_name                     text,
    friends_count                   integer,
    profile_image_url               text,
    profile_sidebar_fill_color      text,
    profile_sidebar_border_color    text,
    url                             text
);
CREATE TABLE tweet (
    id                              integer     PRIMARY KEY,
    user_id                         integer,
    favorited                       integer     DEFAULT 0,
    truncated                       integer     DEFAULT 0,
    created_at                      integer     NOT NULL,
    in_reply_to_user_id             integer,
    in_reply_to_status_id           integer,
    in_reply_to_screen_name         text,
    text                            text,
    source                          text,
    score                           integer     DEFAULT 0,
    seen                            integer     DEFAULT 0,
    
    FOREIGN KEY ( user_id )         REFERENCES user( id )
);
CREATE TABLE tag (
    tweet_id                        integer,
    text                            text,
    
    UNIQUE ( tweet_id, text )
);
CREATE TABLE bucket (
    tweet_id                        integer,
    text                            text,
    
    UNIQUE ( tweet_id, text )
);
