tunnelvision - a twitter filter
===============================
*tunnelvision* is a group of perl scripts and library code to deal with
fetching, storing, categorising and rebroadcasting tweets.

This is better (for me, anyway) than a simple iPhone or OS X twitter client
because I can program it to do other, cleverer, things than just show me
tweets. For example:

* mark things as "seen", so I don't end up reading the same tweet over again
  on different devices
* mail a summary of the things I might deem important that I haven't seen
  recently for those periods when I am not paying attention
* send tweets that mention me, or new results for a saved search, straight to
  my phone as an alert using [Prowl][prowl]
* "snooze" a user doing something distasteful (such as liveblogging an event I
  am not interested in), rather than unfollow and have to remember to refollow
  later
* roll up tweets that mention the same URL (a la retweeting)

Do note that whilst I am running this code 24/7 for myself, it is not
documented (other than this readme) and probably not ready for prime-time just
yet. To illustrate, it currently expects to run out of the check-out
directory.

Broad architecture
------------------
Conceptually, *tunnelvision* is split into three distinct types of code:

* _Collectors_: fetch new tweets from Twitter and save them to the
  database
* _Classifiers_: categorise new tweets according to priority, spamminess,
  group, etc.
* _Circulators_: broadcast tweets back to me, either directly (eg. via
  [Prowl][prowl]) or in the form of a website

Pre-requisites
--------------
### Database
*tunnelvision* uses [CouchDB][couchdb] to store tweets. It currently expects
to connect to 'localhost' on the standard port and use a database called
'twitter'.

### CPAN modules
I am using a *lot* of external CPAN modules in this project.

* Moose
* MooseX::FollowPBP
* MooseX::Method::Signatures
* Net::Twitter
* AnyEvent::Twitter::Stream
* DB::CouchDB
* Plack
* ... and many more (this list is definitely *not* complete)

If you are playing with this, I recommend installing any CPAN modules with the
truly excellent [cpanm][cpanm] script, like so:

    sudo cpanm Moose MooseX::FollowPBP MooseX::Method::Signatures \
               Net::Twitter AnyEvent::Twitter::Stream DB::CouchDB \
               Plack ...

TODO
----
Finish writing the code (the more verbose todo list is kept in
`tunnelvision.taskpaper`).



[prowl]:http://prowl.weks.net/
[couchdb]:http://couchdb.apache.org/
[cpanm]:http://cpanmin.us/
